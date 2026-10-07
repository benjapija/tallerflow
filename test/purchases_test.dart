import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/models.dart';
import 'package:tallerflow/domain/purchases.dart';

Map<String, dynamic> request(String item) => {
  'revision': 0,
  'id': 'purchase',
  'supplier': 'Fictional supplier',
  'reference': 'Manual order 1',
  'expectedAt': '2026-10-08T00:00:00Z',
  'orderId': 'o-1048',
  'reason': 'Fictional repair order',
  'lines': [
    {
      'id': 'oil',
      'itemId': item,
      'packageSizeMilli': 5000,
      'packagesMilli': 2000,
      'unitCostCents': 650,
    },
  ],
};
Map<String, dynamic> movement(int rev, int packages) => {
  'revision': rev,
  'purchaseId': 'purchase',
  'lineId': 'oil',
  'packagesMilli': packages,
  'reference': 'Fictional delivery note',
  'reason': 'Quantity physically checked',
};
void main() {
  final catalog = demoState().catalog,
      actor = demoActors.firstWhere((a) => a.role == Role.admin),
      at = DateTime.utc(2026, 10, 7);
  PurchaseChange create([Map<String, dynamic>? p]) => PurchaseLedger().apply(
    'create',
    'purchase_create',
    p ?? request(catalog.first.id),
    actor,
    at,
    catalog: catalog,
    availableStock: {},
    repairOrders: {'o-1048'},
  );
  test(
    'Two five-litre packages request ten litres and creation does not change stock',
    () {
      final r = create();
      expect(r.stockDelta, isEmpty);
      expect(r.ledger.orders.single['lines'][0]['requestedMilli'], 10000);
    },
  );
  test(
    'Partial receipts keep frozen cost, remaining quantity and original order',
    () {
      final first = create(), original = first.ledger.orders;
      final r = first.ledger.apply(
        'receive',
        'purchase_receive',
        movement(1, 1000),
        actor,
        at,
        catalog: catalog,
        availableStock: {},
      );
      expect(r.stockDelta[catalog.first.id], 5000);
      expect(r.ledger.movements.single['costCents'], 3250);
      expect(r.ledger.orders, original);
      final next = r.ledger.apply(
        'receive2',
        'purchase_receive',
        movement(2, 1000),
        actor,
        at,
        catalog: catalog,
        availableStock: {catalog.first.id: 5000},
      );
      expect(next.ledger.movements.length, 2);
      expect(next.stockDelta[catalog.first.id], 5000);
      expect(
        () => next.ledger.apply(
          'extra',
          'purchase_receive',
          movement(3, 1),
          actor,
          at,
          catalog: catalog,
          availableStock: {},
        ),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Lost-response replay produces no second stock delta and changed identity is rejected',
    () {
      final p = request(catalog.first.id),
          first = create(p),
          r = first.ledger.apply(
            'create',
            'purchase_create',
            p,
            actor,
            at,
            catalog: catalog,
            availableStock: {},
            repairOrders: {'o-1048'},
          );
      expect(r.replayed, true);
      expect(r.stockDelta, isEmpty);
      expect(r.ledger.revision, 1);
      expect(
        () => first.ledger.apply(
          'create',
          'purchase_create',
          {...p, 'supplier': 'Changed'},
          actor,
          at,
          catalog: catalog,
          availableStock: {},
        ),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Concurrent or excessive supplier returns cannot consume reserved or absent stock',
    () {
      final l = create().ledger
          .apply(
            'receipt',
            'purchase_receive',
            movement(1, 1000),
            actor,
            at,
            catalog: catalog,
            availableStock: {},
          )
          .ledger;
      expect(
        () => l.apply(
          'bad',
          'supplier_return',
          movement(2, 1000),
          actor,
          at,
          catalog: catalog,
          availableStock: {catalog.first.id: 4000},
        ),
        throwsA(isA<RuleException>()),
      );
      final r = l.apply(
        'return',
        'supplier_return',
        movement(2, 500),
        actor,
        at,
        catalog: catalog,
        availableStock: {catalog.first.id: 5000},
      );
      expect(r.stockDelta[catalog.first.id], -2500);
      expect(r.ledger.movements.first['quantityMilli'], 5000);
      expect(
        () => r.ledger.apply(
          'stale',
          'supplier_return',
          movement(2, 500),
          actor,
          at,
          catalog: catalog,
          availableStock: {catalog.first.id: 5000},
        ),
        throwsA(isA<RuleException>()),
      );
      expect(
        () => r.ledger.apply(
          'too-many',
          'supplier_return',
          movement(3, 501),
          actor,
          at,
          catalog: catalog,
          availableStock: {catalog.first.id: 5000},
        ),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Unsupported precision, forged fields and unrelated repair orders are rejected',
    () {
      for (final p in [
        {...request(catalog.first.id), 'orderId': 'foreign'},
        {...request(catalog.first.id), 'totalCents': 1},
        {
          ...request(catalog.first.id),
          'lines': [
            {
              'id': 'oil',
              'itemId': catalog.first.id,
              'packageSizeMilli': 1001,
              'packagesMilli': 333,
              'unitCostCents': 1,
            },
          ],
        },
      ]) {
        expect(() => create(p), throwsA(isA<RuleException>()));
      }
    },
  );
  test('Operators and inactive accounts cannot record manual purchases', () {
    for (final a in [
      demoActors[0],
      Actor(actor.id, actor.name, actor.role, active: false),
    ]) {
      expect(
        () => PurchaseLedger().apply(
          'create',
          'purchase_create',
          request(catalog.first.id),
          a,
          at,
          catalog: catalog,
          availableStock: {},
          repairOrders: {'o-1048'},
        ),
        throwsA(isA<RuleException>()),
      );
    }
  });
  test('Receipt dated before the original purchase is refused', () {
    expect(
      () => create().ledger.apply(
        'old',
        'purchase_receive',
        movement(1, 1000),
        actor,
        at.subtract(const Duration(days: 1)),
        catalog: catalog,
        availableStock: {},
      ),
      throwsA(isA<RuleException>()),
    );
  });
  test(
    'Ledger serialization retains movement evidence while returned views cannot alter originals',
    () {
      final l = create().ledger
          .apply(
            'receipt',
            'purchase_receive',
            movement(1, 1000),
            actor,
            at,
            catalog: catalog,
            availableStock: {},
          )
          .ledger;
      final restored = PurchaseLedger(l.toJson());
      expect(restored.toJson(), l.toJson());
      final exposed = restored.orders;
      exposed.single['supplier'] = 'Changed view';
      expect(restored.orders.single['supplier'], 'Fictional supplier');
    },
  );
}
