import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/fiscal_calculation.dart';
import 'package:tallerflow/domain/models.dart';
import 'package:tallerflow/ui/tax_breakdown.dart';

FiscalLine line({
  String id = 'part',
  int price = 1000,
  int quantity = 1000,
  int discount = 0,
  int rate = 2100,
  FiscalTax tax = FiscalTax.iva,
  FiscalTreatment treatment = FiscalTreatment.taxable,
  String reason = '',
}) => FiscalLine(
  id: id,
  description: 'Partida ficticia',
  quantityMilli: quantity,
  unitPriceCents: price,
  discountBps: discount,
  rateBps: rate,
  tax: tax,
  treatment: treatment,
  legalReason: reason,
);

Map<String, dynamic> savedNote() => {
  'netCents': 2502,
  'taxCents': 385,
  'totalCents': 2887,
  'lines': [
    {'netCents': 1502, 'taxCents': 315, 'taxBps': 2100},
    {'netCents': 1000, 'taxCents': 70, 'taxBps': 700},
  ],
};

void main() {
  test(
    'Fractional quantities and discounts precede tax, without floating point',
    () {
      final c = FiscalCalculation.calculate([
        line(price: 1101, quantity: 1500, discount: 1000),
      ]);
      expect(c.lines.single.grossCents, 1652);
      expect(c.lines.single.discountCents, 165);
      expect(c.baseCents, 1487);
      expect(c.taxCents, 312);
      expect(c.totalCents, 1799);
      expect(c.emissionEnabled, false);
    },
  );
  test('IVA, IGIC, IPSI and other stay separate even with the same rate', () {
    final c = FiscalCalculation.calculate([
      for (final tax in FiscalTax.values)
        line(id: tax.name, tax: tax, rate: 700),
      line(id: 'another iva', rate: 700),
    ]);
    expect(c.groups.length, 4);
    expect(c.groups.first.baseCents, 2000);
    expect(c.groups.first.taxCents, 140);
    expect(c.baseCents, 5000);
    expect(c.taxCents, 350);
  });
  test(
    'Groups sum line-rounded taxes without introducing a different cent',
    () {
      final c = FiscalCalculation.calculate([
        line(id: 'one', price: 3, rate: 2100),
        line(id: 'two', price: 3, rate: 2100),
      ]);
      expect(c.groups.single.baseCents, 6);
      expect(c.groups.single.taxCents, 2);
      expect(c.totalCents, 8);
    },
  );
  test(
    'Exemption, reverse charge and outside scope need justification and no charge',
    () {
      for (final t in FiscalTreatment.values.where(
        (t) => t != FiscalTreatment.taxable,
      )) {
        expect(
          () => line(treatment: t, rate: 0),
          throwsA(isA<RuleException>()),
        );
        expect(
          () => line(treatment: t, reason: 'Justificación ficticia'),
          throwsA(isA<RuleException>()),
        );
        final c = FiscalCalculation.calculate([
          line(treatment: t, rate: 0, reason: 'Justificación ficticia'),
        ]);
        expect(c.taxCents, 0);
        expect(c.totalCents, 1000);
      }
    },
  );
  test('Signed adjustments round symmetrically and require a reason', () {
    expect(
      () => FiscalCalculation.calculate([line(price: -3)]),
      throwsA(isA<RuleException>()),
    );
    final c = FiscalCalculation.calculate([
      line(price: -1101, quantity: 1500, discount: 1000),
    ], adjustmentReason: 'Ajuste ficticio, sin rectificación emitida');
    expect(c.baseCents, -1487);
    expect(c.taxCents, -312);
    expect(fiscalDecimal(c.totalCents), '-17.99');
    expect(fiscalDecimal(-1), '-0.01');
  });
  test(
    'Limits reject unsafe totals, invalid quantities, rates and duplicate IDs',
    () {
      expect(() => line(quantity: 0), throwsA(isA<RuleException>()));
      expect(() => line(rate: 10001), throwsA(isA<RuleException>()));
      expect(() => line(discount: -1), throwsA(isA<RuleException>()));
      expect(
        () => FiscalCalculation.calculate([line(), line()]),
        throwsA(isA<RuleException>()),
      );
      expect(
        () => FiscalCalculation.calculate([]),
        throwsA(isA<RuleException>()),
      );
      expect(
        () => FiscalCalculation.calculate([
          line(price: 1000000000000, quantity: 1000000000),
        ]),
        throwsA(isA<RuleException>()),
      );
      expect(
        () => FiscalCalculation.calculate([line(price: 1000000000000)]),
        throwsA(isA<RuleException>()),
      );
      final c = FiscalCalculation.calculate([line(discount: 10000)]);
      expect(c.totalCents, 0);
    },
  );
  test(
    'Saved amounts and legacy unknown types stay unchanged and immutable',
    () {
      final note = savedNote();
      note['lines'][1].remove('taxBps');
      final original = cloneMap(note);
      final b = SavedTaxBreakdown.fromNote(note, demoActors[2]);
      expect(b.groups[1].rateBps, isNull);
      expect(b.totalCents, 2887);
      expect(note, original);
      note['lines'][0]['taxCents'] = 999;
      expect(b.groups.first.taxCents, 315);
      expect(() => b.groups.clear(), throwsUnsupportedError);
      final c = FiscalCalculation.calculate([line()]);
      expect(() => c.lines.clear(), throwsUnsupportedError);
    },
  );
  test(
    'Saved totals cannot hide corrupt rows; operators and inactive office are denied',
    () {
      final n = savedNote()..['totalCents'] = 1;
      expect(
        () => SavedTaxBreakdown.fromNote(n, demoActors[2]),
        throwsA(isA<RuleException>()),
      );
      expect(
        () => SavedTaxBreakdown.fromNote(savedNote(), demoActors[0]),
        throwsA(isA<RuleException>()),
      );
      final inactive = Actor.fromJson({
        ...demoActors[2].toJson(),
        'active': false,
      });
      expect(
        () => SavedTaxBreakdown.fromNote(savedNote(), inactive),
        throwsA(isA<RuleException>()),
      );
    },
  );
  testWidgets(
    'Office can review a saved breakdown and close without changing the note',
    (tester) async {
      final note = savedNote(), before = cloneMap(savedNote());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaxBreakdownButton(
              source: () => note,
              actor: () => demoActors[2],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Desglose de impuestos'));
      await tester.pumpAndSettle();
      expect(find.text('21,00 % registrado'), findsOneWidget);
      expect(find.text('7,00 % registrado'), findsOneWidget);
      expect(find.text('Total: ${money(2887)}'), findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      expect(note, before);
      expect(tester.takeException(), isNull);
    },
  );
}
