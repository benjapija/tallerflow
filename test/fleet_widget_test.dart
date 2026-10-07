import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/domain/fleets.dart';
import 'package:tallerflow/domain/vehicles.dart';
import 'package:tallerflow/ui/fleet_panel.dart';

void main() {
  testWidgets(
    'Office groups a vehicle and owner change hides its current work until membership review',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = WorkshopController(
        Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
        actor: demoActors[2],
      );
      await c.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnimatedBuilder(
                animation: c,
                builder: (context, _) => FleetPanel(
                  controller: c,
                  run: (f) => f(),
                  openOrder: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> fill(String label, String v) async =>
          tester.enterText(find.widgetWithText(TextFormField, label), v);
      await tester.tap(find.text('Crear flota'));
      await tester.pumpAndSettle();
      await fill('Nombre de la flota', 'Flota ficticia');
      await fill('Empresa o responsable', 'Responsable ficticio');
      await fill('Motivo y comprobación', 'Verificación ficticia');
      await tester.tap(find.text('Confirmar y guardar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Incorporar vehículo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4821LKR · Elena García').last);
      await tester.pumpAndSettle();
      await fill('Referencia dentro de la flota', 'Unidad 1');
      await fill(
        'Comprobación de pertenencia',
        'Confirmación ficticia del responsable',
      );
      await fill('Motivo', 'Incorporación comprobada');
      await tester.tap(find.text('Confirmar y guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Vínculo confirmado'), findsOneWidget);
      expect(find.text('OT-1048 · Volkswagen Golf'), findsOneWidget);
      final v = vehicleProfiles(c.state).first;
      await c.changeVehicle({
        'vehicleId': v['id'],
        'revision': v['revision'],
        'change': 'owner',
        'ownerId': 'new-owner',
        'name': 'Nuevo propietario ficticio',
        'phone': '',
        'reason': 'Cambio comprobado',
      });
      await tester.pumpAndSettle();
      expect(
        find.text('Revisar vínculo: propietario cambiado'),
        findsOneWidget,
      );
      expect(find.text('OT-1048 · Volkswagen Golf'), findsNothing);
      expect(
        FleetLedger(
          c.state.configuration['fleets'],
        ).groups.single['memberships'][0]['ownerSnapshot']['name'],
        'Elena García',
      );
      c.dispose();
    },
  );
}
