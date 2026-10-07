import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:tallerflow/data/backup_set.dart';
import 'package:tallerflow/data/photo_blobs.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/local_native.dart';
import 'package:tallerflow/data/simulation.dart';
import 'package:tallerflow/ui/app.dart';

// Runs twice in separate native processes. The encrypted file and operating
// system credential store are real; the workshop server is explicitly fictional.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  const scope = String.fromEnvironment('TF_RUN_SCOPE');
  const stage = String.fromEnvironment('TF_STAGE');
  const evidencePath = String.fromEnvironment(
    'TF_EVIDENCE_DIR',
    defaultValue: 'build/native-test-evidence',
  );
  testWidgets('native offline work survives a process restart ($stage)', (
    tester,
  ) async {
    expect(RegExp(r'^native-test-[a-zA-Z0-9-]+$').hasMatch(scope), isTrue);
    expect(['record', 'restore'], contains(stage));
    final server = SimulatedWorkshop();
    var now = DateTime.now().toUtc().subtract(const Duration(seconds: 30));
    final vault = await openVault(scope);
    final original = await vault.read();
    if (stage == 'record') {
      expect(original, isNull, reason: 'Every run requires an isolated scope');
    } else {
      expect(
        original,
        isNotNull,
        reason: 'The previous native process saved it',
      );
      expect(original!['outbox'], hasLength(2));
      expect(original['outbox'][0]['kind'], 'start');
      expect(original['outbox'][1]['kind'], 'stop');
    }
    final c = WorkshopController(
      vault,
      remote: NativePhotoRemote(server),
      actor: demoActors[0],
      clock: () => now,
    );
    await c.load();
    Future<void> waitForSavedRecords(int count) async {
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (true) {
          if ((await vault.read())?['outbox'].length == count) return;
          if (DateTime.now().isAfter(deadline)) {
            fail('The native file did not finish saving $count records');
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pumpAndSettle();
    }

    c.offline = true;
    await tester.pumpWidget(TallerFlowApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Volkswagen Golf'));
    await tester.pumpAndSettle();
    if (stage == 'record') {
      await tester.ensureVisible(find.text('Iniciar').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Iniciar').first);
      await waitForSavedRecords(1);
      expect(find.text('Pausar'), findsOneWidget);
      now = now.add(const Duration(seconds: 30));
      await tester.ensureVisible(find.text('Pausar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pausar'));
      await waitForSavedRecords(2);
      expect(c.outbox, hasLength(2));
      expect(c.state.orders['o-1048']!.times.single['end'], isNotNull);
      await tester.runAsync(() async {
        await c.beginPhotoCapture(
          'o-1048',
          'Fotografía ficticia para reinicio nativo',
        );
        await c.finishPhotoCapture(
          Uint8List.fromList(img.encodeJpg(img.Image(width: 16, height: 12))),
        );
        final archive = await c.exportBackup(splitFiles: true);
        final dir = Directory(
          '${(await getApplicationSupportDirectory()).path}/$scope.backup',
        );
        await dir.create(recursive: true);
        await for (final part in BackupSetCodec().sealParts(
          archive,
          'Contraseña ficticia de copia nativa',
          readPhoto: vault.photos.read,
        )) {
          await File(
            '${dir.path}/${part.fileName}',
          ).writeAsBytes(part.bytes, flush: true);
        }
      });
      expect(c.photoQueue, hasLength(1));
    } else {
      expect(c.deviceId, original!['deviceId']);
      expect(c.outbox, hasLength(2));
      expect(c.state.orders['o-1048']!.times.single['end'], isNotNull);
      expect(c.photoQueue, hasLength(1));
      await tester.runAsync(() async {
        final copy = await openVault('$scope-copy');
        final dir = Directory(
          '${(await getApplicationSupportDirectory()).path}/$scope.backup',
        );
        final parts = await dir
            .list()
            .where((e) => e.path.endsWith('.tfpart'))
            .cast<File>()
            .toList();
        expect(parts, isNotEmpty);
        final archive = await BackupSetCodec().openParts(
          [
            for (final f in parts)
              BackupPartInput(length: f.length, read: f.readAsBytes),
          ],
          'Contraseña ficticia de copia nativa',
          writePhoto: copy.photos.write,
        );
        final restored = WorkshopController(
          copy,
          remote: NativePhotoRemote(SimulatedWorkshop()),
          actor: demoActors[0],
        );
        await restored.load();
        await restored.restoreLocalBackup(archive, readPhoto: copy.photos.read);
        expect(restored.deviceId, c.deviceId);
        expect(restored.restoredArchive!['sourceDeviceId'], c.deviceId);
        expect(
          restored.restoredArchive!['previousLocal']['deviceId'],
          isNot(c.deviceId),
        );
        expect(restored.accessRevoked, true);
        expect(restored.outbox.map((o) => o.id), c.outbox.map((o) => o.id));
        expect(restored.photoQueue.single['id'], c.photoQueue.single['id']);
        expect(
          await copy.photos.read(c.photoQueue.single['sha256']),
          await vault.photos.read(c.photoQueue.single['sha256']),
        );
        expect(restored.validatedAt, isNull);
        restored.dispose();
      });
      c.offline = false;
      await c.synchronize();
      await tester.pumpAndSettle();
      expect(c.syncError, isNull);
      expect(c.outbox, isEmpty);
      expect(c.photoQueue, isEmpty);
      expect((await vault.read())!['photoQueue'], isEmpty);
      expect(server.state.orders['o-1048']!.times, hasLength(1));
      final time = server.state.orders['o-1048']!.times.single;
      expect(
        DateTime.parse(time['end']).difference(DateTime.parse(time['start'])),
        const Duration(seconds: 30),
      );
      await c.synchronize();
      expect(server.state.orders['o-1048']!.times, hasLength(1));
      expect((await vault.read())!['outbox'], isEmpty);
      final office = server.snapshot(demoActors[2], '$scope-office');
      final order = (office['orders'] as List).firstWhere(
        (o) => o['id'] == 'o-1048',
      );
      expect(order['times'], hasLength(1));
    }
    expect(c.state.orders['o-1048']!.billableMinutes, 0);
    expect(tester.takeException(), isNull);
    final folder = await getApplicationSupportDirectory();
    final stored = await File('${folder.path}/$scope.vault').readAsString();
    expect(stored, isNot(contains('Volkswagen')));
    expect(stored, isNot(contains('Elena García')));
    // The artifact contains results only, never vaults or operating system keys.
    final evidence = Directory(evidencePath);
    await evidence.create(recursive: true);
    await File('${evidence.path}/$stage.json').writeAsString(
      jsonEncode({
        'stage': stage,
        'platform': Platform.operatingSystem,
        'nativeCredentialStore': true,
        'nativeEncryptedFile': true,
        'server': 'fictional-in-memory',
        'authHttpValidated': false,
        'pendingRecords': c.outbox.length,
        'pendingPhotos': c.photoQueue.length,
        'photoEncryptedFile': true,
        'splitBackupRestoredUnderNewDeviceKey': stage == 'restore',
        'billableMinutes': c.state.orders['o-1048']!.billableMinutes,
        'passed': true,
      }),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
}

class NativePhotoRemote extends SimulatedRemote {
  final prepared = <String, Map<String, dynamic>>{};
  final files = <String, Uint8List>{};
  NativePhotoRemote(SimulatedWorkshop server) : super(server, demoActors[0]);
  @override
  Future<Map<String, dynamic>> preparePhoto(
    String id,
    Map<String, dynamic> p,
  ) async => prepared.putIfAbsent(p['id'], () => {...p, 'status': 'pending'});
  @override
  Future<void> uploadPhoto(Map<String, dynamic> p, Uint8List bytes) async {
    expect(await PhotoBlobs.digest(bytes), p['sha256']);
    files.putIfAbsent(p['sha256'], () => bytes);
  }

  @override
  Future<Map<String, dynamic>> finalizePhoto(String id) async {
    final p = prepared[id]!;
    p['status'] = 'attached';
    workshop.state.configuration['photoManifest'] = prepared.values.toList();
    return p;
  }
}
