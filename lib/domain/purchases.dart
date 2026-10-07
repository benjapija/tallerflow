import 'dart:convert';
import 'engine.dart';
import 'management.dart';
import 'models.dart';

/// Immutable manual purchase/receipt evidence. Transport and stock application
/// must commit the returned delta with this ledger; this is not a supplier API.
class PurchaseLedger {
  final Map<String, dynamic> _data;
  PurchaseLedger([Map<String, dynamic>? data])
    : _data = cloneMap(
        data ?? {'revision': 0, 'orders': [], 'movements': [], 'receipts': []},
      );
  int get revision => _data['revision'];
  Map<String, dynamic> toJson() => cloneMap(_data);
  List<Map<String, dynamic>> get orders =>
      (toJson()['orders'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get movements =>
      (toJson()['movements'] as List).cast<Map<String, dynamic>>();

  PurchaseChange apply(
    String id,
    String action,
    Map<String, dynamic> payload,
    Actor actor,
    DateTime at, {
    required List<CatalogItem> catalog,
    required Map<String, int> availableStock,
    Set<String> repairOrders = const {},
  }) {
    if (!actor.active ||
        !actor.isOffice ||
        (actor.role != Role.admin && !actor.seeCosts)) {
      throw const RuleException(
        'Se requiere oficina activa con permiso para gestionar costes',
      );
    }
    final p = cloneMap(payload), next = toJson();
    final previous = (next['receipts'] as List)
        .where((r) => r['id'] == id)
        .firstOrNull;
    if (previous != null) {
      if (previous['actorId'] != actor.id ||
          previous['action'] != action ||
          _canonical(previous['payload']) != _canonical(p)) {
        throw const RuleException('Identificador reutilizado con otros datos');
      }
      return PurchaseChange(PurchaseLedger(next), const {}, true);
    }
    if (p['revision'] != revision) {
      throw const RuleException('El almacén cambió. Actualiza y revisa');
    }
    final reason = requiredText(p['reason'], 'Motivo', max: 2000);
    final delta = <String, int>{};
    if (action == 'purchase_create') {
      _keys(p, {
        'revision',
        'at',
        'reason',
        'id',
        'supplier',
        'reference',
        'expectedAt',
        'orderId',
        'lines',
      });
      final purchaseId = requiredText(p['id'], 'Pedido', max: 100);
      if ((next['orders'] as List).any((o) => o['id'] == purchaseId)) {
        throw const RuleException('El pedido ya existe');
      }
      final orderId = p['orderId'];
      if (orderId != null && !repairOrders.contains(orderId)) {
        throw const RuleException(
          'La reparación vinculada no pertenece al taller',
        );
      }
      final expected = p['expectedAt'] is String
          ? DateTime.tryParse(p['expectedAt'])
          : null;
      if (expected == null) {
        throw const RuleException('Indica la fecha prevista');
      }
      final raw = p['lines'];
      if (raw is! List || raw.isEmpty || raw.length > 100) {
        throw const RuleException(
          'El pedido necesita entre una y cien partidas',
        );
      }
      final lines = <Map<String, dynamic>>[], ids = <String>{};
      for (final v in raw) {
        final line = Map<String, dynamic>.from(v);
        _keys(line, {
          'id',
          'itemId',
          'packageSizeMilli',
          'packagesMilli',
          'unitCostCents',
        });
        final lineId = requiredText(line['id'], 'Partida', max: 100);
        if (!ids.add(lineId)) throw const RuleException('Partidas duplicadas');
        final item = catalog
            .where((c) => c.id == line['itemId'] && c.active)
            .firstOrNull;
        if (item == null) {
          throw const RuleException(
            'Selecciona un artículo activo del catálogo',
          );
        }
        final size = boundedInt(
          line['packageSizeMilli'],
          1000000000,
          'Contenido por envase',
          min: 1,
        );
        final packages = boundedInt(
          line['packagesMilli'],
          1000000000,
          'Envases solicitados',
          min: 1,
        );
        lines.add({
          'id': lineId,
          'itemId': item.id,
          'reference': item.reference,
          'description': item.description,
          'unit': item.unit,
          'packageSizeMilli': size,
          'requestedPackagesMilli': packages,
          'requestedMilli': _baseQuantity(packages, size),
          'unitCostCents': boundedInt(
            line['unitCostCents'],
            1000000000,
            'Coste por unidad',
          ),
        });
      }
      (next['orders'] as List).add({
        'id': purchaseId,
        'supplier': requiredText(p['supplier'], 'Proveedor', max: 300),
        'reference': requiredText(
          p['reference'],
          'Referencia del pedido',
          max: 300,
        ),
        'expectedAt': expected.toUtc().toIso8601String(),
        'orderId': orderId,
        'lines': lines,
        'actorId': actor.id,
        'createdAt': at.toUtc().toIso8601String(),
        'reason': reason,
      });
    } else if (action == 'purchase_receive' || action == 'supplier_return') {
      _keys(p, {
        'revision',
        'at',
        'reason',
        'purchaseId',
        'lineId',
        'packagesMilli',
        'reference',
      });
      final purchase = (next['orders'] as List)
          .where((o) => o['id'] == p['purchaseId'])
          .firstOrNull;
      final line = purchase == null
          ? null
          : (purchase['lines'] as List)
                .where((l) => l['id'] == p['lineId'])
                .firstOrNull;
      if (line == null) {
        throw const RuleException('Partida de pedido no encontrada');
      }
      if (at.isBefore(DateTime.parse(purchase['createdAt']))) {
        throw const RuleException(
          'La recepción o devolución debe ser posterior al pedido',
        );
      }
      final item = catalog.where((c) => c.id == line['itemId']).firstOrNull;
      if (item == null || item.unit != line['unit']) {
        throw const RuleException(
          'La unidad del catálogo cambió. Revisa el pedido',
        );
      }
      final packages = boundedInt(
            p['packagesMilli'],
            1000000000,
            'Envases',
            min: 1,
          ),
          quantity = _baseQuantity(packages, line['packageSizeMilli']);
      final rows = (next['movements'] as List).where(
        (m) => m['purchaseId'] == purchase['id'] && m['lineId'] == line['id'],
      );
      final received = rows
          .where((m) => m['kind'] == 'receive')
          .fold<int>(0, (s, m) => s + (m['quantityMilli'] as int));
      final returned = rows
          .where((m) => m['kind'] == 'supplier_return')
          .fold<int>(0, (s, m) => s + (m['quantityMilli'] as int));
      if (action == 'purchase_receive' &&
          received + quantity > line['requestedMilli']) {
        throw const RuleException('La recepción supera lo solicitado');
      }
      if (action == 'supplier_return' &&
          (quantity > received - returned ||
              quantity > (availableStock[item.id] ?? 0))) {
        throw const RuleException(
          'La devolución supera lo recibido o el stock disponible sin reservas',
        );
      }
      delta[item.id] = action == 'purchase_receive' ? quantity : -quantity;
      (next['movements'] as List).add({
        'id': id,
        'purchaseId': purchase['id'],
        'lineId': line['id'],
        'itemId': item.id,
        'kind': action == 'purchase_receive' ? 'receive' : 'supplier_return',
        'packagesMilli': packages,
        'quantityMilli': quantity,
        'unit': line['unit'],
        'unitCostCents': line['unitCostCents'],
        'costCents': roundProduct(quantity, line['unitCostCents'], 1000),
        'reference': requiredText(
          p['reference'],
          'Albarán o referencia',
          max: 300,
        ),
        'reason': reason,
        'actorId': actor.id,
        'at': at.toUtc().toIso8601String(),
      });
    } else {
      throw const RuleException('Acción de compra desconocida');
    }
    next['revision'] = revision + 1;
    (next['receipts'] as List).add({
      'id': id,
      'actorId': actor.id,
      'action': action,
      'payload': p,
    });
    return PurchaseChange(PurchaseLedger(next), Map.unmodifiable(delta), false);
  }

  static int _baseQuantity(int packages, int size) {
    final raw = BigInt.from(packages) * BigInt.from(size),
        divisor = BigInt.from(1000);
    if (raw % divisor != BigInt.zero ||
        raw ~/ divisor > BigInt.from(1000000000)) {
      throw const RuleException(
        'La conversión necesita una cantidad exacta con hasta tres decimales',
      );
    }
    return (raw ~/ divisor).toInt();
  }

  static void _keys(Map<String, dynamic> p, Set<String> allowed) {
    if (p.keys.any((k) => !allowed.contains(k))) {
      throw const RuleException('Campo de pedido no permitido');
    }
  }

  static String _canonical(dynamic value) {
    dynamic sorted(dynamic v) {
      if (v is Map) {
        return {
          for (final k in (v.keys.cast<String>().toList()..sort()))
            k: sorted(v[k]),
        };
      }
      if (v is List) {
        return v.map(sorted).toList();
      }
      return v;
    }

    return jsonEncode(sorted(value));
  }
}

class PurchaseChange {
  final PurchaseLedger ledger;
  final Map<String, int> stockDelta;
  final bool replayed;
  const PurchaseChange(this.ledger, this.stockDelta, this.replayed);
}

void applyPurchaseCommand(
  WorkshopState state,
  String id,
  String action,
  Map<String, dynamic> payload,
  Actor actor,
  DateTime now,
) {
  final at = payload['at'] == null
      ? now
      : payload['at'] is String
      ? DateTime.tryParse(payload['at'])
      : null;
  if (at == null || at.isAfter(now.add(const Duration(minutes: 2)))) {
    throw const RuleException('Fecha de movimiento no válida');
  }
  final result = PurchaseLedger(state.configuration['purchaseLedger']).apply(
    id,
    action,
    payload,
    actor,
    at,
    catalog: state.catalog,
    availableStock: {
      for (final item in state.catalog)
        item.id: state.stock(item.id) - state.reserved(item.id),
    },
    repairOrders: state.orders.keys.toSet(),
  );
  if (result.replayed) return;
  for (final entry in result.stockDelta.entries) {
    final index = state.catalog.indexWhere((i) => i.id == entry.key),
        item = state.catalog.firstWhere((i) => i.id == entry.key);
    final stock = item.stockMilli + entry.value;
    boundedInt(stock, 9007199254740991, 'Existencias');
    state.catalog[index] = CatalogItem.fromJson({
      ...item.toJson(),
      'stockMilli': stock,
    });
  }
  state.configuration['purchaseLedger'] = result.ledger.toJson();
  state.applied.add(id);
  state.audit.add({
    'id': id,
    'actorId': actor.id,
    'actor': actor.name,
    'kind': action,
    'at': at.toUtc().toIso8601String(),
    'reason': payload['reason'],
  });
}
