import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/photo_blobs.dart';
import 'package:tallerflow/data/simulation.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/domain/photos.dart';

Uint8List photo() => prepareTechnicalPhoto(
  Uint8List.fromList(img.encodePng(img.Image(width: 20, height: 12))),
);

class BrokenStore extends MemoryStore {
  bool fail = false;
  @override
  Future<void> write(String value) async {
    if (fail) throw StateError('Fictional disk full');
    await super.write(value);
  }
}

class PhotoRemote extends SimulatedRemote {
  final Map<String, Map<String, dynamic>> prepared = {};
  final Map<String, Uint8List> files = {};
  bool lose = true;
  int uploads = 0;
  PhotoRemote() : super(SimulatedWorkshop(), demoActors[0]);
  @override
  Future<Map<String, dynamic>> preparePhoto(
    String id,
    Map<String, dynamic> metadata,
  ) async {
    prepared.putIfAbsent(
      metadata['id'],
      () => {...metadata, 'status': 'pending'},
    );
    return prepared[metadata['id']]!;
  }

  @override
  Future<void> uploadPhoto(Map<String, dynamic> info, Uint8List bytes) async {
    uploads++;
    files.putIfAbsent(info['sha256'], () => bytes);
  }

  @override
  Future<Map<String, dynamic>> finalizePhoto(String id) async {
    final p = prepared[id]!;
    p['status'] = 'attached';
    workshop.state.configuration['photoManifest'] = prepared.values.toList();
    if (lose) {
      lose = false;
      throw StateError('Fictional lost verification response');
    }
    return p;
  }

  @override
  Future<Uint8List> downloadPhoto(Map<String, dynamic> info) async =>
      files[info['sha256']]!;
}

void main() {
  test('Fresh JPEG strips metadata and rejects invalid or excessive input', () {
    final image = img.Image(width: 2000, height: 30);
    image.exif.imageIfd.make = 'Fictional identifiable camera';
    final clean = prepareTechnicalPhoto(
      Uint8List.fromList(img.encodeJpg(image)),
    );
    final decoded = img.decodeJpg(clean)!;
    expect(decoded.width, 1920);
    expect(decoded.exif.isEmpty, true);
    expect(
      () => prepareTechnicalPhoto(Uint8List(17 * 1024 * 1024)),
      throwsFormatException,
    );
    expect(
      () => prepareTechnicalPhoto(Uint8List.fromList('not an image'.codeUnits)),
      throwsFormatException,
    );
  });
  test(
    'Encrypted blob validates its content hash and cannot overwrite evidence',
    () async {
      final key = await AesGcm.with256bits().newSecretKey();
      final stores = <String, MemoryStore>{};
      final blobs = PhotoBlobs(
        (h) => stores.putIfAbsent(h, MemoryStore.new),
        key,
      );
      final bytes = photo(), hash = await PhotoBlobs.digest(bytes);
      await blobs.write(hash, bytes);
      expect(stores[hash]!.value!.contains(base64Encode(bytes)), false);
      expect(await blobs.read(hash), bytes);
      await expectLater(blobs.write(hash, [1, 2, 3]), throwsFormatException);
      await expectLater(blobs.read('../escape'), throwsFormatException);
      final e = jsonDecode(stores[hash]!.value!);
      e['mac'] = base64Encode(Uint8List(16));
      stores[hash]!.value = jsonEncode(e);
      await expectLater(
        blobs.read(hash),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    },
  );
  test(
    'Capture, restart, encrypted backup and a different key preserve original queued bytes',
    () async {
      final remote = PhotoRemote(),
          store = MemoryStore(),
          key = await AesGcm.with256bits().newSecretKey();
      final c = WorkshopController(
        Vault(store, key),
        remote: remote,
        actor: demoActors[0],
      );
      await c.load();
      c.offline = true;
      await c.beginPhotoCapture('o-1048', 'Fictional damage');
      final captureId = c.captureTicket!['id'];
      await c.finishPhotoCapture(photo());
      final queue = c.photoQueue.single;
      final archive = await c.exportBackup();
      expect(archive['photoFiles'][queue['sha256']], isNotNull);
      final restarted = WorkshopController(
        c.vault,
        remote: remote,
        actor: demoActors[0],
      );
      await restarted.load();
      expect(restarted.photoQueue.single['id'], captureId);
      expect(await restarted.vault.photos.read(queue['sha256']), photo());
      final target = WorkshopController(
        Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
        remote: remote,
        actor: demoActors[0],
      );
      await target.load();
      await target.restoreLocalBackup(archive);
      expect(target.photoQueue.single, queue);
      expect(await target.vault.photos.read(queue['sha256']), photo());
      c.dispose();
      restarted.dispose();
      target.dispose();
    },
  );
  test(
    'Interrupted verification reuses photo identity and clears queue only with durable snapshot',
    () async {
      final remote = PhotoRemote(), store = MemoryStore();
      final c = WorkshopController(
        Vault(store, await AesGcm.with256bits().newSecretKey()),
        remote: remote,
        actor: demoActors[0],
      );
      await c.load();
      await c.beginPhotoCapture('o-1048', 'Fictional damage');
      await c.finishPhotoCapture(photo());
      final id = c.photoQueue.single['id'];
      await c.synchronize();
      expect(c.photoQueue, isNotEmpty);
      expect(c.syncError, isNotNull);
      await c.synchronize();
      expect(c.photoQueue, isEmpty);
      expect(remote.prepared.keys, {id});
      expect(remote.files.length, 1);
      expect(c.photoHistory.single['id'], id);
      c.dispose();
    },
  );
  test(
    'Metadata disk failure preserves the capture ticket and encrypted original without a phantom receipt',
    () async {
      final store = BrokenStore(), remote = PhotoRemote();
      final c = WorkshopController(
        Vault(store, await AesGcm.with256bits().newSecretKey()),
        remote: remote,
        actor: demoActors[0],
      );
      await c.load();
      await c.beginPhotoCapture('o-1048', 'Fictional damage');
      final ticket = Map.of(c.captureTicket!);
      store.fail = true;
      await expectLater(c.finishPhotoCapture(photo()), throwsStateError);
      expect(c.captureTicket, ticket);
      expect(c.photoQueue, isEmpty);
      expect(c.photoHistory, isEmpty);
      store.fail = false;
      await c.finishPhotoCapture(photo());
      expect(c.photoQueue.length, 1);
      c.dispose();
    },
  );
  test(
    'Missing or corrupted backup image is rejected before replacing local state',
    () async {
      final source = WorkshopController(
        Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
        remote: PhotoRemote(),
        actor: demoActors[0],
      );
      await source.load();
      source.offline = true;
      await source.beginPhotoCapture('o-1048', 'Fictional');
      await source.finishPhotoCapture(photo());
      final archive = await source.exportBackup();
      final target = WorkshopController(
        Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
        remote: PhotoRemote(),
        actor: demoActors[0],
      );
      await target.load();
      final previous = target.deviceId;
      archive['photoFiles'] = {};
      await expectLater(target.restoreLocalBackup(archive), throwsA(anything));
      expect(target.deviceId, previous);
      expect(target.photoQueue, isEmpty);
      source.dispose();
      target.dispose();
    },
  );
}
