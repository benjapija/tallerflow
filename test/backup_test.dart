import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/backup.dart';
import 'package:tallerflow/data/cloud.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/models.dart';

class BackupRemote extends Remote {
  final state = demoState();
  final List<String> pushed = [];
  @override
  bool get requiresLease => true;
  @override
  Future<Map<String, dynamic>> snapshot() async => {
    ...state.toJson(),
    'actor': demoActors[0].toJson(),
    'serverTime': DateTime.now().toUtc().toIso8601String(),
  };
  @override
  Future<Map<String, dynamic>> push(Operation op, String device) async {
    pushed.add(op.id);
    state.apply(op, demoActors[0]);
    return {'status': 'accepted'};
  }

  @override
  Future<void> reauthenticateReplacement(
    String e,
    String p,
    String actor,
  ) async {}
}

class FailingBackupStore extends MemoryStore {
  bool fail = false;
  @override
  Future<void> write(String v) async {
    if (fail) throw StateError('Disk unavailable');
    await super.write(v);
  }
}

Future<WorkshopController> client({
  BackupRemote? remote,
  MemoryStore? store,
}) async {
  final c = WorkshopController(
    Vault(store ?? MemoryStore(), await AesGcm.with256bits().newSecretKey()),
    remote: remote ?? BackupRemote(),
    actor: demoActors[0],
  );
  await c.load();
  return c;
}

void main() {
  test(
    'Portable encrypted copy restores pending timer and originals under a different device key',
    () async {
      final remote = BackupRemote();
      final source = await client(remote: remote);
      source.offline = true;
      await source.execute('o-1048', 'start', {'taskId': 't-1'});
      await source.execute('o-1048', 'note', {
        'text': 'Original offline measurement',
      });
      source.closeLocks['o-1045'] = {
        'orderId': 'o-1045',
        'requestId': 'saved-request',
        'revision': 0,
        'locallyFrozen': true,
      };
      source.commandHistory.add({
        'id': 'old-receipt',
        'action': 'request_close',
        'result': {'requestId': 'saved-request'},
      });
      final archive = await source.exportBackup();
      final codec = BackupCodec();
      const password = 'una contraseña de recuperación ficticia';
      final bytes = await codec.seal(archive, password);
      expect(
        utf8.decode(bytes).contains('Original offline measurement'),
        false,
      );
      final opened = await codec.open(bytes, password);
      final target = await client(remote: remote);
      await target.restoreLocalBackup(opened);
      expect(
        target.outbox.map((x) => x.id).toList(),
        source.outbox.map((x) => x.id).toList(),
      );
      expect(target.state.orders['o-1048']!.times.single['end'], isNull);
      expect(target.closeLocks, source.closeLocks);
      expect(target.commandHistory, source.commandHistory);
      expect(target.accessAllowed, false);
      expect(
        target.restoredArchive!['originalLocal']['outbox'],
        archive['local']['outbox'],
      );
      await target.reauthenticate('synthetic@example.invalid', password);
      expect(target.accessAllowed, true);
      expect(target.outbox, isEmpty);
      await target.synchronize();
      expect(remote.pushed.toSet().length, 2);
      expect(remote.pushed.length, 2);
      expect(remote.state.orders['o-1048']!.times.length, 1);
      await expectLater(
        codec.open(bytes, 'wrong-password-123'),
        throwsA(isA<FormatException>()),
      );
      final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final cipher = base64Decode(envelope['cipher']);
      cipher[0] ^= 1;
      envelope['cipher'] = base64Encode(cipher);
      await expectLater(
        codec.open(
          Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
          password,
        ),
        throwsA(isA<FormatException>()),
      );
      source.dispose();
      target.dispose();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
  test(
    'Wrong workshop/account, incompatible commands and existing pending work do not overwrite local data',
    () async {
      final source = await client();
      source.offline = true;
      await source.execute('o-1048', 'note', {'text': 'Source evidence'});
      final archive = await source.exportBackup();
      final target = await client();
      final before = await target.vault.store.read();
      for (final changed in [
        {...archive, 'workshopId': 'other'},
        {...archive, 'actorId': 'other'},
        cloneMap(archive)..['local']['pendingCommands'] = ['bad'],
      ]) {
        await expectLater(
          target.restoreLocalBackup(changed),
          throwsA(anything),
        );
        expect(await target.vault.store.read(), before);
      }
      target.offline = true;
      await target.execute('o-1048', 'note', {'text': 'Target evidence'});
      final pending = await target.vault.store.read();
      await expectLater(
        target.restoreLocalBackup(archive),
        throwsA(isA<RuleException>()),
      );
      expect(await target.vault.store.read(), pending);
      source.dispose();
      target.dispose();
    },
  );
  test(
    'Disk failure during restoration preserves live state and encrypted store',
    () async {
      final source = await client();
      source.offline = true;
      await source.execute('o-1048', 'note', {'text': 'Recover this'});
      final archive = await source.exportBackup();
      final store = FailingBackupStore();
      final target = await client(store: store);
      final before = store.value;
      final state = cloneMap(target.state.toJson());
      store.fail = true;
      await expectLater(
        target.restoreLocalBackup(archive),
        throwsA(isA<StateError>()),
      );
      expect(store.value, before);
      expect(target.state.toJson(), state);
      expect(target.outbox, isEmpty);
      source.dispose();
      target.dispose();
    },
  );
  test('Incompatible envelope and weak password are refused', () async {
    final codec = BackupCodec();
    await expectLater(codec.seal({}, 'short'), throwsA(isA<FormatException>()));
    await expectLater(
      codec.open(
        Uint8List.fromList(utf8.encode('{}')),
        'a sufficiently long password',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
