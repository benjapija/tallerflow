import 'dart:convert';
import 'engine.dart';
import 'management.dart';
import 'models.dart';

// Pure draft model. UI, persisted operations, server permissions and portal are
// deliberately separate pending integration; this never authorizes a WorkOrder.
class QuoteLedger {
  final List<Map<String, dynamic>> _versions;
  final List<Map<String, dynamic>> _decisions;
  QuoteLedger({
    List<Map<String, dynamic>> versions = const [],
    List<Map<String, dynamic>> decisions = const [],
  }) : _versions = versions.map(_snapshot).toList(),
       _decisions = decisions.map(_snapshot).toList();

  Map<String, dynamic> toJson() =>
      _snapshot({'versions': _versions, 'decisions': _decisions});
  factory QuoteLedger.fromJson(Map<String, dynamic> data) => QuoteLedger(
    versions: (data['versions'] as List).cast<Map<String, dynamic>>(),
    decisions: (data['decisions'] as List).cast<Map<String, dynamic>>(),
  );
  Map<String, dynamic>? current(String id) =>
      _versions.where((v) => v['id'] == id).lastOrNull;

  Map<String, dynamic> prepare(WorkOrder order, Actor actor, Operation op) {
    _office(order, actor, op);
    final p = op.payload;
    _keys(p, {
      'id',
      'expectedVersion',
      'title',
      'reason',
      'validUntil',
      'lines',
    });
    final id = requiredText(p['id'], 'Presupuesto', max: 100);
    final old = current(id);
    if (old != null && old['orderId'] != order.id) {
      throw const RuleException('El presupuesto pertenece a otra orden');
    }
    if (boundedInt(p['expectedVersion'], 100000, 'Versión') !=
        (old?['version'] ?? 0)) {
      throw const RuleException('Revisa la versión actual del presupuesto');
    }
    final expiry = DateTime.tryParse(
      p['validUntil'] is String ? p['validUntil'] : '',
    );
    if (expiry == null || !expiry.isAfter(op.at)) {
      throw const RuleException('Indica una fecha de validez posterior');
    }
    final raw = p['lines'];
    if (raw is! List || raw.isEmpty || raw.length > 50) {
      throw const RuleException('Añade entre 1 y 50 partidas');
    }
    final ids = <String>{}, tasks = <String>{};
    final lines = <Map<String, dynamic>>[];
    for (final value in raw) {
      if (value is! Map<String, dynamic>) {
        throw const RuleException('Partida incompatible');
      }
      _keys(value, {'id', 'taskId', 'description', 'laborMinutes', 'parts'});
      final lineId = requiredText(value['id'], 'Partida', max: 100);
      final taskId = requiredText(value['taskId'], 'Tarea', max: 100);
      if (!ids.add(lineId) || !tasks.add(taskId)) {
        throw const RuleException(
          'Cada partida corresponde a una tarea distinta',
        );
      }
      final task = order.tasks.where((t) => t['id'] == taskId).firstOrNull;
      if (task == null || task['cancelled'] == true) {
        throw const RuleException('Selecciona una tarea vigente');
      }
      final components = <Map<String, dynamic>>[];
      final minutes = boundedInt(value['laborMinutes'], 14400, 'Minutos');
      if (minutes > 0) {
        components.add(
          _amount(
            {
              'kind': 'labor',
              'description': task['title'],
              'minutes': minutes,
              'unitPriceCents': boundedInt(
                task['rateCents'],
                10000000,
                'Tarifa',
              ),
              'taxBps': boundedInt(task['taxBps'], 10000, 'Impuesto'),
              'discountBps': boundedInt(
                task['discountBps'] ?? 0,
                10000,
                'Descuento',
              ),
            },
            minutes,
            60,
          ),
        );
      }
      final parts = value['parts'];
      if (parts is! List || parts.length > 40) {
        throw const RuleException('Revisa las piezas del presupuesto');
      }
      final references = <String>{};
      for (final part in parts) {
        if (part is! Map<String, dynamic>) {
          throw const RuleException('Pieza incompatible');
        }
        _keys(part, {
          'reference',
          'description',
          'unit',
          'quantityMilli',
          'unitPriceCents',
          'taxBps',
          'discountBps',
        });
        final ref = requiredText(part['reference'], 'Referencia', max: 100);
        if (!references.add(ref)) {
          throw const RuleException('Referencia duplicada en la partida');
        }
        final q = boundedInt(
          part['quantityMilli'],
          100000000,
          'Cantidad',
          min: 1,
        );
        components.add(
          _amount(
            {
              'kind': 'part',
              'reference': ref,
              'description': requiredText(
                part['description'],
                'Descripción',
                max: 300,
              ),
              'unit': requiredText(part['unit'], 'Unidad', max: 30),
              'quantityMilli': q,
              'unitPriceCents': boundedInt(
                part['unitPriceCents'],
                10000000,
                'Precio',
              ),
              'taxBps': boundedInt(part['taxBps'], 10000, 'Impuesto'),
              'discountBps': boundedInt(
                part['discountBps'],
                10000,
                'Descuento',
              ),
            },
            q,
            1000,
          ),
        );
      }
      if (components.isEmpty) {
        throw const RuleException('La partida necesita mano de obra o piezas');
      }
      final net = components.fold<int>(0, (v, c) => v + (c['netCents'] as int));
      final tax = components.fold<int>(0, (v, c) => v + (c['taxCents'] as int));
      lines.add({
        'id': lineId,
        'taskId': taskId,
        'description': requiredText(value['description'], 'Alcance', max: 1000),
        'scopeVersion': task['scopeVersion'] ?? 1,
        'priceVersion': task['priceVersion'] ?? 1,
        'components': components,
        'netCents': net,
        'taxCents': tax,
        'totalCents': net + tax,
      });
    }
    final next = _snapshot({
      'id': id,
      'version': (old?['version'] ?? 0) + 1,
      'orderId': order.id,
      'orderRevision': order.revision,
      'title': requiredText(p['title'], 'Título', max: 200),
      'reason': requiredText(p['reason'], 'Motivo', max: 2000),
      'validUntil': expiry.toUtc().toIso8601String(),
      'at': op.at.toUtc().toIso8601String(),
      'actorId': actor.id,
      'operationId': op.id,
      'customer': order.client,
      'lines': lines,
      'totalCents': lines.fold<int>(0, (v, l) => v + (l['totalCents'] as int)),
      'type': 'Presupuesto · no es una factura',
    });
    _versions.add(next);
    return next;
  }

  Map<String, dynamic> recordDecision(
    WorkOrder order,
    Actor actor,
    Operation op,
  ) {
    _office(order, actor, op);
    final p = op.payload;
    _keys(p, {
      'quoteId',
      'version',
      'customer',
      'channel',
      'evidence',
      'reason',
      'decisions',
    });
    final quote = current(requiredText(p['quoteId'], 'Presupuesto', max: 100));
    if (quote == null ||
        quote['orderId'] != order.id ||
        quote['version'] != p['version']) {
      throw const RuleException(
        'La decisión corresponde a una versión anterior',
      );
    }
    if (!DateTime.parse(quote['validUntil']).isAfter(op.at)) {
      throw const RuleException('El presupuesto ha caducado');
    }
    final customer = requiredText(p['customer'], 'Destinatario', max: 300);
    if (customer != quote['customer'] || customer != order.client) {
      throw const RuleException('Revisa el destinatario del presupuesto');
    }
    if (![
      'telephone',
      'in_person',
      'email',
      'written',
    ].contains(p['channel'])) {
      throw const RuleException('Indica el canal de autorización');
    }
    final raw = p['decisions'];
    if (raw is! List || raw.isEmpty || raw.length > 50) {
      throw const RuleException('Indica las partidas decididas');
    }
    final ids = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final decision in raw) {
      if (decision is! Map<String, dynamic>) {
        throw const RuleException('Decisión incompatible');
      }
      _keys(decision, {'lineId', 'accepted'});
      final lineId = requiredText(decision['lineId'], 'Partida', max: 100);
      if (!ids.add(lineId) || decision['accepted'] is! bool) {
        throw const RuleException('Revisa la decisión de cada partida');
      }
      final line = (quote['lines'] as List)
          .where((l) => l['id'] == lineId)
          .firstOrNull;
      if (line == null) throw const RuleException('Partida inexistente');
      final task = order.tasks
          .where((t) => t['id'] == line['taskId'])
          .firstOrNull;
      if (task == null ||
          task['cancelled'] == true ||
          (task['scopeVersion'] ?? 1) != line['scopeVersion'] ||
          (task['priceVersion'] ?? 1) != line['priceVersion']) {
        throw const RuleException(
          'El alcance o el precio ha cambiado; prepara otra versión',
        );
      }
      if (_decisions.any(
        (d) =>
            d['quoteId'] == quote['id'] &&
            d['version'] == quote['version'] &&
            (d['decisions'] as List).any((l) => l['lineId'] == lineId),
      )) {
        throw const RuleException(
          'La decisión original se conserva; prepara otra versión para cambiarla',
        );
      }
      result.add({
        'lineId': lineId,
        'taskId': line['taskId'],
        'accepted': decision['accepted'],
        'approvedCents': decision['accepted'] ? line['totalCents'] : 0,
      });
    }
    final recorded = _snapshot({
      'id': op.id,
      'quoteId': quote['id'],
      'version': quote['version'],
      'customer': customer,
      'channel': p['channel'],
      'evidence': requiredText(
        p['evidence'],
        'Soporte de autorización',
        max: 2000,
      ),
      'reason': requiredText(p['reason'], 'Motivo', max: 2000),
      'actorId': actor.id,
      'at': op.at.toUtc().toIso8601String(),
      'decisions': result,
    });
    _decisions.add(recorded);
    return recorded;
  }
}

void _office(WorkOrder order, Actor actor, Operation op) {
  if (!actor.isOffice ||
      !actor.active ||
      op.actorId != actor.id ||
      op.orderId != order.id) {
    throw const RuleException('Se requiere una cuenta activa de oficina');
  }
  if (order.issued) {
    throw const RuleException('El documento emitido se conserva');
  }
  if (op.baseRevision != order.revision) {
    throw const RuleException('Revisa la orden actual antes de continuar');
  }
}

void _keys(Map<String, dynamic> value, Set<String> keys) {
  if (value.keys.any((k) => !keys.contains(k))) {
    throw const RuleException('Campo de presupuesto no permitido');
  }
}

Map<String, dynamic> _amount(
  Map<String, dynamic> row,
  int quantity,
  int divisor,
) {
  final gross = roundProduct(quantity, row['unitPriceCents'] as int, divisor);
  final discount = roundProduct(gross, row['discountBps'] as int, 10000);
  final net = gross - discount;
  final tax = roundProduct(net, row['taxBps'] as int, 10000);
  return {
    ...row,
    'grossCents': gross,
    'discountCents': discount,
    'netCents': net,
    'taxCents': tax,
    'totalCents': net + tax,
  };
}

Map<String, dynamic> _snapshot(Map<String, dynamic> value) =>
    _freeze(jsonDecode(jsonEncode(value))) as Map<String, dynamic>;
dynamic _freeze(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable(
      value.map((k, v) => MapEntry(k as String, _freeze(v))),
    );
  }
  if (value is List) return List<dynamic>.unmodifiable(value.map(_freeze));
  return value;
}
