import 'engine.dart';
import 'models.dart';
import 'management.dart';

void applyPricingReview(WorkOrder order, Operation op, Actor actor) {
  if (!actor.isOffice) {
    throw const RuleException('Se requiere permiso de oficina');
  }
  if (op.baseRevision != order.revision) {
    throw const RuleException('La orden ha cambiado. Actualiza y revisa');
  }
  final p = op.payload;
  const keys = {
    'target',
    'targetId',
    'unitPriceCents',
    'taxBps',
    'discountBps',
    'charge',
    'reason',
  };
  if (p.keys.any((k) => !keys.contains(k))) {
    throw const RuleException('Campo de revisión no permitido');
  }
  final reason = requiredText(p['reason'], 'Motivo');
  final price = boundedInt(p['unitPriceCents'], 10000000, 'Precio');
  final tax = boundedInt(p['taxBps'], 10000, 'Impuesto');
  final discount = boundedInt(p['discountBps'], 10000, 'Descuento');
  if (p['charge'] is! bool) throw const RuleException('Indica si se cobra');
  final labor = p['target'] == 'labor';
  if (!labor && p['target'] != 'part') {
    throw const RuleException('Partida inválida');
  }
  final entry = (labor ? order.tasks : order.parts)
      .where((e) => e['id'] == p['targetId'])
      .firstOrNull;
  if (entry == null ||
      (labor ? entry['cancelled'] == true : entry['kind'] != 'consume')) {
    throw const RuleException('Selecciona una tarea vigente o un consumo');
  }
  if (labor && p['charge'] != true) {
    throw const RuleException(
      'Para no cobrar mano de obra, revisa sus minutos o aplica descuento',
    );
  }
  if (labor &&
      order.times.any((e) => e['taskId'] == entry['id'] && e['end'] == null)) {
    throw const RuleException(
      'Pausa los cronómetros de la tarea antes de revisar',
    );
  }
  final priceKey = labor ? 'rateCents' : 'priceCents';
  final before = <String, dynamic>{
    'unitPriceCents': entry[priceKey] ?? 0,
    'taxBps': entry['taxBps'] ?? 2100,
    'discountBps': entry['discountBps'] ?? 0,
    'charge': labor || entry['charge'] == true,
  };
  final after = <String, dynamic>{
    'unitPriceCents': price,
    'taxBps': tax,
    'discountBps': discount,
    'charge': p['charge'],
  };
  final requiresAuthorization =
      p['charge'] == true &&
      (before['charge'] != true ||
          price > before['unitPriceCents'] ||
          tax > before['taxBps'] ||
          discount < before['discountBps']);
  final task = labor
      ? entry
      : order.tasks.where((t) => t['id'] == entry['taskId']).firstOrNull;
  if (task == null) throw const RuleException('Tarea no encontrada');
  if (requiresAuthorization) {
    task['previousAuthorizations'] = [
      ...(task['previousAuthorizations'] as List? ?? []),
      if (task['authorization'] != null) cloneMap(task['authorization']),
    ];
    task['authorized'] = false;
    task['authorization'] = null;
    task['approvedCents'] = 0;
  }
  entry[priceKey] = price;
  entry['taxBps'] = tax;
  entry['discountBps'] = discount;
  if (!labor) {
    entry['charge'] = p['charge'];
    entry['reviewed'] = true;
    entry['noChargeReason'] = p['charge'] == false ? reason : null;
  }
  task['priceVersion'] = (task['priceVersion'] as int? ?? 1) + 1;
  order.data['pricingReviews'] = [
    ...(order.data['pricingReviews'] as List? ?? []),
    {
      'id': op.id,
      'target': p['target'],
      'targetId': entry['id'],
      'actorId': actor.id,
      'at': op.at.toUtc().toIso8601String(),
      'reason': reason,
      'before': before,
      'after': after,
      'requiresAuthorization': requiresAuthorization,
    },
  ];
}

class EstimatedMargin {
  final int revenueCents,
      materialCostCents,
      laborCostCents,
      missingMaterialCosts;
  final bool laborCostKnown;
  const EstimatedMargin(
    this.revenueCents,
    this.materialCostCents,
    this.laborCostCents,
    this.missingMaterialCosts,
    this.laborCostKnown,
  );
  bool get complete => missingMaterialCosts == 0 && laborCostKnown;
  int get registeredCostCents => materialCostCents + laborCostCents;
  int? get marginCents => complete ? revenueCents - registeredCostCents : null;
}

/// Estimates use recorded work, never billable minutes or tax-inclusive income.
/// Legacy tasks without a cost snapshot use the currently configured internal rate.
EstimatedMargin estimateMargin(
  WorkOrder order,
  Map<String, dynamic> settings,
  DateTime now, {
  bool includeRevenue = true,
}) {
  var materials = 0, missing = 0, labor = 0;
  var laborKnown = true;
  for (final p in order.parts.where((p) => p['kind'] == 'consume')) {
    final q = remainingConsumption(order, p);
    if (q == 0) continue;
    if (p['costKnown'] != true || p['costCents'] is! int) {
      missing++;
    } else {
      materials += roundProduct(q, p['costCents'] as int, 1000);
    }
  }
  for (final t in order.tasks) {
    final seconds = order.times.where((e) => e['taskId'] == t['id']).fold<int>(
      0,
      (sum, e) {
        final elapsed = (e['end'] == null ? now : DateTime.parse(e['end']))
            .difference(DateTime.parse(e['start']))
            .inSeconds;
        return sum + (elapsed < 0 ? 0 : elapsed);
      },
    );
    if (seconds == 0) continue;
    final known = t['internalCostKnown'] ?? settings['internalCostKnown'];
    final rate = t['internalCostCents'] ?? settings['internalHourlyCostCents'];
    if (known != true || rate is! int) {
      laborKnown = false;
    } else {
      labor += roundProduct(seconds, rate, 3600);
    }
  }
  return EstimatedMargin(
    includeRevenue ? calculateNote(order).netCents : 0,
    materials,
    labor,
    missing,
    laborKnown,
  );
}
