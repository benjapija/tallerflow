import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/simulation.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/models.dart';
import 'package:tallerflow/domain/vehicles.dart';
import 'package:tallerflow/ui/inspection_panel.dart';

const inspectionId = '01000000-0000-4000-8000-000000000001';
const checkId = '01000000-0000-4000-8000-000000000002';
Map<String, dynamic> payload() => {
  'id': inspectionId,
  'expectedVersion': 0,
  'title': 'Inspección inicial',
  'reason': 'Comprobación ficticia',
  'items': [
    {
      'id': checkId,
      'label': 'Frenos',
      'status': 'follow_up',
      'observation': 'Medir desgaste en siguiente visita',
      'photoIds': <String>[],
    },
  ],
};
Operation op(
  WorkshopState s,
  Map<String, dynamic> p, {
  String id = 'inspection-original',
  Actor? actor,
  int? revision,
}) => Operation(
  id: id,
  orderId: 'o-1048',
  kind: 'inspection_save',
  actorId: (actor ?? demoActors[0]).id,
  baseRevision: revision ?? s.orders['o-1048']!.revision,
  at: DateTime.utc(2026, 10, 7),
  payload: p,
);
void main() {
  test(
    'Findings remain recommendations and never add work, authorizations or charges',
    () {
      final s = demoState(), o = safeOrder();
      final original = cloneMap(s.orders['o-1048']!.data);
      s.apply(op(s, payload()), demoActors[0]);
      final result = s.orders['o-1048']!;
      expect(result.tasks, original['tasks']);
      expect(result.parts, original['parts']);
      expect(result.billableMinutes, o.billableMinutes);
      expect(
        result.data['inspections'].single['items'].single['status'],
        'follow_up',
      );
      expect(s.audit.last['kind'], 'inspection_save');
      expect(result.data['quality'], isNull);
    },
  );
  test(
    'Review keeps the previous version and exposes only technical history',
    () {
      final s = demoState();
      s.apply(op(s, payload()), demoActors[0]);
      final old = cloneMap(s.orders['o-1048']!.data['inspections'].single);
      final p = payload()
        ..['expectedVersion'] = 1
        ..['reason'] = 'Medición repetida';
      p['items'][0]['status'] = 'attention';
      s.apply(op(s, p, id: 'review', actor: demoActors[2]), demoActors[2]);
      final o = s.orders['o-1048']!;
      expect(o.data['inspectionHistory'], [old]);
      expect(o.data['inspections'].single['version'], 2);
      final h = technicalHistoryEntry(o);
      expect(h['inspections'], o.data['inspections']);
      expect(h['client'], isNull);
      expect(h['document'], isNull);
    },
  );
  test('Stale versions and revisions cannot replace a newer finding', () {
    final s = demoState();
    s.apply(op(s, payload()), demoActors[0]);
    final before = cloneMap(s.orders['o-1048']!.data);
    for (final p in [payload(), payload()..['expectedVersion'] = 1]) {
      expect(
        () => s.copy().apply(
          op(s, p, id: 'stale', revision: before['revision'] - 1),
          demoActors[0],
        ),
        throwsA(isA<RuleException>()),
      );
    }
    expect(
      () =>
          s.copy().apply(op(s, payload(), id: 'wrong-version'), demoActors[0]),
      throwsA(isA<RuleException>()),
    );
    expect(s.orders['o-1048']!.data, before);
  });
  test(
    'Invalid findings, fabricated charges and unconfirmed photos are rejected',
    () {
      final s = demoState();
      final cases = <Map<String, dynamic>>[
        payload()..['priceCents'] = 1,
        payload()..['reason'] = '',
        payload()..['items'] = [],
        payload()..['items'] = [...payload()['items'], ...payload()['items']],
        payload()..['items'][0]['status'] = 'authorized',
        payload()..['items'][0]['observation'] = '',
        payload()..['items'][0]['photoIds'] = ['another-order-photo'],
        payload()..['items'][0]['priceCents'] = 1,
      ];
      for (final p in cases) {
        expect(
          () => s.copy().apply(op(s, p), demoActors[0]),
          throwsA(isA<RuleException>()),
        );
      }
      final p = payload();
      p['items'][0]['photoIds'] = ['confirmed'];
      s.orders['o-1048']!.data['photos'] = [
        {'id': 'confirmed', 'status': 'attached'},
      ];
      s.apply(op(s, p), demoActors[0]);
      expect(
        s
            .orders['o-1048']!
            .data['inspections']
            .single['items']
            .single['photoIds'],
        ['confirmed'],
      );
    },
  );
  test(
    'Offline original survives restart and backup without duplicating its finding',
    () async {
      final vault = Vault(
        MemoryStore(),
        await AesGcm.with256bits().newSecretKey(),
      );
      final server = SimulatedWorkshop();
      final c = WorkshopController(
        vault,
        remote: SimulatedRemote(server, demoActors[0]),
        actor: demoActors[0],
      );
      await c.load();
      c.offline = true;
        await c.execute('o-1048', 'inspection_save', payload());
      final id = c.outbox.single.id;
      final archive = await c.exportBackup(splitFiles: true);
      c.dispose();
      final reopened = WorkshopController(
        vault,
        remote: SimulatedRemote(server, demoActors[0]),
        actor: demoActors[0],
      );
      await reopened.load();
      expect(reopened.outbox.single.id, id);
      expect(archive['local']['outbox'].single['id'], id);
      reopened.offline = false;
      await reopened.synchronize();
      await reopened.synchronize();
      expect(reopened.syncError, isNull);
      expect(reopened.outbox, isEmpty);
      expect(server.state.orders['o-1048']!.data['inspections'], hasLength(1));
      reopened.dispose();
    },
  );
  testWidgets(
    'Editor requires a human result before saving and issued records are read only',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InspectionPanel(
              order: safeOrder(),
              canEdit: true,
              onSave: (_) async {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('Nueva inspección'));
      await tester.pumpAndSettle();
      expect(find.text('Resultado de la comprobación'), findsOneWidget);
      await tester.tap(find.text('Guardar inspección'));
      await tester.pumpAndSettle();
      expect(find.text('Completa este dato'), findsWidgets);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      final issued = safeOrder()..data['document'] = {'totalCents': 0};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InspectionPanel(
              order: issued,
              canEdit: true,
              onSave: (_) async {},
            ),
          ),
        ),
      );
      expect(find.text('Nueva inspección'), findsNothing);
    },
  );
}

WorkOrder safeOrder() => demoState().orders['o-1048']!;
