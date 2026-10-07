import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/simulation.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/models.dart';
import 'package:tallerflow/ui/quote_panel.dart';
import 'quotes_test.dart' as fixtures;

void main() {
  test(
    'Partial approval leaves the rejected extension and other tasks unchanged',
    () {
      final s = demoState(), o = s.orders.values.first;
      final first = cloneMap(o.tasks.first);
      o.tasks[1]['authorized'] = false;
      o.tasks[1]['authorization'] = null;
      o.tasks[1]['approvedCents'] = 0;
      final p = fixtures.draft(o);
      p['lines'].add({
        'id': 'second-line',
        'taskId': o.tasks[1]['id'],
        'description': 'Comprobación adicional',
        'laborMinutes': 15,
        'parts': [],
      });
      s.apply(fixtures.op(o, p, id: 'partial-draft'), demoActors[2]);
      final d = fixtures.decision(o);
      d['decisions'] = [
        {'lineId': 'line-test', 'accepted': false},
        {'lineId': 'second-line', 'accepted': true},
      ];
      s.apply(
        Operation(
          id: 'partial-decision',
          orderId: o.id,
          kind: 'quote_decision',
          actorId: demoActors[2].id,
          baseRevision: o.revision,
          at: DateTime.utc(2026, 10, 7),
          payload: d,
        ),
        demoActors[2],
      );
      expect(o.tasks.first, first);
      expect(o.tasks[1]['approvedCents'], 1452);
      expect(o.tasks[1]['authorization']['lineId'], 'second-line');
    },
  );
  test(
    'Quote decisions authorize only selected tasks, rejection preserves prior approval, and replay is once',
    () {
      final s = demoState(), o = s.orders.values.first;
      final before = cloneMap(o.tasks.first);
      s.apply(fixtures.op(o, fixtures.draft(o), id: 'draft'), demoActors[2]);
      expect(o.tasks.first, before);
      final p = fixtures.decision(o);
      p['decisions'][0]['accepted'] = false;
      final rejected = Operation(
        id: 'reject',
        orderId: o.id,
        kind: 'quote_decision',
        actorId: demoActors[2].id,
        baseRevision: o.revision,
        at: DateTime.utc(2026, 10, 7),
        payload: p,
      );
      s.apply(rejected, demoActors[2]);
      s.apply(rejected, demoActors[2]);
      expect(o.tasks.first, before);
      expect(o.data['quoteLedger']['decisions'].length, 1);
      s.apply(
        fixtures.op(o, {...fixtures.draft(o), 'expectedVersion': 1}, id: 'v2'),
        demoActors[2],
      );
      s.apply(
        Operation(
          id: 'accept',
          orderId: o.id,
          kind: 'quote_decision',
          actorId: demoActors[2].id,
          baseRevision: o.revision,
          at: DateTime.utc(2026, 10, 7),
          payload: fixtures.decision(o, version: 2),
        ),
        demoActors[2],
      );
      expect(o.tasks.first['authorized'], true);
      expect(o.tasks.first['approvedCents'], 4540);
      expect(o.tasks.first['authorization']['quoteId'], 'quote-test');
      expect(o.data['quoteLedger']['versions'].length, 2);
    },
  );
  test(
    'A batch cannot lower the authorization below recorded work or mutate an issued document',
    () {
      final s = demoState(), o = s.orders.values.first;
      o.tasks.first['billableMinutes'] = 120;
      s.apply(fixtures.op(o, fixtures.draft(o), id: 'draft'), demoActors[2]);
      final before = cloneMap(o.data);
      expect(
        () => s.copy().apply(
          Operation(
            id: 'low-cap',
            orderId: o.id,
            kind: 'quote_decision',
            actorId: demoActors[2].id,
            baseRevision: o.revision,
            at: DateTime.utc(2026, 10, 7),
            payload: fixtures.decision(o),
          ),
          demoActors[2],
        ),
        throwsA(isA<RuleException>()),
      );
      expect(o.data, before);
      o.data['document'] = {'totalCents': 11616};
      expect(
        () => s.copy().apply(
          fixtures.op(o, {
            ...fixtures.draft(o),
            'expectedVersion': 1,
          }, id: 'late'),
          demoActors[2],
        ),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Offline quote and authorization survive vault reopen, complete backup and lost-response replay',
    () async {
      final server = SimulatedWorkshop(), store = MemoryStore();
      final vault = Vault(store, await AesGcm.with256bits().newSecretKey());
      final c = WorkshopController(
        vault,
        remote: SimulatedRemote(server, demoActors[2]),
        actor: demoActors[2],
      );
      await c.load();
      c.offline = true;
      final o = c.state.orders.values.first;
      await c.execute(
        o.id,
        'quote_draft',
        fixtures.draft(o),
        at: DateTime.utc(2026, 10, 7),
      );
      final fresh = c.state.orders[o.id]!;
      await c.execute(
        o.id,
        'quote_decision',
        fixtures.decision(fresh),
        at: DateTime.utc(2026, 10, 7),
      );
      final ids = c.outbox.map((p) => p.id).toList(),
          archive = await c.exportBackup(splitFiles: true);
      expect(archive['local']['outbox'].length, 2);
      c.dispose();
      final reopened = WorkshopController(
        vault,
        remote: SimulatedRemote(server, demoActors[2]),
        actor: demoActors[2],
      );
      await reopened.load();
      expect(reopened.outbox.map((p) => p.id).toList(), ids);
      expect(
        reopened.state.orders[o.id]!.data['quoteLedger']['versions'].length,
        1,
      );
      reopened.offline = false;
      await reopened.synchronize();
      await reopened.synchronize();
      expect(reopened.outbox, isEmpty);
      expect(
        server.state.orders[o.id]!.data['quoteLedger']['decisions'].length,
        1,
      );
      expect(server.records.keys.where(ids.contains).length, 2);
      reopened.dispose();
    },
  );
  test(
    'Operator snapshots omit quote documents even with price permission; stale open dialogs cannot approve refreshed orders',
    () async {
      final server = SimulatedWorkshop(), o = server.state.orders.values.first;
      server.state.apply(
        fixtures.op(o, fixtures.draft(o), id: 'draft'),
        demoActors[2],
      );
      final snapshot = server.snapshot(demoActors[0], 'operator');
      expect(
        (snapshot['orders'] as List).every((v) => v['quoteLedger'] == null),
        true,
      );
      final c = WorkshopController(
        Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
      );
      await c.load();
      c.changeDemoActor(demoActors[2]);
      final current = c.state.orders.values.first;
      final revision = current.revision;
      await c.execute(
        current.id,
        'quote_draft',
        fixtures.draft(current),
        at: DateTime.utc(2026, 10, 7),
      );
      await expectLater(
        c.execute(
          current.id,
          'quote_decision',
          fixtures.decision(current),
          expectedRevision: revision,
        ),
        throwsA(isA<RuleException>()),
      );
      c.dispose();
    },
  );
  testWidgets(
    'Office views previous versions and decision states without changing work',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = demoState(), o = s.orders.values.first;
      s.apply(fixtures.op(o, fixtures.draft(o), id: 'draft'), demoActors[2]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: QuotePanel(
                order: o,
                actor: demoActors[2],
                catalog: s.catalog,
                canEdit: true,
                onSave: (k, p) async {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Presupuestos y autorizaciones'), findsOneWidget);
      await tester.tap(find.textContaining('versión 1').first);
      await tester.pumpAndSettle();
      expect(find.text('Registrar decisión'), findsOneWidget);
      await tester.tap(find.text('Registrar decisión'));
      await tester.pumpAndSettle();
      expect(find.text('Sin decisión'), findsOneWidget);
      expect(find.textContaining('soporte', findRichText: true), findsNothing);
      expect(o.data['quoteLedger']['decisions'], isEmpty);
    },
  );
}
