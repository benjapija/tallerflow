import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tallerflow/data/cloud.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/session_policy.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/models.dart';

/// Tests the client transport/persistence boundary; PostgreSQL tests exercise
/// actual server closure validation separately. This mock is not Supabase.
class TransportRemote extends Remote {
  final WorkshopState server = demoState();
  Actor user = demoActors[0];
  DateTime now = DateTime.utc(2026, 10, 6, 10);
  bool offline = false, conflict = false, loseCommandReceipt = false;
  int reads = 0;
  String device = '';
  final Set<String> retired = {};
  final List<String> commandCalls = [];
  final Map<String, Map<String, dynamic>> receipts = {}, commandReceipts = {};
  final List<Map<String, dynamic>> requests = [];
  void Function()? onCommand;
  @override
  bool get requiresLease => true;
  @override
  Future<void> reauthenticateReplacement(
    String email,
    String password,
    String expectedActor,
  ) async {
    if (expectedActor != user.id) throw StateError('Account mismatch');
  }

  @override
  void bindDevice(String id) => device = id;
  @override
  Future<Map<String, dynamic>> snapshot() async {
    reads++;
    if (offline) throw StateError('No network');
    if (retired.contains(device)) {
      throw const PostgrestException(message: 'Device retired', code: '42501');
    }
    return {
      ...cloneMap(server.toJson()),
      'actor': user.toJson(),
      'serverTime': now.toIso8601String(),
      'receipts': receipts.values.toList(),
      'closures': requests,
      'devices': [],
    };
  }

  @override
  Future<Map<String, dynamic>> push(Operation op, String deviceId) async {
    if (offline) throw StateError('No network');
    if (receipts.containsKey(op.id)) return receipts[op.id]!;
    final status = retired.contains(deviceId)
        ? 'late'
        : conflict
        ? 'conflict'
        : 'accepted';
    if (status == 'accepted') {
      server.apply(op, user);
    } else {
      server.incidents.add({
        'operation': op.toJson(),
        'reason': status,
        'status': status,
      });
    }
    return receipts[op.id] = {'id': op.id, 'status': status, 'reason': status};
  }

  @override
  Future<Map<String, dynamic>> command(
    String id,
    String action,
    Map<String, dynamic> payload,
  ) async {
    if (offline) throw StateError('No network');
    commandCalls.add(id);
    if (commandReceipts.containsKey(id)) return commandReceipts[id]!;
    onCommand?.call();
    if (action == 'ack_close') {
      final req = requests.firstWhere((r) => r['id'] == payload['requestId']);
      (req['confirmedDevices'] as List).add(device);
    }
    final r = commandReceipts[id] = action == 'replace_device'
        ? {'newDeviceId': payload['newDeviceId'], 'previousCommands': []}
        : {'confirmed': true};
    if (loseCommandReceipt) {
      loseCommandReceipt = false;
      throw StateError('Lost reply after commit');
    }
    return r;
  }

  void request(String deviceId) => requests.add({
    'id': 'request-1',
    'orderId': 'o-1048',
    'revision': server.orders['o-1048']!.revision,
    'status': 'active',
    'requiredDevices': [deviceId],
    'confirmedDevices': <String>[],
  });
}

class FailingStore extends MemoryStore {
  int writes = 0;
  int? failAt;
  bool fail = false;
  @override
  Future<void> write(String value) async {
    writes++;
    if (fail || writes == failAt) throw StateError('Disk unavailable');
    await super.write(value);
  }
}

Future<WorkshopController> controller(
  TransportRemote remote,
  Vault vault,
) async {
  final c = WorkshopController(
    vault,
    remote: remote,
    actor: remote.user,
    clock: () => remote.now,
  );
  await c.load();
  return c;
}

void main() {
  test(
    'Previously validated encrypted session reopens offline without server lookup',
    () async {
      final r = TransportRemote();
      final store = MemoryStore();
      final key = await AesGcm.with256bits().newSecretKey();
      final c = await controller(r, Vault(store, key));
      await c.execute('o-1048', 'start', {'taskId': 't-1'});
      r.offline = true;
      final before = r.reads;
      final reopened = await controller(r, Vault(store, key));
      expect(r.reads, before);
      expect(reopened.accessAllowed, true);
      expect(reopened.outbox.single.kind, 'start');
      expect(reopened.state.orders['o-1048']!.times.single['end'], null);
      expect(store.value!.contains('Álex'), false);
      c.dispose();
      reopened.dispose();
    },
  );
  test(
    'Lease expires after 24 hours, keeps evidence and revalidates online',
    () async {
      final r = TransportRemote();
      final v = Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey());
      final c = await controller(r, v);
      await c.execute('o-1048', 'note', {'text': 'Pending original'});
      r.now = r.now.add(const Duration(hours: 24));
      r.offline = true;
      expect(c.accessAllowed, false);
      expect(c.visibleOrders, isEmpty);
      await expectLater(
        c.execute('o-1048', 'note', {'text': 'No authority'}),
        throwsA(isA<RuleException>()),
      );
      final reopened = await controller(r, v);
      expect(reopened.accessAllowed, false);
      expect(reopened.outbox.length, 1);
      r.offline = false;
      await reopened.synchronize();
      expect(reopened.accessAllowed, true);
      expect(reopened.outbox, isEmpty);
      c.dispose();
      reopened.dispose();
    },
  );
  test('Clock rollback after work blocks cached privileges', () async {
    final r = TransportRemote();
    final c = await controller(
      r,
      Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
    );
    r.now = r.now.add(const Duration(hours: 2));
    await c.execute('o-1048', 'note', {'text': 'At noon'});
    r.now = r.now.subtract(const Duration(hours: 1));
    expect(c.accessAllowed, false);
    expect(c.outbox.length, 1);
    c.dispose();
  });
  test(
    'Account mismatch and encrypted invalid lease cannot open another user cache',
    () {
      final saved = {
        'actor': demoActors[0].toJson(),
        'validatedAt': DateTime.utc(2026, 10, 6, 10).toIso8601String(),
      };
      expect(
        () => LocalSessionPolicy.cachedActor(
          saved,
          demoActors[1].id,
          DateTime.utc(2026, 10, 6, 11),
        ),
        throwsA(isA<RuleException>()),
      );
      expect(
        () => LocalSessionPolicy.cachedActor(
          {...saved, 'accessRevoked': true},
          demoActors[0].id,
          DateTime.utc(2026, 10, 6, 11),
        ),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Remote updates merge with pending conflicts; repeated refresh does not duplicate either',
    () async {
      final r = TransportRemote();
      final c = await controller(
        r,
        Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
      );
      await c.execute('o-1048', 'note', {'text': 'Local measurement'});
      final original = c.outbox.single.toJson();
      final office = demoActors.firstWhere((a) => a.isOffice);
      r.server.apply(
        Operation(
          id: 'remote-note',
          orderId: 'o-1048',
          kind: 'note',
          actorId: office.id,
          baseRevision: 0,
          at: r.now,
          payload: {'text': 'Office observation'},
        ),
        office,
      );
      r.conflict = true;
      await c.synchronize();
      await c.synchronize();
      final texts = c.state.orders['o-1048']!.notes
          .map((n) => n['text'])
          .toList();
      expect(texts.where((t) => t == 'Local measurement').length, 1);
      expect(texts.where((t) => t == 'Office observation').length, 1);
      expect(c.outbox.single.toJson(), original);
      expect(c.failures.length, 1);
      r.receipts[c.outbox.single.id]!['resolved'] = true;
      r.server.incidents.single['resolution'] = {
        'outcome': 'archive',
        'reason': 'Evidence preserved for follow-up',
      };
      await c.synchronize();
      expect(c.outbox, isEmpty);
      expect(c.state.incidents.single['operation'], original);
      c.dispose();
    },
  );
  test(
    'Persistent freeze precedes acknowledgement and survives lost reply and restart',
    () async {
      final r = TransportRemote();
      final v = Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey());
      final c = await controller(r, v);
      r.request(c.deviceId);
      r.loseCommandReceipt = true;
      await expectLater(c.confirmClose('o-1048'), throwsStateError);
      final saved = (await v.read())!;
      expect(saved['closeLocks']['o-1048']['locallyFrozen'], true);
      expect(c.pendingCommands.length, 1);
      final reopened = await controller(r, v);
      expect(reopened.frozen('o-1048'), true);
      await expectLater(
        reopened.execute('o-1048', 'note', {'text': 'Must freeze'}),
        throwsA(isA<RuleException>()),
      );
      await reopened.synchronize();
      expect(reopened.pendingCommands, isEmpty);
      expect(r.commandCalls[0], r.commandCalls[1]);
      expect(r.requests.single['confirmedDevices'], [reopened.deviceId]);
      r.requests.single['status'] = 'invalidated';
      await reopened.synchronize();
      expect(reopened.frozen('o-1048'), false);
      c.dispose();
      reopened.dispose();
    },
  );
  test('Failed disk freeze never sends acknowledgement', () async {
    final r = TransportRemote();
    final store = FailingStore();
    final v = Vault(store, await AesGcm.with256bits().newSecretKey());
    final c = await controller(r, v);
    r.request(c.deviceId);
    store.failAt = store.writes + 2;
    await expectLater(c.confirmClose('o-1048'), throwsStateError);
    expect(r.commandCalls, isEmpty);
    expect(c.frozen('o-1048'), false);
    c.dispose();
  });
  test(
    'Failed saving a command receipt retains the same command for retry',
    () async {
      final r = TransportRemote();
      final store = FailingStore();
      final v = Vault(store, await AesGcm.with256bits().newSecretKey());
      final c = await controller(r, v);
      r.request(c.deviceId);
      r.onCommand = () => store.fail = true;
      await expectLater(c.confirmClose('o-1048'), throwsStateError);
      expect(c.pendingCommands.length, 1);
      expect(c.commandHistory, isEmpty);
      store.fail = false;
      r.onCommand = null;
      await c.synchronize();
      expect(c.pendingCommands, isEmpty);
      expect(r.commandCalls[0], r.commandCalls[1]);
      c.dispose();
    },
  );
  test(
    'Revocation locks cached data, recovery conserves evidence and replacement gets new identity',
    () async {
      final r = TransportRemote();
      final v = Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey());
      final c = await controller(r, v);
      await c.execute('o-1048', 'note', {'text': 'Recovered actual record'});
      final original = c.outbox.single.toJson();
      final oldId = c.deviceId;
      r.retired.add(oldId);
      await c.synchronize();
      expect(c.accessAllowed, false);
      final reopened = await controller(r, v);
      expect(reopened.accessAllowed, false);
      expect(reopened.outbox.length, 1);
      await reopened.recoverRetiredRecords();
      expect(reopened.outbox, isEmpty);
      expect(r.server.incidents.single['operation'], original);
      expect(r.server.orders['o-1048']!.notes, isEmpty);
      await reopened.replaceRetiredDevice(
        email: 'synthetic@example.invalid',
        password: 'fictional-test-only',
      );
      expect(reopened.deviceId, isNot(oldId));
      expect(reopened.accessAllowed, true);
      expect(r.retired.contains(oldId), true);
      c.dispose();
      reopened.dispose();
    },
  );
}
