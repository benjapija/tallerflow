import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/ui/dialogs.dart';

void main() {
  testWidgets(
    'Return reception uses current owner and requires an explicit human classification',
    (tester) async {
      Map<String, dynamic>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await receptionDialog(
                    context,
                    demoActors,
                    sourceOrderId: 'original',
                    initial: {
                      'plate': '0001FIC',
                      'country': 'ES',
                      'vin': 'FICTITIOUS',
                      'vehicle': 'Fictional car',
                      'client': 'New fictional owner',
                      'phone': '',
                    },
                  );
                },
                child: const Text('Regreso'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Regreso'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Cliente actual'),
            )
            .initialValue,
        'New fictional owner',
      );
      Future<void> input(String label, String value) async {
        final f = find.widgetWithText(TextFormField, label);
        await tester.ensureVisible(f);
        await tester.enterText(f, value);
      }

      await input('Kilometraje de entrada', '100');
      await input('Descripción original del cliente', 'New symptom');
      await input('Motivo de la clasificación', 'Human must classify');
      await tester.tap(find.text('Confirmar y guardar'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(
        find.text('Selecciona la clasificación del regreso'),
        findsOneWidget,
      );
      expect(find.text('Regreso del vehículo'), findsOneWidget);
    },
  );
}
