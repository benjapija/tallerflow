import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/models.dart';
import 'package:tallerflow/domain/quotes.dart';

Map<String, dynamic> draft(WorkOrder o) => {
  'id': 'quote-test',
  'expectedVersion': 0,
  'title': 'Prueba',
  'reason': 'Alcance inicial',
  'validUntil': '2026-11-01T00:00:00Z',
  'lines': [
    {
      'id': 'line-test',
      'taskId': o.tasks.first['id'],
      'description': 'Trabajo ficticio',
      'laborMinutes': 30,
      'parts': [
        {
          'reference': 'OIL',
          'description': 'Aceite ficticio',
          'unit': 'litro',
          'quantityMilli': 1500,
          'unitPriceCents': 1001,
          'taxBps': 2100,
          'discountBps': 1000,
        },
      ],
    },
  ],
};
Operation op(
  WorkOrder o,
  Map<String, dynamic> p, {
  Actor? actor,
  String id = 'op',
  DateTime? at,
}) => Operation(
  id: id,
  orderId: o.id,
  kind: 'quote_draft',
  actorId: (actor ?? demoActors[2]).id,
  baseRevision: o.revision,
  at: at ?? DateTime.utc(2026, 10, 7),
  payload: p,
);
Map<String, dynamic> decision(WorkOrder o, {int version = 1}) => {
  'quoteId': 'quote-test',
  'version': version,
  'customer': o.client,
  'channel': 'telephone',
  'evidence': 'Conversación ficticia',
  'reason': 'Decisión humana',
  'decisions': [
    {'lineId': 'line-test', 'accepted': true},
  ],
};
void main() {
  test(
    'Decimal quantities, discount before tax and per-component rounding match the note arithmetic',
    () {
      final o = demoState().orders.values.first, l = QuoteLedger();
      final q = l.prepare(o, demoActors[2], op(o, draft(o)));
      final c = q['lines'][0]['components'];
      expect(c[0]['totalCents'], 2904);
      expect(c[1]['grossCents'], 1502);
      expect(c[1]['discountCents'], 150);
      expect(c[1]['netCents'], 1352);
      expect(c[1]['taxCents'], 284);
      expect(q['totalCents'], 4540);
    },
  );
  test(
    'Preparing an extension keeps authorized work, stock, time and previous versions intact',
    () {
      final o = demoState().orders.values.first, l = QuoteLedger();
      final before = jsonEncode(o.data),
          p = draft(o),
          q = l.prepare(o, demoActors[2], op(o, p));
      p['lines'][0]['description'] = 'Changed draft';
      expect(q['lines'][0]['description'], 'Trabajo ficticio');
      final next = {...draft(o), 'expectedVersion': 1, 'reason': 'Ampliación'};
      l.prepare(o, demoActors[2], op(o, next, id: 'v2'));
      expect(l.toJson()['versions'].length, 2);
      expect(jsonEncode(o.data), before);
      expect(
        () => q['lines'][0]['components'][0]['netCents'] = 1,
        throwsUnsupportedError,
      );
    },
  );
  test(
    'An old version cannot approve a newer budget and decisions remain separate immutable evidence',
    () {
      final o = demoState().orders.values.first, l = QuoteLedger();
      l.prepare(o, demoActors[2], op(o, draft(o)));
      final before = jsonEncode(o.data);
      final d = l.recordDecision(
        o,
        demoActors[2],
        op(o, decision(o), id: 'decision-1'),
      );
      expect(d['decisions'][0]['approvedCents'], 4540);
      expect(jsonEncode(o.data), before);
      l.prepare(
        o,
        demoActors[2],
        op(o, {...draft(o), 'expectedVersion': 1}, id: 'v2'),
      );
      expect(
        () => l.recordDecision(
          o,
          demoActors[2],
          op(o, decision(o), id: 'old-link'),
        ),
        throwsA(isA<RuleException>()),
      );
      expect(l.toJson()['decisions'].length, 1);
    },
  );
  test(
    'Price or scope changes, expiry and changed owner require a current reviewed version',
    () {
      for (final kind in ['price', 'scope', 'expiry', 'owner']) {
        final o = demoState().orders.values.first, l = QuoteLedger();
        l.prepare(o, demoActors[2], op(o, draft(o)));
        if (kind == 'price') o.tasks.first['priceVersion'] = 2;
        if (kind == 'scope') o.tasks.first['scopeVersion'] = 2;
        if (kind == 'owner') o.data['client'] = 'Otro propietario';
        expect(
          () => l.recordDecision(
            o,
            demoActors[2],
            op(
              o,
              decision(o),
              at: kind == 'expiry' ? DateTime.utc(2026, 12, 1) : null,
            ),
          ),
          throwsA(isA<RuleException>()),
        );
      }
    },
  );
  test(
    'A rejected line stays unapproved, duplicate decisions and extra amount fields are refused',
    () {
      final o = demoState().orders.values.first, l = QuoteLedger();
      l.prepare(o, demoActors[2], op(o, draft(o)));
      final p = decision(o);
      p['decisions'][0]['accepted'] = false;
      final d = l.recordDecision(o, demoActors[2], op(o, p));
      expect(d['decisions'][0]['approvedCents'], 0);
      expect(
        () => l.recordDecision(o, demoActors[2], op(o, p, id: 'duplicate')),
        throwsA(isA<RuleException>()),
      );
      expect(
        () => l.prepare(
          o,
          demoActors[2],
          op(o, {...draft(o), 'expectedVersion': 1, 'totalCents': 1}),
        ),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Operator access and issued documents are refused; serialization preserves all snapshots',
    () {
      final o = demoState().orders.values.first, l = QuoteLedger();
      expect(
        () =>
            l.prepare(o, demoActors[0], op(o, draft(o), actor: demoActors[0])),
        throwsA(isA<RuleException>()),
      );
      l.prepare(o, demoActors[2], op(o, draft(o)));
      l.recordDecision(o, demoActors[2], op(o, decision(o)));
      expect(
        QuoteLedger.fromJson(jsonDecode(jsonEncode(l.toJson()))).toJson(),
        l.toJson(),
      );
      o.data['document'] = {'immutable': true};
      expect(
        () => l.prepare(
          o,
          demoActors[2],
          op(o, {...draft(o), 'expectedVersion': 1}),
        ),
        throwsA(isA<RuleException>()),
      );
    },
  );
}
