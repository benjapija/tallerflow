import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/simulation.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/models.dart';
import 'package:tallerflow/domain/purchases.dart';
import 'purchases_test.dart' as fixtures;

class LostInventoryReply extends SimulatedRemote {
  bool lose = true;
  LostInventoryReply(super.workshop, super.actor);
  @override
  Future<Map<String, dynamic>> command(
    String id,
    String action,
    Map<String, dynamic> payload,
  ) async {
    final r = await super.command(id, action, payload);
    if (lose) {
      lose = false;
      throw StateError('Lost committed command reply');
    }
    return r;
  }
}

void main() {
  final admin = demoActors.firstWhere((a) => a.role == Role.admin);
  test(
    'Offline purchase survives restart and receipt retry changes stock exactly once',
    () async {
      final server = SimulatedWorkshop();
      final transport = LostInventoryReply(server, admin),
          vault = Vault(
            MemoryStore(),
            await AesGcm.with256bits().newSecretKey(),
          );
      final c = WorkshopController(vault, remote: transport, actor: admin);
      await c.load();
      c.offline = true;
      final item = c.state.catalog.first.id,
          initial = server.state.stock(c.state.catalog.first.id);
      await c.inventory('purchase_create', fixtures.request(item));
      expect(c.pendingCommands.length, 1);
      expect(server.state.configuration['purchaseLedger'], isNull);
      final archive = await c.exportBackup(splitFiles: true);
      expect(archive['local']['pendingCommands'].length, 1);
      final id = c.pendingCommands.single['id'];
      c.dispose();
      final reopened = WorkshopController(
        vault,
        remote: transport,
        actor: admin,
      );
      await reopened.load();
      expect(reopened.pendingCommands.single['id'], id);
      reopened.offline = false;
      await reopened.synchronize();
      await reopened.synchronize();
      expect(reopened.pendingCommands, isEmpty);
      expect(
        PurchaseLedger(
          server.state.configuration['purchaseLedger'],
        ).orders.length,
        1,
      );
      reopened.offline = true;
      await reopened.inventory('purchase_receive', fixtures.movement(1, 1000));
      expect(server.state.stock(item), initial);
      transport.lose = true;
      reopened.offline = false;
      await reopened.synchronize();
      await reopened.synchronize();
      expect(server.state.stock(item), initial + 5000);
      expect(
        PurchaseLedger(
          server.state.configuration['purchaseLedger'],
        ).movements.length,
        1,
      );
      expect(reopened.pendingCommands, isEmpty);
      reopened.dispose();
    },
  );
  test(
    'Purchase movements preserve issued prices and office without cost permission is denied',
    () {
      final s = demoState(), o = s.orders.values.first;
      o.data['document'] = {
        'totalCents': 123,
        'issuedAt': '2026-10-07T00:00:00Z',
        'revision': 2,
      };
      final original = cloneMap(o.data['document']);
      applyPurchaseCommand(
        s,
        'create',
        'purchase_create',
        fixtures.request(s.catalog.first.id),
        admin,
        DateTime.now().toUtc(),
      );
      applyPurchaseCommand(
        s,
        'receive',
        'purchase_receive',
        fixtures.movement(1, 1000),
        admin,
        DateTime.now().toUtc(),
      );
      expect(o.data['document'], original);
      expect(
        () => PurchaseLedger().apply(
          'new',
          'purchase_create',
          fixtures.request(s.catalog.first.id),
          demoActors[2],
          DateTime.now(),
          catalog: s.catalog,
          availableStock: {},
          repairOrders: s.orders.keys.toSet(),
        ),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test('Operator snapshots exclude supplier and cost records', () {
    final server = SimulatedWorkshop();
    applyPurchaseCommand(
      server.state,
      'create',
      'purchase_create',
      fixtures.request(server.state.catalog.first.id),
      admin,
      DateTime.now().toUtc(),
    );
    final snapshot = server.snapshot(demoActors[0], 'operator');
    expect(snapshot['purchaseLedger'], isNull);
  });
}
