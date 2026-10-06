import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/domain/models.dart';
import 'package:tallerflow/domain/vehicles.dart';
import 'package:tallerflow/ui/app.dart';
import 'package:tallerflow/ui/vehicle_history.dart';

void main() {
  testWidgets(
    'Mobile office changes the owner without altering the original repair',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = WorkshopController(
        Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
      );
      await c.load();
      c.changeDemoActor(demoActors[2]);
      final before = cloneMap(c.state.orders['o-1048']!.data);
      await tester.pumpWidget(
        MaterialApp(
          theme: tallerTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: VehicleHistory(controller: c, openOrder: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Cambiar propietario').first);
      await tester.tap(find.text('Cambiar propietario').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Nuevo cliente ficticio',
      );
      await tester.enterText(find.byType(TextFormField).at(1), '600000000');
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'Documentación ficticia revisada',
      );
      await tester.tap(find.text('Confirmar y guardar'));
      await tester.pumpAndSettle();
      expect(
        vehicleProfiles(c.state).first['owner']['name'],
        'Nuevo cliente ficticio',
      );
      expect(c.state.orders['o-1048']!.data, before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );
  testWidgets(
    'Technical history hides owner controls and previous recipients',
    (tester) async {
      final c = WorkshopController(
        Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
      );
      await c.load();
      c.changeDemoActor(demoActors[0]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VehicleHistory(controller: c, openOrder: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cambiar propietario'), findsNothing);
      expect(find.textContaining('Propietario actual:'), findsNothing);
      await tester.tap(find.textContaining('OT-1048 ·').first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Destinatario de esta reparación:'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );
}
