import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/simulation.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/models.dart';
import 'package:tallerflow/domain/payments.dart';
import 'package:tallerflow/ui/payment_panel.dart';

WorkshopState issued() {
  final s = demoState(), o = s.orders.values.first;
  o.data['document'] = {
    'totalCents': 10001,
    'revision': o.revision,
    'issuedAt': '2026-10-06T09:00:00Z',
  };
  o.data['status'] = 'finished';
  return s;
}

Map<String, dynamic> receipt(int cents) => {
  'amountCents': cents,
  'method': 'cash',
  'paidAt': '2026-10-06T10:00:00Z',
  'reference': 'Fictional receipt',
  'reason': 'Fictional payment received',
};
Operation operation(
  WorkOrder o,
  String kind,
  Map<String, dynamic> p, {
  String id = 'receipt-1',
  int? revision,
  Actor? actor,
}) => Operation(
  id: id,
  orderId: o.id,
  kind: kind,
  actorId: (actor ?? demoActors[2]).id,
  baseRevision: revision ?? o.revision,
  at: DateTime.utc(2026, 10, 7),
  payload: p,
);
void apply(
  WorkshopState s,
  String kind,
  Map<String, dynamic> p, {
  String id = 'receipt-1',
}) => s.apply(operation(s.orders.values.first, kind, p, id: id), demoActors[2]);
Map<String, dynamic> reversal(String id, int cents) => {
  ...receipt(cents)..remove('method'),
  'sourceId': id,
  'reason': 'Fictional refund completed',
};

class LostPaymentResponse extends SimulatedRemote {
  bool lose = true;
  LostPaymentResponse(super.workshop, super.actor);
  @override
  Future<Map<String, dynamic>> push(Operation op, String deviceId) async {
    final r = await super.push(op, deviceId);
    if (lose) {
      lose = false;
      throw StateError('Lost response after commit');
    }
    return r;
  }
}

void main() {
  test(
    'Partial receipts, linked partial refunds and settlement preserve issued document',
    () {
      final s = issued(),
          o = s.orders.values.first,
          document = cloneMap(s.orders.values.first.data['document']);
      apply(s, 'payment_record', receipt(4001));
      expect(PaymentBalance.forOrder(o).status, 'partial');
      apply(s, 'payment_reverse', reversal('receipt-1', 1000), id: 'refund-1');
      apply(s, 'payment_reverse', reversal('receipt-1', 1001), id: 'refund-2');
      expect(reversibleCents(o, 'receipt-1'), 2000);
      apply(s, 'payment_record', receipt(8001), id: 'receipt-2');
      expect(PaymentBalance.forOrder(o).status, 'paid');
      expect(PaymentBalance.forOrder(o).paidCents, 10001);
      expect(o.data['document'], document);
      expect(paymentEntries(o).first['amountCents'], 4001);
      expect(s.audit.where((a) => a['kind'] == 'payment_reverse').length, 2);
    },
  );
  test(
    'Delivery records explicit credit without fabricating a payment; later settlement is allowed',
    () {
      final s = issued();
      apply(s, 'payment_record', receipt(2000));
      apply(s, 'deliver', {
        'reason': 'Fictional office authorizes credit',
      }, id: 'delivery');
      final o = s.orders.values.first,
          d = cloneMap(s.orders.values.first.data['delivery']);
      expect(d['outstandingCents'], 8001);
      expect(d['creditAuthorized'], true);
      apply(s, 'payment_record', receipt(8001), id: 'settlement');
      expect(o.data['delivery'], d);
      expect(PaymentBalance.forOrder(o).outstandingCents, 0);
      expect(
        () => apply(s, 'deliver', {
          'reason': 'Attempt to rewrite',
        }, id: 'delivery-2'),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Zero, overpayment, future and preissue dates, forged fields and missing evidence fail atomically',
    () {
      for (final p in [
        receipt(0),
        receipt(-1),
        receipt(10002),
        {...receipt(1), 'paidAt': '2026-10-08T00:00:00Z'},
        {...receipt(1), 'paidAt': '2026-10-05T00:00:00Z'},
        {...receipt(1), 'totalCents': 1},
        {...receipt(1), 'reference': ''},
        {...receipt(1), 'method': 'unknown'},
      ]) {
        final s = issued(), before = s.toJson();
        expect(
          () => apply(s, 'payment_record', p),
          throwsA(isA<RuleException>()),
        );
        expect(s.toJson(), before);
      }
    },
  );
  test(
    'Refunds cannot exceed the remaining original receipt or use an unknown source',
    () {
      final s = issued();
      apply(s, 'payment_record', receipt(2000));
      apply(s, 'payment_reverse', reversal('receipt-1', 1500), id: 'refund');
      for (final p in [
        reversal('receipt-1', 501),
        reversal('missing', 1),
        {...reversal('receipt-1', 1), 'paidAt': '2026-10-06T09:30:00Z'},
      ]) {
        expect(
          () => apply(s, 'payment_reverse', p, id: 'bad'),
          throwsA(isA<RuleException>()),
        );
      }
      expect(reversibleCents(s.orders.values.first, 'receipt-1'), 500);
    },
  );
  test('Only active office at the reviewed revision may record money', () {
    final s = issued(), o = s.orders.values.first;
    expect(
      () => s.apply(
        operation(o, 'payment_record', receipt(1), actor: demoActors[0]),
        demoActors[0],
      ),
      throwsA(isA<RuleException>()),
    );
    expect(
      () => s.apply(
        operation(o, 'payment_record', receipt(1), revision: o.revision + 1),
        demoActors[2],
      ),
      throwsA(isA<RuleException>()),
    );
    o.data.remove('document');
    expect(
      () => apply(s, 'payment_record', receipt(1)),
      throwsA(isA<RuleException>()),
    );
  });
  test(
    'Offline receipts survive encrypted restart and a lost response is never double counted',
    () async {
      final server = SimulatedWorkshop()..state = issued();
      final vault = Vault(
        MemoryStore(),
        await AesGcm.with256bits().newSecretKey(),
      );
      final transport = LostPaymentResponse(server, demoActors[2]);
      final c = WorkshopController(
        vault,
        remote: transport,
        actor: demoActors[2],
      );
      await c.load();
      c.offline = true;
      final o = c.state.orders.values.first;
      await c.execute(
        o.id,
        'payment_record',
        receipt(3000),
        at: DateTime.utc(2026, 10, 7),
      );
      final archive = await c.exportBackup(splitFiles: true);
      expect(archive['local']['outbox'].length, 1);
      expect(paymentEntries(c.state.orders[o.id]!).length, 1);
      final restored = WorkshopController(
        Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
        remote: SimulatedRemote(server, demoActors[2]),
        actor: demoActors[2],
      );
      await restored.load();
      await restored.restoreLocalBackup(archive);
      expect(restored.outbox.single.toJson(), c.outbox.single.toJson());
      expect(restored.state.orders[o.id]!.data['document'], o.data['document']);
      expect(
        paymentEntries(restored.state.orders[o.id]!).single['amountCents'],
        3000,
      );
      expect(
        restored.restoredArchive!['originalLocal']['outbox'],
        archive['local']['outbox'],
      );
      restored.dispose();
      final originalId = c.outbox.single.id;
      c.dispose();
      final reopened = WorkshopController(
        vault,
        remote: transport,
        actor: demoActors[2],
      );
      await reopened.load();
      expect(reopened.outbox.single.id, originalId);
      reopened.offline = false;
      await reopened.synchronize();
      await reopened.synchronize();
      expect(reopened.outbox, isEmpty);
      expect(paymentEntries(server.state.orders[o.id]!).length, 1);
      expect(
        PaymentBalance.forOrder(server.state.orders[o.id]!).paidCents,
        3000,
      );
      expect(server.records[originalId]!['status'], 'accepted');
      reopened.dispose();
    },
  );
  test(
    'Concurrent office payment is retained as a conflict instead of charging twice',
    () async {
      final server = SimulatedWorkshop()..state = issued();
      final clients = <WorkshopController>[];
      for (var n = 0; n < 2; n++) {
        final c = WorkshopController(
          Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
          remote: SimulatedRemote(server, demoActors[2]),
          actor: demoActors[2],
        );
        await c.load();
        c.offline = true;
        clients.add(c);
        await c.execute(
          c.state.orders.keys.first,
          'payment_record',
          receipt(6000),
          at: DateTime.utc(2026, 10, 7),
        );
      }
      for (final c in clients) {
        c.offline = false;
        await c.synchronize();
      }
      expect(
        PaymentBalance.forOrder(server.state.orders.values.first).paidCents,
        6000,
      );
      expect(
        server.state.incidents.single['operation']['payload']['amountCents'],
        6000,
      );
      for (final c in clients) {
        c.dispose();
      }
    },
  );
  testWidgets(
    'Office records a decimal receipt and keeps the pending balance visible',
    (tester) async {
      final s = issued(), o = s.orders.values.first;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PaymentPanel(
                order: o,
                canEdit: true,
                onSave: (k, p) async {
                  s.apply(
                    Operation(
                      id: 'widget-payment',
                      orderId: o.id,
                      kind: k,
                      actorId: demoActors[2].id,
                      baseRevision: o.revision,
                      at: DateTime.now().toUtc(),
                      payload: p,
                    ),
                    demoActors[2],
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Registrar cobro recibido'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Importe (€)'),
        '20,01',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Justificante o referencia'),
        'Fictional receipt',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo'),
        'Received in fictional test',
      );
      await tester.tap(find.text('Guardar registro'));
      await tester.pumpAndSettle();
      expect(paymentEntries(o).single['amountCents'], 2001);
      expect(PaymentBalance.forOrder(o).outstandingCents, 8000);
      expect(tester.takeException(), isNull);
    },
  );
}
