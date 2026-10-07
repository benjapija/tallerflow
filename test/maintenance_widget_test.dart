import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/domain/maintenance.dart';
import 'package:tallerflow/domain/vehicles.dart';
import 'package:tallerflow/ui/maintenance_panel.dart';

void main() {
  testWidgets(
    'Manual plan retains invalid calendar input and records completion using Spanish local date',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = WorkshopController(
        Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
        actor: demoActors[2],
        clock: () => DateTime.utc(2026, 10, 7, 12),
      );
      await c.load();
      final vid = c.state.orders['o-1048']!.data['vehicleId'];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnimatedBuilder(
                animation: c,
                builder: (context, _) => MaintenancePanel(
                  controller: c,
                  vehicle: vehicleProfiles(
                    c.state,
                  ).firstWhere((v) => v['id'] == vid),
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> fill(String label, String value) async =>
          tester.enterText(find.widgetWithText(TextFormField, label), value);
      await tester.tap(find.text('Programar mantenimiento'));
      await tester.pumpAndSettle();
      await fill('Mantenimiento', 'Aceite ficticio');
      await fill(
        'Fuente o criterio de seguimiento',
        'Criterio manual revisado',
      );
      await fill('Fecha prevista (dd/mm/aaaa)', '30/02/2026');
      await fill('Kilometraje previsto', '130000');
      await fill('Repetir cada (meses)', '12');
      await fill('Repetir cada (km)', '15000');
      await fill('Motivo de la previsión', 'Ensayo ficticio');
      await tester.tap(find.text('Confirmar y guardar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Aceite ficticio'), findsOneWidget);
      expect(
        MaintenanceLedger(c.state.configuration['maintenance']).plans,
        isEmpty,
      );
      await fill('Fecha prevista (dd/mm/aaaa)', '08/10/2026');
      await tester.tap(find.text('Confirmar y guardar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('Registrar realizado'));
      await tester.pumpAndSettle();
      await fill(
        'Fecha y hora realizadas (dd/mm/aaaa hh:mm)',
        '07/10/2026 13:00',
      );
      await fill('Kilometraje comprobado', '129000');
      await fill(
        'Comprobación de la intervención realizada',
        'Aceite comprobado en prueba ficticia',
      );
      await fill('Motivo del registro', 'Intervención confirmada');
      await tester.tap(find.text('Confirmar y guardar'));
      await tester.pumpAndSettle();
      final p = MaintenanceLedger(
        c.state.configuration['maintenance'],
      ).plans.single;
      expect(p['dueDate'], '2027-10-07');
      expect(p['dueKm'], 144000);
      expect(p['completions'][0]['performedAt'], '2026-10-07T11:00:00.000Z');
      expect(find.text('Kilometraje previsto: 144000 km'), findsOneWidget);
      c.dispose();
    },
  );
}
