import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/models.dart';
import 'package:tallerflow/domain/pricing.dart';

void main() {
  var seq = 0;
  final now = DateTime.utc(2026, 10, 6, 14);
  Operation review(
    WorkshopState s,
    String target,
    Map<String, dynamic> entry, {
    int? price,
    int discount = 0,
    bool charge = true,
    String reason = 'Revisión ficticia',
    int? revision,
  }) => Operation(
    id: 'pricing-${seq++}',
    orderId: 'o-1048',
    kind: 'pricing_review',
    actorId: 'office',
    baseRevision: revision ?? s.orders['o-1048']!.revision,
    at: now,
    payload: {
      'target': target,
      'targetId': entry['id'],
      'unitPriceCents':
          price ?? entry[target == 'labor' ? 'rateCents' : 'priceCents'],
      'taxBps': entry['taxBps'],
      'discountBps': discount,
      'charge': charge,
      'reason': reason,
    },
  );
  test(
    'Discounts round per line before tax and preserve actual work and source prices',
    () {
      final s = demoState();
      final o = s.orders['o-1048']!;
      final t = o.tasks.firstWhere((t) => t['authorized'] == true);
      t['billableMinutes'] = 37;
      t['rateCents'] = 4801;
      t['taxBps'] = 2100;
      final times = cloneMap({'times': o.times});
      final op = review(s, 'labor', t, discount: 1250);
      s.apply(op, demoActors[2]);
      s.apply(op, demoActors[2]);
      final total = calculateNote(o);
      final line = total.lines.firstWhere((l) => l['taskId'] == t['id']);
      expect(line['grossCents'], 2961);
      expect(line['discountCents'], 370);
      expect(line['netCents'], 2591);
      expect(line['taxCents'], 544);
      expect(o.data['pricingReviews'], hasLength(1));
      expect(t['authorized'], true);
      expect({'times': o.times}, times);
    },
  );
  test('No-charge consumption keeps stock and cost after partial return', () {
    final s = demoState();
    final o = s.orders['o-1048']!;
    final t = o.tasks.firstWhere((t) => t['authorized'] == true);
    final item = s.catalog.first;
    final p = {
      'id': 'part-price',
      'taskId': t['id'],
      'itemId': item.id,
      'description': 'Material ficticio',
      'unit': 'L',
      'kind': 'consume',
      'quantityMilli': 4500,
      'priceCents': 1450,
      'costCents': 650,
      'costKnown': true,
      'taxBps': 2100,
      'charge': true,
      'reviewed': false,
    };
    o.parts.add(p);
    o.parts.add({
      ...p,
      'id': 'return-price',
      'kind': 'return',
      'sourceId': p['id'],
      'quantityMilli': 500,
      'charge': false,
    });
    final stock = s.stock(item.id);
    s.apply(
      review(
        s,
        'part',
        p,
        charge: false,
        reason: 'Atención comercial ficticia',
      ),
      demoActors[2],
    );
    expect(s.stock(item.id), stock);
    expect(p['costCents'], 650);
    expect(p['noChargeReason'], 'Atención comercial ficticia');
    final line = calculateNote(
      o,
    ).lines.firstWhere((l) => l['partId'] == p['id']);
    expect(line['netCents'], 0);
    expect(line['discountCents'], 5800);
    expect(line['noChargeReason'], 'Atención comercial ficticia');
    final e = estimateMargin(o, {
      'internalCostKnown': true,
      'internalHourlyCostCents': 2000,
    }, now);
    expect(e.materialCostCents, greaterThanOrEqualTo(2600));
  });
  test(
    'Price increase preserves prior authorization and requires a fresh decision',
    () {
      final s = demoState();
      final o = s.orders['o-1048']!;
      final t = o.tasks.firstWhere((t) => t['authorized'] == true);
      t['authorization'] = {
        'version': 3,
        'evidence': 'Autorización ficticia original',
      };
      s.apply(
        review(s, 'labor', t, price: (t['rateCents'] as int) + 1),
        demoActors[2],
      );
      expect(t['authorized'], false);
      expect(t['authorization'], null);
      expect(t['previousAuthorizations'].single['version'], 3);
      expect(t['priceVersion'], 2);
      expect(o.data['pricingReviews'].single['requiresAuthorization'], true);
    },
  );
  test(
    'Missing reasons, old revisions and operator changes leave state untouched',
    () {
      final s = demoState();
      final o = s.orders['o-1048']!;
      final t = o.tasks.first;
      final before = cloneMap(s.toJson());
      expect(
        () => s.apply(review(s, 'labor', t, reason: ''), demoActors[2]),
        throwsA(isA<RuleException>()),
      );
      expect(
        () => s.apply(
          review(s, 'labor', t, revision: o.revision + 1),
          demoActors[2],
        ),
        throwsA(isA<RuleException>()),
      );
      final op = review(s, 'labor', t);
      expect(
        () => s.apply(
          Operation(
            id: op.id,
            orderId: op.orderId,
            kind: op.kind,
            actorId: demoActors[0].id,
            baseRevision: op.baseRevision,
            at: now,
            payload: op.payload,
          ),
          demoActors[0],
        ),
        throwsA(isA<RuleException>()),
      );
      expect(s.toJson(), before);
    },
  );
  test(
    'Issued notes reject revisions and backup serialization retains reasons',
    () {
      final s = demoState();
      final o = s.orders['o-1048']!;
      final t = o.tasks.first;
      s.apply(review(s, 'labor', t, discount: 500), demoActors[2]);
      final restored = WorkshopState.fromJson(cloneMap(s.toJson()));
      expect(
        restored.orders[o.id]!.data['pricingReviews'],
        o.data['pricingReviews'],
      );
      o.data['document'] = {'totalCents': 1234};
      final before = cloneMap(o.data);
      expect(
        () => s.apply(review(s, 'labor', t), demoActors[2]),
        throwsA(isA<RuleException>()),
      );
      expect(o.data, before);
    },
  );
  test('Unknown costs do not produce a complete or misleading margin', () {
    final s = demoState();
    final o = s.orders['o-1048']!;
    final t = o.tasks.first;
    o.times.clear();
    o.times.add({
      'taskId': t['id'],
      'start': now.subtract(const Duration(hours: 1)).toIso8601String(),
      'end': now.toIso8601String(),
    });
    o.parts.clear();
    o.parts.add({
      'id': 'unknown',
      'taskId': t['id'],
      'kind': 'consume',
      'quantityMilli': 1000,
      'priceCents': 2000,
      'costKnown': false,
      'unit': 'ud',
      'description': 'Coste pendiente',
      'taxBps': 2100,
      'charge': true,
    });
    final e = estimateMargin(o, {'internalCostKnown': false}, now);
    expect(e.complete, false);
    expect(e.marginCents, null);
    expect(e.missingMaterialCosts, 1);
    expect(e.laborCostKnown, false);
    o.parts.first.remove('priceCents');
    expect(estimateMargin(o, {}, now, includeRevenue: false).marginCents, null);
  });
  test(
    'Integer rounding remains exact when intermediate products exceed JavaScript safe integers',
    () {
      expect(roundProduct(999999999999, 9999, 10000), 999899999999);
      expect(roundProduct(999999999999, 5000, 10000), 500000000000);
      expect(roundProduct(-999999999999, 5000, 10000), -500000000000);
    },
  );
}
