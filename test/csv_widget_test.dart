import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/domain/csv_import.dart';
import 'package:tallerflow/ui/csv_panel.dart';

void main() {
  testWidgets(
    'CSV controls hide catalog from office and all imports from operators',
    (tester) async {
      final c = WorkshopController(
        Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
        actor: demoActors[3],
      );
      await c.load();
      Future<void> show() => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: CsvPanel(controller: c)),
          ),
        ),
      );
      await show();
      expect(find.byType(DropdownButton<ImportKind>), findsOneWidget);
      final admin = tester.widget<DropdownButton<ImportKind>>(
        find.byType(DropdownButton<ImportKind>),
      );
      expect(admin.items!.length, 3);
      c.actor = demoActors[2];
      await show();
      await tester.pump();
      final office = tester.widget<DropdownButton<ImportKind>>(
        find.byType(DropdownButton<ImportKind>),
      );
      expect(office.items!.map((i) => i.value), [
        ImportKind.clients,
        ImportKind.vehicles,
      ]);
      c.actor = demoActors[0];
      await show();
      await tester.pump();
      expect(find.text('Seleccionar CSV y revisar'), findsNothing);
      expect(tester.takeException(), isNull);
      c.dispose();
    },
  );
}
