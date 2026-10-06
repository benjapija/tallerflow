import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/ui/app.dart';
import 'package:tallerflow/ui/pricing_panel.dart';

void main() {
  testWidgets('Mobile office reviews a decimal percentage with a reason', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = demoState();
    final o = s.orders['o-1048']!;
    await tester.pumpWidget(
      MaterialApp(
        theme: tallerTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PricingPanel(
              order: o,
              canEdit: true,
              showPrices: true,
              showCosts: true,
              settings: s.settings,
              members: demoActors,
              onReview: (p) async {
                s.apply(
                  Operation(
                    id: 'widget-pricing',
                    orderId: o.id,
                    kind: 'pricing_review',
                    actorId: 'office',
                    baseRevision: o.revision,
                    at: DateTime.now(),
                    payload: p,
                  ),
                  demoActors[2],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Precios y descuentos'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Revisar tarifa y descuento').first);
    await tester.tap(find.text('Revisar tarifa y descuento').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(2), '10,50');
    await tester.enterText(
      find.byType(TextFormField).at(3),
      'Atención ficticia revisada',
    );
    await tester.ensureVisible(find.text('Confirmar y guardar'));
    await tester.tap(find.text('Confirmar y guardar'));
    await tester.pumpAndSettle();
    expect(o.tasks.first['discountBps'], 1050);
    expect(
      o.data['pricingReviews'].single['reason'],
      'Atención ficticia revisada',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Cost-only permission renders known costs without assuming hidden prices',
    (tester) async {
      final s = demoState();
      final o = s.orders['o-1048']!;
      for (final t in o.tasks) {
        t.remove('rateCents');
      }
      for (final p in o.parts) {
        p.remove('priceCents');
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PricingPanel(
                order: o,
                canEdit: false,
                showPrices: false,
                showCosts: true,
                settings: s.settings,
                members: demoActors,
                onReview: (_) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Precios y descuentos'), findsNothing);
      expect(find.textContaining('Importe previsto'), findsNothing);
      expect(find.textContaining('Costes y margen estimado'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
