import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/ui/app.dart';
import 'package:tallerflow/ui/simulation.dart';

void main() {
  testWidgets('Render desktop, repair and mobile previews', (tester) async {
    final font = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    final c = WorkshopController(
      Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
    );
    await c.load();
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('preview'),
        child: TallerFlowApp(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('preview')),
      matchesGoldenFile('../previews/01-panel.png'),
    );
    await tester.tap(find.text('Volkswagen Golf'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('preview')),
      matchesGoldenFile('../previews/02-reparacion.png'),
    );
    c.changeDemoActor(demoActors[0]);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('preview'),
        child: TallerFlowApp(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('preview')),
      matchesGoldenFile('../previews/03-movil.png'),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    c.dispose();
  });
  testWidgets('Render actual three-device simulation', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    final font = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: tallerTheme(),
        home: const RepaintBoundary(
          key: ValueKey('sim-preview'),
          child: ReliabilitySimulation(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await expectLater(
      find.byKey(const ValueKey('sim-preview')),
      matchesGoldenFile('../previews/04-simulacion.png'),
    );
    await tester.ensureVisible(find.text('Renault Kangoo'));
    await tester.tap(find.text('Renault Kangoo'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Solicitar o renovar cierre'));
    await tester.tap(find.text('Solicitar o renovar cierre'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('sim-preview')),
      matchesGoldenFile('../previews/05-cierre.png'),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
