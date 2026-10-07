import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/simulation.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/domain/planning.dart';
import 'package:tallerflow/domain/engine.dart';

class LostReply extends SimulatedRemote {
  bool lose = true;
  LostReply(super.workshop, super.actor);
  @override
  Future<Map<String, dynamic>> command(
    String id,
    String action,
    Map<String, dynamic> p,
  ) async {
    final result = await super.command(id, action, p);
    if (lose) {
      lose = false;
      throw StateError('Lost committed agenda reply');
    }
    return result;
  }
}

class FailingStore extends MemoryStore {
  bool fail = false;
  @override
  Future<void> write(String value) async {
    if (fail) throw StateError('Disk full');
    await super.write(value);
  }
}

Map<String, dynamic> slot(String id) => {
  'id': id,
  'title': 'Fictional slot',
  'start': '2026-10-08T09:00:00Z',
  'end': '2026-10-08T10:00:00Z',
  'kind': 'appointment',
  'assignees': [demoActors.first.id],
  'liftId': null,
  'orderId': 'o-1048',
  'reason': 'Fictional booking',
};
Future<Vault> vault([MemoryStore? store]) async =>
    Vault(store ?? MemoryStore(), await AesGcm.with256bits().newSecretKey());
void main() {
  test(
    'Offline reservations stay pending through restart and are confirmed only after syncing',
    () async {
      final remote = SimulatedRemote(SimulatedWorkshop(), demoActors[2]);
      final v = await vault(),
          c = WorkshopController(v, actor: demoActors[2], remote: remote);
      await c.load();
      c.offline = true;
      await c.planning('schedule_booking', slot('pending'));
      expect(c.pendingCommands, hasLength(1));
      expect(
        PlanningLedger(c.state.configuration['planning']).bookings,
        isEmpty,
      );
      c.dispose();
      final next = WorkshopController(v, actor: demoActors[2], remote: remote);
      await next.load();
      expect(next.pendingCommands, hasLength(1));
      next.offline = false;
      await next.synchronize();
      expect(next.pendingCommands, isEmpty);
      expect(
        PlanningLedger(
          next.state.configuration['planning'],
        ).bookings.single['id'],
        'pending',
      );
      next.dispose();
    },
  );
  test(
    'Lost committed response reuses command identity and does not duplicate booking',
    () async {
      final remote = LostReply(SimulatedWorkshop(), demoActors[2]);
      final v = await vault();
      final c = WorkshopController(v, actor: demoActors[2], remote: remote);
      await c.load();
      await expectLater(
        () => c.planning('schedule_booking', slot('one')),
        throwsStateError,
      );
      final id = c.pendingCommands.single['id'];
      expect(remote.workshop.commands.keys.single, id);
      c.dispose();
      final next = WorkshopController(v, actor: demoActors[2], remote: remote);
      await next.load();
      await next.synchronize();
      expect(next.pendingCommands, isEmpty);
      expect(
        PlanningLedger(next.state.configuration['planning']).bookings,
        hasLength(1),
      );
      expect(remote.workshop.commands, hasLength(1));
      next.dispose();
    },
  );
  test(
    'Two offices cannot commit competing stale slots; technician snapshot strips private evidence',
    () async {
      final w = SimulatedWorkshop(),
          office = WorkshopController(
            await vault(),
            actor: demoActors[2],
            remote: SimulatedRemote(SimulatedWorkshop(), demoActors[2]),
          );
      office.dispose();
      final a = WorkshopController(
        await vault(),
        actor: demoActors[2],
        remote: SimulatedRemote(w, demoActors[2]),
      );
      final b = WorkshopController(
        await vault(),
        actor: demoActors.last,
        remote: SimulatedRemote(w, demoActors.last),
      );
      await a.load();
      await b.load();
      await a.planning('schedule_booking', slot('winner'));
      await expectLater(
        () => b.planning('schedule_booking', slot('stale')),
        throwsA(isA<RuleException>()),
      );
      expect(
        PlanningLedger(w.state.configuration['planning']).bookings.single['id'],
        'winner',
      );
      expect(b.commandHistory.last['status'], 'rejected');
      expect(
        PlanningLedger(b.state.configuration['planning']).bookings.single['id'],
        'winner',
      );
      final tech = WorkshopController(
        await vault(),
        actor: demoActors.first,
        remote: SimulatedRemote(w, demoActors.first),
      );
      await tech.load();
      final booking = PlanningLedger(
        tech.state.configuration['planning'],
      ).bookings.single;
      expect(booking['events'], isEmpty);
      expect(booking['versions'], isEmpty);
      await expectLater(
        () => tech.planning('schedule_booking', slot('forged')),
        throwsA(isA<RuleException>()),
      );
      a.dispose();
      b.dispose();
      tech.dispose();
    },
  );
  test(
    'Demo rollback preserves agenda and audit when encrypted persistence fails',
    () async {
      final store = FailingStore(),
          c = WorkshopController(await vault(store), actor: demoActors.last);
      await c.load();
      final before = c.state.toJson();
      store.fail = true;
      await expectLater(
        () => c.planning('schedule_booking', slot('failed')),
        throwsStateError,
      );
      expect(c.state.toJson(), before);
      c.dispose();
    },
  );
}
