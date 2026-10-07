import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/domain/planning.dart';
import 'package:tallerflow/ui/planning_panel.dart';

void main() {
  testWidgets(
    'Invalid or overlapping slots retain editable form data and valid slots use written Spanish dates',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = WorkshopController(
        Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
        actor: demoActors[2],
        clock: () => DateTime.utc(2026, 10, 7, 8),
      );
      await c.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnimatedBuilder(
                animation: c,
                builder: (context, _) =>
                    PlanningPanel(controller: c, run: (action) => action()),
              ),
            ),
          ),
        ),
      );
      Future<void> fill(String label, String value) async {
        await tester.enterText(
          find.widgetWithText(TextFormField, label),
          value,
        );
      }

      Future<void> open(String title) async {
        await tester.tap(find.text('Reservar cita'));
        await tester.pumpAndSettle();
        await fill('Título de la reserva', title);
        await fill('Inicio (dd/mm/aaaa hh:mm)', '08/10/2026 09:00');
        await fill('Fin (dd/mm/aaaa hh:mm)', '08/10/2026 10:00');
        await fill('Motivo y comprobación', 'Prueba ficticia de oficina');
        await tester.tap(find.text('Álex Martín'));
        await tester.pump();
      }

      await open('Cita ficticia');
      await tester.tap(find.text('Guardar reserva'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      final b = PlanningLedger(
        c.state.configuration['planning'],
      ).bookings.single;
      expect(b['start'], '2026-10-08T07:00:00.000Z');
      expect(b['end'], '2026-10-08T08:00:00.000Z');
      await open('Conservar esta propuesta');
      await tester.tap(find.text('Guardar reserva'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text('Se solapa con una reserva de operario o elevador'),
        findsOneWidget,
      );
      expect(find.text('Conservar esta propuesta'), findsOneWidget);
      expect(
        PlanningLedger(c.state.configuration['planning']).bookings,
        hasLength(1),
      );
      await fill('Inicio (dd/mm/aaaa hh:mm)', '08/10/2026 10:00');
      await fill('Fin (dd/mm/aaaa hh:mm)', '08/10/2026 11:00');
      await tester.tap(find.text('Guardar reserva'));
      await tester.pumpAndSettle();
      expect(
        PlanningLedger(c.state.configuration['planning']).bookings,
        hasLength(2),
      );
      c.dispose();
    },
  );
}
