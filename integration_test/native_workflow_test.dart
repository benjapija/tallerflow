import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/local_native.dart';
import 'package:tallerflow/data/simulation.dart';
import 'package:tallerflow/ui/app.dart';

// Runs twice in separate native processes. The encrypted file and operating
// system credential store are real; the workshop server is explicitly fictional.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
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
      remote: SimulatedRemote(server, demoActors[0]),
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
      await tester.tap(find.text('Iniciar').first);
      await waitForSavedRecords(1);
      expect(find.text('Pausar'), findsOneWidget);
      now = now.add(const Duration(seconds: 30));
      await tester.tap(find.text('Pausar'));
      await waitForSavedRecords(2);
      expect(c.outbox, hasLength(2));
      expect(c.state.orders['o-1048']!.times.single['end'], isNotNull);
    } else {
      expect(c.deviceId, original!['deviceId']);
      expect(c.outbox, hasLength(2));
      expect(c.state.orders['o-1048']!.times.single['end'], isNotNull);
      c.offline = false;
      await c.synchronize();
      await tester.pumpAndSettle();
      expect(c.syncError, isNull);
      expect(c.outbox, isEmpty);
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
        'billableMinutes': c.state.orders['o-1048']!.billableMinutes,
        'passed': true,
      }),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
}
