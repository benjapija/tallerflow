import 'engine.dart';
import 'management.dart';
import 'models.dart';

const inspectionStates = {
  'correct': 'Correcto',
  'follow_up': 'Necesita seguimiento',
  'attention': 'Requiere atención',
};

void applyInspection(WorkOrder order, Operation op, Actor actor) {
  final p = op.payload;
  if (op.baseRevision != order.revision) {
    throw const RuleException('La orden ha cambiado. Actualiza y revisa');
  }
  if (p.keys.any(
    (k) => !['id', 'expectedVersion', 'title', 'items', 'reason'].contains(k),
  )) {
    throw const RuleException('La inspección contiene campos no admitidos');
  }
  final id = requiredText(p['id'], 'Identificador de inspección', max: 100);
  final current = (order.data['inspections'] as List? ?? [])
      .cast<Map<String, dynamic>>();
  final old = current.where((i) => i['id'] == id).firstOrNull;
  if (boundedInt(p['expectedVersion'], 100000, 'Versión') !=
      (old?['version'] ?? 0)) {
    throw const RuleException(
      'La inspección ha cambiado. Revisa su versión actual',
    );
  }
  if (old == null && current.length >= 50) {
    throw const RuleException('La orden admite hasta 50 inspecciones');
  }
  final title = requiredText(p['title'], 'Nombre de inspección', max: 200);
  final reason = requiredText(p['reason'], 'Motivo de revisión', max: 2000);
  final raw = p['items'];
  if (raw is! List || raw.isEmpty || raw.length > 40) {
    throw const RuleException('Configura entre 1 y 40 comprobaciones');
  }
  final ids = <String>{};
  final items = <Map<String, dynamic>>[];
  for (final value in raw) {
    if (value is! Map ||
        value.keys.any(
          (k) =>
              !['id', 'label', 'status', 'observation', 'photoIds'].contains(k),
        )) {
      throw const RuleException('Comprobación incompatible');
    }
    final itemId = requiredText(
      value['id'],
      'Identificador de comprobación',
      max: 100,
    );
    if (!ids.add(itemId)) {
      throw const RuleException('Comprobaciones duplicadas');
    }
    final status = value['status'];
    final observation = value['observation'];
    final photos = value['photoIds'];
    if (!inspectionStates.containsKey(status) ||
        observation is! String ||
        observation.length > 2000) {
      throw const RuleException('Revisa el estado y la observación');
    }
    if (status != 'correct' && observation.trim().isEmpty) {
      throw const RuleException(
        'Describe los hallazgos que requieren atención o seguimiento',
      );
    }
    if (photos is! List ||
        photos.length > 10 ||
        photos.toSet().length != photos.length ||
        photos.any(
          (id) => !(order.data['photos'] as List? ?? []).any(
            (photo) => photo['id'] == id && photo['status'] == 'attached',
          ),
        )) {
      throw const RuleException(
        'Vincula fotografías confirmadas de esta orden',
      );
    }
    items.add({
      'id': itemId,
      'label': requiredText(value['label'], 'Comprobación', max: 200),
      'status': status,
      'observation': observation.trim(),
      'photoIds': List<String>.from(photos),
    });
  }
  final next = {
    'id': id,
    'version': (old?['version'] ?? 0) + 1,
    'title': title,
    'items': items,
    'reason': reason,
    'actorId': actor.id,
    'at': op.at.toUtc().toIso8601String(),
    'operationId': op.id,
  };
  order.data['inspectionHistory'] = [
    ...(order.data['inspectionHistory'] as List? ?? []),
    if (old != null) cloneMap(old),
  ];
  order.data['inspections'] = [
    for (final i in current)
      if (i['id'] != id) i,
    next,
  ];
  // Findings are technical evidence. They never create tasks, authorize work,
  // consume stock, add labour or modify the monetary document.
  order.data['quality'] = null;
}
