import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/domain/purchases.dart';
import 'package:tallerflow/ui/purchase_panel.dart';

void main() {
  testWidgets(
    'Office creates a manual request with exact package quantities and no stock change',
    (tester) async {
      final state = demoState();
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PurchasePanel(
                ledger: PurchaseLedger(),
                catalog: state.catalog,
                repairOrders: state.orders.values.toList(),
                canEdit: true,
                pending: false,
                onSave: (kind, payload) async {
                  expect(kind, 'purchase_create');
                  saved = payload;
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Crear pedido al proveedor'));
      await tester.pumpAndSettle();
      Future<void> input(String label, String value) async {
        final f = find.widgetWithText(TextFormField, label);
        await tester.ensureVisible(f);
        await tester.enterText(f, value);
      }

      await input('Proveedor', 'Proveedor ficticio');
      await input('Referencia del pedido', 'Pedido manual ficticio');
      await input('Motivo', 'Reposición ficticia');
      await input('Contenido por envase (${state.catalog.first.unit})', '5');
      await input('Envases solicitados', '2');
      await input('Coste por unidad del catálogo (€)', '6,50');
      await tester.tap(find.text('Guardar pedido'));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!['lines'].single['packageSizeMilli'], 5000);
      expect(saved!['lines'].single['packagesMilli'], 2000);
      expect(saved!['lines'].single['unitCostCents'], 650);
      expect(saved!['orderId'], isNull);
      expect(state.configuration['purchaseLedger'], isNull);
    },
  );
  testWidgets(
    'Pending movements disable another purchase and explain confirmed stock',
    (tester) async {
      final state = demoState();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PurchasePanel(
              ledger: PurchaseLedger(),
              catalog: state.catalog,
              repairOrders: [],
              canEdit: true,
              pending: true,
              onSave: (_, _) async =>
                  fail('Pending purchase must stay disabled'),
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Crear pedido al proveedor'),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.textContaining(
          'Las existencias muestran los movimientos confirmados',
        ),
        findsOneWidget,
      );
    },
  );
}
