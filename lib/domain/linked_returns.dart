import 'engine.dart';
import 'management.dart';
import 'models.dart';

const returnClassifications = {
  'warranty': 'Garantía',
  'recurrence': 'Reincidencia',
  'different': 'Avería diferente',
};

Map<String, dynamic> classifyReturn(
  Map<String, dynamic> payload,
  Actor actor,
  DateTime at,
) {
  if (!actor.active || !actor.isOffice) {
    throw const RuleException('Se requiere oficina activa para clasificar');
  }
  if (payload.keys.any(
    (k) => !['sourceOrderId', 'classification', 'reason'].contains(k),
  )) {
    throw const RuleException('Campo de clasificación no permitido');
  }
  if (!returnClassifications.containsKey(payload['classification'])) {
    throw const RuleException('Clasifica el regreso del vehículo');
  }
  return {
    'sourceOrderId': requiredText(
      payload['sourceOrderId'],
      'Orden original',
      max: 100,
    ),
    'classification': payload['classification'],
    'reason': requiredText(
      payload['reason'],
      'Motivo de la clasificación',
      max: 2000,
    ),
    'actorId': actor.id,
    'at': at.toUtc().toIso8601String(),
  };
}

void attachReturn(
  WorkshopState state,
  WorkOrder newOrder,
  Map<String, dynamic> payload,
  Actor actor,
  DateTime at,
) {
  final link = classifyReturn(payload, actor, at);
  final original = state.orders[link['sourceOrderId']];
  if (original == null ||
      original.id == newOrder.id ||
      original.vehicleId != newOrder.vehicleId) {
    throw const RuleException('Vincula una orden anterior del mismo vehículo');
  }
  if (!original.issued &&
      ![
        OrderStatus.finished,
        OrderStatus.verified,
        OrderStatus.delivered,
      ].contains(original.status)) {
    throw const RuleException('La reparación original aún está en curso');
  }
  newOrder.data['returnHistory'] = [link];
}

void reclassifyReturn(WorkOrder order, Operation op, Actor actor) {
  if (op.baseRevision != order.revision) {
    throw const RuleException('La clasificación cambió. Actualiza y revisa');
  }
  final history = order.data['returnHistory'];
  if (history is! List || history.isEmpty) {
    throw const RuleException(
      'Esta recepción no está vinculada a otra reparación',
    );
  }
  final link = classifyReturn(op.payload, actor, op.at);
  if (link['sourceOrderId'] != history.first['sourceOrderId']) {
    throw const RuleException('La referencia original se conserva');
  }
  history.add(link);
}
