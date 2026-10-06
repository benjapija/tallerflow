import 'dart:convert';
import 'dart:io';
import 'package:tallerflow/data/local_native.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/cloud.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/models.dart';

class FakeRemote extends Remote {
  final state = demoState();
  bool disconnected = false, lostReceipt = false, conflict = false;
  List<String> calls = [];
  @override
  Future<Map<String, dynamic>> snapshot() async {
    if (disconnected) throw StateError('Offline');
    return cloneMap(state.toJson());
  }

  @override
  Future<Map<String, dynamic>> push(Operation op, String device) async {
    calls.add(op.id);
    if (disconnected) throw StateError('Offline');
    if (conflict) return {'status': 'conflict', 'reason': 'Concurrent update'};
    state.apply(op, demoActors.firstWhere((a) => a.id == op.actorId));
    if (lostReceipt) {
      lostReceipt = false;
      throw StateError('Connection lost after commit');
    }
    return {'status': 'accepted'};
  }
}

void main() {
  test(
    'Atomic store recovers a flushed new file after interrupted rotation',
    () async {
      final dir = await Directory.systemTemp.createTemp('tallerflow-test-');
      try {
        final key = await AesGcm.with256bits().newSecretKey();
        final file = File('${dir.path}/test.vault');
        final vault = Vault(AtomicFileStore(file), key);
        await vault.write({'sequence': 1});
        await vault.write({'sequence': 2});
        await file.rename('${file.path}.next');
        expect((await vault.read())!['sequence'], 2);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'Concurrent local writes are serialized and survive reopening',
    () async {
      final store = MemoryStore();
      final key = await AesGcm.with256bits().newSecretKey();
      final c = WorkshopController(Vault(store, key));
      await c.load();
      await Future.wait([
        c.execute('o-1048', 'note', {'text': 'First real observation'}),
        c.execute('o-1048', 'note', {'text': 'Second real observation'}),
      ]);
      final reopened = WorkshopController(Vault(store, key));
      await reopened.load();
      expect(reopened.state.orders['o-1048']!.notes.length, 2);
      c.dispose();
      reopened.dispose();
    },
  );

  test('Encrypted backup restores data and detects tampering', () async {
    final key = await AesGcm.with256bits().newSecretKey();
    final store = MemoryStore();
    final vault = Vault(store, key);
    final data = demoState().toJson();
    await vault.write({'state': data});
    expect(store.value!.contains('Elena'), false);
    expect((await Vault(store, key).read())!['state'], data);
    final e = jsonDecode(store.value!) as Map<String, dynamic>;
    final bytes = base64Decode(e['cipher']);
    bytes[0] ^= 1;
    e['cipher'] = base64Encode(bytes);
    store.value = jsonEncode(e);
    expect(() => vault.read(), throwsA(isA<SecretBoxAuthenticationError>()));
  });
  test('Active timer and outbox survive restart and receipt loss', () async {
    final store = MemoryStore();
    final key = await AesGcm.with256bits().newSecretKey();
    final remote = FakeRemote();
    final c = WorkshopController(
      Vault(store, key),
      remote: remote,
      actor: demoActors[0],
    );
    await c.load();
    c.offline = true;
    await c.execute('o-1048', 'start', {'taskId': 't-1'});
    final restored = WorkshopController(
      Vault(store, key),
      remote: remote,
      actor: demoActors[0],
    );
    await restored.load();
    expect(restored.outbox.length, 1);
    expect(restored.state.orders['o-1048']!.times.first['end'], isNull);
    remote.lostReceipt = true;
    await restored.synchronize();
    expect(restored.outbox.length, 1);
    await restored.synchronize();
    expect(restored.outbox, isEmpty);
    expect(remote.calls.length, 1);
    expect(
      remote.calls.single,
      restored.state.orders['o-1048']!.times.single['id'],
    );
    expect(remote.state.orders['o-1048']!.times.length, 1);
    c.dispose();
    restored.dispose();
  });
  test('Conflict retains original record and prevents closing', () async {
    final remote = FakeRemote();
    final c = WorkshopController(
      Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
      remote: remote,
      actor: demoActors[0],
    );
    await c.load();
    await c.execute('o-1048', 'note', {'text': 'Actual measurement: example'});
    remote.conflict = true;
    await c.synchronize();
    expect(c.outbox.single.payload['text'], 'Actual measurement: example');
    expect(c.failures.length, 1);
    expect(c.state.orders['o-1048']!.notes.length, 1);
    expect(
      c.issues(c.state.orders['o-1048']!).any((i) => i.contains('conflictos')),
      true,
    );
    c.dispose();
  });
}
