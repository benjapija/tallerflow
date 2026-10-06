import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/backup_set.dart';
import 'package:tallerflow/data/photo_blobs.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/simulation.dart';

class FailingSetStore extends MemoryStore {
  bool fail = false;
  @override
  Future<void> write(String value) async {
    if (fail) throw StateError('Disk unavailable');
    await super.write(value);
  }
}

// Test-only derivation keeps protocol/large-file tests bounded. Production
// always uses the 600,000-iteration PBKDF2 implementation tested by backup_test.
Future<List<int>> testKey(String password, List<int> salt) async =>
    (await Sha256().hash([...utf8.encode(password), ...salt])).bytes;
const password = 'contraseña ficticia para recuperar';
Map<String, dynamic> archive(Map<String, int> files) => {
  'kind': 'TallerFlow',
  'version': 1,
  'archiveId': 'fictional-archive',
  'workshopId': 'fictional-workshop',
  'actorId': 'fictional-account',
  'local': {
    'actor': {'id': 'fictional-account', 'name': 'Fictional private contact'},
    'state': {'workshopId': 'fictional-workshop'},
    'outbox': [
      {'id': 'offline-original'},
    ],
  },
  'photoFiles': files,
};
List<BackupPartInput> inputs(List<BackupPart> parts) => [
  for (final p in parts)
    BackupPartInput(
      length: () async => p.bytes.length,
      read: () async => p.bytes,
    ),
];
BackupPart changed(
  BackupPart part,
  void Function(Map<String, dynamic>) mutate,
) {
  final e = Map<String, dynamic>.from(jsonDecode(utf8.decode(part.bytes)));
  mutate(e);
  return BackupPart(
    part.setId,
    part.index,
    part.last,
    Uint8List.fromList(utf8.encode(jsonEncode(e))),
  );
}

void main() {
  test(
    'A single encrypted part preserves metadata and does not disclose private content',
    () async {
      final codec = BackupSetCodec(deriveKey: testKey), source = archive({});
      final parts = await codec
          .sealParts(source, password, readPhoto: (_) async => null)
          .toList();
      expect(parts.length, 1);
      expect(parts.single.last, true);
      expect(
        utf8.decode(parts.single.bytes),
        isNot(contains('Fictional private contact')),
      );
      expect(
        await codec.openParts(
          inputs(parts),
          password,
          writePhoto: (_, _) async => fail('No photos'),
        ),
        source,
      );
      await expectLater(
        codec.openParts(
          inputs(parts),
          'wrong password 123',
          writePhoto: (_, _) async => fail('Wrong key wrote a file'),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'A copy over 32 MiB reads one original at a time and stages photos under a different device key',
    () async {
      final codec = BackupSetCodec(deriveKey: testKey),
          originals = <String, Uint8List>{};
      for (var i = 0; i < 12; i++) {
        final bytes = Uint8List(3 * 1024 * 1024);
        bytes[0] = i;
        bytes[1] = 255;
        originals[await PhotoBlobs.digest(bytes)] = bytes;
      }
      final source = archive(
        originals.map((hash, bytes) => MapEntry(hash, bytes.length)),
      );
      var reading = 0, maximum = 0;
      final parts = await codec
          .sealParts(
            source,
            password,
            readPhoto: (hash) async {
              reading++;
              if (reading > maximum) maximum = reading;
              await Future<void>.delayed(Duration.zero);
              reading--;
              return originals[hash];
            },
          )
          .toList();
      expect(
        originals.values.fold<int>(0, (n, b) => n + b.length),
        greaterThan(32 * 1024 * 1024),
      );
      expect(parts.length, greaterThan(1));
      expect(maximum, 1);
      expect(
        parts.every((p) => p.bytes.length <= BackupSetCodec.maxPartBytes),
        true,
      );
      final target = Vault(
        MemoryStore(),
        await AesGcm.with256bits().newSecretKey(),
      );
      final opened = await codec.openParts(
        inputs(parts.reversed.toList()),
        password,
        writePhoto: target.photos.write,
      );
      expect(opened, source);
      expect(await target.store.read(), isNull);
      for (final e in originals.entries) {
        expect(await target.photos.read(e.key), e.value);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
  test(
    'Missing, repeated, mixed and changed parts never yield a restorable archive',
    () async {
      final codec = BackupSetCodec(deriveKey: testKey),
          files = <String, Uint8List>{};
      for (var i = 0; i < 3; i++) {
        final b = Uint8List(4 * 1024 * 1024)..[0] = i;
        files[await PhotoBlobs.digest(b)] = b;
      }
      final source = archive(files.map((h, b) => MapEntry(h, b.length)));
      final parts = await codec
          .sealParts(source, password, readPhoto: (h) async => files[h])
          .toList();
      final other = await codec
          .sealParts(source, password, readPhoto: (h) async => files[h])
          .toList();
      expect(parts.length, greaterThan(1));
      final variants = <List<BackupPart>>[
        [parts.first],
        [parts.last],
        [parts.first, parts.first],
        [parts.first, other.last],
        [parts.first, changed(parts.last, (e) => e['last'] = false)],
        [
          parts.first,
          changed(parts.last, (e) {
            final b = base64Decode(e['cipher']);
            b[0] ^= 1;
            e['cipher'] = base64Encode(b);
          }),
        ],
        [parts.first, changed(parts.last, (e) => e['previous'] = '0' * 64)],
      ];
      for (final variant in variants) {
        final store = MemoryStore()..value = 'unchanged metadata';
        final target = Vault(store, await AesGcm.with256bits().newSecretKey());
        await expectLater(
          codec.openParts(
            inputs(variant),
            password,
            writePhoto: target.photos.write,
          ),
          throwsFormatException,
        );
        expect(store.value, 'unchanged metadata');
      }
    },
  );
  test(
    'Absent or changed photo bytes stop export and a failed staging write aborts recovery',
    () async {
      final codec = BackupSetCodec(deriveKey: testKey),
          bytes = Uint8List.fromList([1, 2, 3]);
      final hash = await PhotoBlobs.digest(bytes),
          source = archive({hash: bytes.length});
      for (final value in [
        null,
        Uint8List.fromList([1, 2, 4]),
      ]) {
        await expectLater(
          codec
              .sealParts(source, password, readPhoto: (_) async => value)
              .toList(),
          throwsFormatException,
        );
      }
      final parts = await codec
          .sealParts(source, password, readPhoto: (_) async => bytes)
          .toList();
      await expectLater(
        codec.openParts(
          inputs(parts),
          password,
          writePhoto: (_, _) async => throw StateError('Disk full'),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'Malformed envelopes and unsafe limits are rejected before deriving a key',
    () async {
      var calls = 0;
      final codec = BackupSetCodec(
        deriveKey: (p, s) async {
          calls++;
          return testKey(p, s);
        },
      );
      await expectLater(
        codec.openParts([], password, writePhoto: (_, _) async {}),
        throwsFormatException,
      );
      await expectLater(
        codec.openParts(
          [
            BackupPartInput(
              length: () async => BackupSetCodec.maxPartBytes + 1,
              read: () async => throw StateError('Should not read'),
            ),
          ],
          password,
          writePhoto: (_, _) async {},
        ),
        throwsFormatException,
      );
      await expectLater(
        codec
            .sealParts(archive({}), 'short', readPhoto: (_) async => null)
            .toList(),
        throwsFormatException,
      );
      expect(calls, 0);
    },
  );
  test(
    'Split recovery preserves original offline IDs and queued photos without restoring authorization',
    () async {
      final backend = SimulatedWorkshop();
      final source = WorkshopController(
        Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
        remote: SimulatedRemote(backend, demoActors[0]),
        actor: demoActors[0],
      );
      await source.load();
      source.offline = true;
      await source.execute('o-1048', 'start', {'taskId': 't-1'});
      await source.beginPhotoCapture('o-1048', 'Fotografía ficticia pendiente');
      await source.finishPhotoCapture(
        Uint8List.fromList([255, 216, 255, 1, 2, 255, 217]),
      );
      final copy = await source.exportBackup(splitFiles: true);
      expect((copy['photoFiles'] as Map).values.single, isA<int>());
      final codec = BackupSetCodec(deriveKey: testKey);
      final parts = await codec
          .sealParts(copy, password, readPhoto: source.vault.photos.read)
          .toList();
      final target = WorkshopController(
        Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
        remote: SimulatedRemote(backend, demoActors[0]),
        actor: demoActors[0],
      );
      await target.load();
      final opened = await codec.openParts(
        inputs(parts),
        password,
        writePhoto: target.vault.photos.write,
      );
      await target.restoreLocalBackup(
        opened,
        readPhoto: target.vault.photos.read,
      );
      expect(target.outbox.map((o) => o.id), source.outbox.map((o) => o.id));
      expect(target.photoQueue, source.photoQueue);
      expect(target.validatedAt, isNull);
      expect(target.accessRevoked, true);
      final hash = source.photoQueue.single['sha256'];
      expect(
        await target.vault.photos.read(hash),
        await source.vault.photos.read(hash),
      );
      source.dispose();
      target.dispose();
    },
  );
  test(
    'A failed final metadata write leaves the current account state intact after staging split files',
    () async {
      final source = WorkshopController(
        Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
        actor: demoActors[3],
      );
      await source.load();
      await source.beginPhotoCapture('o-1048', 'Ficticio');
      await source.finishPhotoCapture(
        Uint8List.fromList([255, 216, 255, 1, 255, 217]),
      );
      final copy = await source.exportBackup(splitFiles: true),
          codec = BackupSetCodec(deriveKey: testKey);
      final parts = await codec
          .sealParts(copy, password, readPhoto: source.vault.photos.read)
          .toList();
      final store = FailingSetStore();
      final target = WorkshopController(
        Vault(store, await AesGcm.with256bits().newSecretKey()),
        actor: demoActors[3],
      );
      await target.load();
      final before = store.value,
          beforeState = jsonEncode(target.state.toJson());
      final opened = await codec.openParts(
        inputs(parts),
        password,
        writePhoto: target.vault.photos.write,
      );
      store.fail = true;
      await expectLater(
        target.restoreLocalBackup(opened, readPhoto: target.vault.photos.read),
        throwsStateError,
      );
      expect(store.value, before);
      expect(jsonEncode(target.state.toJson()), beforeState);
      source.dispose();
      target.dispose();
    },
  );
}
