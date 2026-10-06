import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/ui/app.dart';
import 'package:tallerflow/ui/simulation.dart';

Future<WorkshopController> demoController() async {
  final c = WorkshopController(
    Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
  );
  await c.load();
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await loader.load();
  });
  testWidgets('Desktop starts and pauses a task without billing real time', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = await demoController();
    c.changeDemoActor(demoActors[0]);
    await tester.pumpWidget(TallerFlowApp(controller: c));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '48-21 lkr');
    await tester.pumpAndSettle();
    expect(find.text('Seat León'), findsNothing);
    await tester.tap(find.text('Volkswagen Golf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Iniciar').first);
    await tester.pumpAndSettle();
    expect(find.text('Pausar'), findsOneWidget);
    expect(c.state.orders['o-1048']!.billableMinutes, 0);
    await tester.tap(find.text('Pausar'));
    await tester.pumpAndSettle();
    expect(c.state.orders['o-1048']!.times.first['end'], isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
  testWidgets(
    'Mobile has no overflow and technician cannot enter office review',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = await demoController();
      c.changeDemoActor(demoActors[0]);
      await tester.pumpWidget(TallerFlowApp(controller: c));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Revisión').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Esta vista requiere permisos de oficina.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );
  testWidgets(
    'Three-device simulation fits mobile and switches to technician',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: ReliabilitySimulation()));
      await tester.pumpAndSettle();
      expect(find.text('Móvil Álex'), findsOneWidget);
      expect(find.text('Móvil Lucía'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Móvil Lucía'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
