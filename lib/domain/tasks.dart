import 'engine.dart';
import 'models.dart';
import 'management.dart';

const taskChanges = [
  'task_add',
  'task_edit',
  'task_cancel',
  'task_reopen',
  'task_block',
  'task_unblock',
  'order_plan',
  'unblock',
  'template_apply',
];
List<String> activeAssignees(WorkshopState state, dynamic value) {
  if (value is! List ||
      value.isEmpty ||
      value.length > 20 ||
      value.toSet().length != value.length ||
      value.any((id) => !state.members.any((m) => m.id == id && m.active))) {
    throw const RuleException('Selecciona operarios activos del taller');
  }
  return List<String>.from(value);
}

Map<String, dynamic> newTask(
  WorkshopState state,
  Map<String, dynamic> source,
) => {
  'id': requiredText(source['id'], 'Tarea interna', max: 100).toLowerCase(),
  'title': requiredText(source['title'], 'Descripción', max: 300),
  'estimateMinutes': boundedInt(
    source['estimateMinutes'],
    14400,
    'Minutos estimados',
    min: 1,
  ),
  'assignees': activeAssignees(state, source['assignees']),
  'authorized': false,
  'authorization': null,
  'approvedCents': 0,
  'done': false,
  'billableMinutes': 0,
  'rateCents': state.settings['hourlyRateCents'] ?? 4800,
  'taxBps': state.settings['taxBps'] ?? 2100,
  'scopeVersion': 1,
  'block': null,
};
void applyTaskChange(
  WorkshopState state,
  WorkOrder order,
  Operation op,
  Actor actor,
) {
  final p = op.payload;
  if (op.baseRevision != order.revision) {
    throw const RuleException('La orden ha cambiado. Actualiza y revisa');
  }
  requiredText(p['reason'], 'Motivo');
  if (!actor.isOffice && !['task_block', 'task_unblock'].contains(op.kind)) {
    throw const RuleException('Se requiere permiso de oficina');
  }
  Map<String, dynamic> task() {
    final t = order.tasks.where((t) => t['id'] == p['taskId']).firstOrNull;
    if (t == null) throw const RuleException('Tarea no encontrada');
    if (!actor.isOffice && !(t['assignees'] as List).contains(actor.id)) {
      throw const RuleException('Tarea no asignada');
    }
    return t;
  }

  List<String> assignees(dynamic value) {
    return activeAssignees(state, value);
  }

  void stopped(String id) {
    if (order.times.any((t) => t['taskId'] == id && t['end'] == null)) {
      throw const RuleException('Pausa todos los cronómetros de esta tarea');
    }
  }

  Map<String, dynamic> createTask(Map<String, dynamic> source) =>
      newTask(state, source);
  switch (op.kind) {
    case 'task_add':
      if (order.tasks.any((t) => t['id'] == p['task']['id'])) {
        throw const RuleException('Tarea duplicada');
      }
      order.tasks.add(createTask(Map<String, dynamic>.from(p['task'])));
    case 'task_edit':
      final t = task();
      stopped(t['id']);
      if (t['cancelled'] == true) throw const RuleException('Tarea cancelada');
      final title = requiredText(p['title'], 'Descripción', max: 300);
      if (title != t['title']) {
        t['previousAuthorizations'] = [
          ...(t['previousAuthorizations'] as List? ?? []),
          if (t['authorization'] != null) t['authorization'],
        ];
        t['authorized'] = false;
        t['approvedCents'] = 0;
        t['authorization'] = null;
        t['scopeVersion'] = (t['scopeVersion'] as int? ?? 1) + 1;
      }
      t['title'] = title;
      t['assignees'] = assignees(p['assignees']);
      t['estimateMinutes'] = boundedInt(
        p['estimateMinutes'],
        14400,
        'Minutos estimados',
        min: 1,
      );
    case 'task_cancel':
      final t = task();
      stopped(t['id']);
      if (order.times.any((v) => v['taskId'] == t['id']) ||
          order.parts.any((v) => v['taskId'] == t['id']) ||
          t['billableMinutes'] != 0) {
        throw const RuleException(
          'Conserva la tarea con trabajo registrado; revisa sus cargos',
        );
      }
      t['previousAuthorizations'] = [
        ...(t['previousAuthorizations'] as List? ?? []),
        if (t['authorization'] != null) t['authorization'],
      ];
      t.addAll({
        'cancelled': true,
        'authorized': false,
        'authorization': null,
        'approvedCents': 0,
        'block': null,
        'cancellationReason': p['reason'],
      });
    case 'task_reopen':
      final t = task();
      stopped(t['id']);
      if (t['cancelled'] == true || t['done'] != true) {
        throw const RuleException('Selecciona una tarea terminada');
      }
      t['done'] = false;
      order.data['status'] = 'repair';
    case 'task_block':
      final t = task();
      stopped(t['id']);
      if (t['done'] == true || t['cancelled'] == true) {
        throw const RuleException('La tarea no admite un bloqueo');
      }
      requiredText(p['nextAction'], 'Siguiente acción');
      if (!state.members.any((m) => m.id == p['ownerId'] && m.active)) {
        throw const RuleException('Responsable no disponible');
      }
      t['block'] = {
        'reason': p['reason'],
        'nextAction': p['nextAction'],
        'ownerId': p['ownerId'],
        'at': op.at.toUtc().toIso8601String(),
        'actorId': actor.id,
      };
    case 'task_unblock':
      final t = task();
      if (t['block'] == null) {
        throw const RuleException('La tarea no está bloqueada');
      }
      t['block'] = null;
    case 'unblock':
      if (order.data['block'] == null) {
        throw const RuleException('La orden no está bloqueada');
      }
      order.data['block'] = null;
      order.data['nextAction'] = null;
      order.data['status'] = 'pending';
    case 'order_plan':
      if (!['Normal', 'Alta', 'Urgente'].contains(p['priority'])) {
        throw const RuleException('Prioridad inválida');
      }
      for (final k in ['priority', 'due', 'location', 'keys']) {
        order.data[k] = requiredText(p[k], k, max: 300);
      }
    case 'template_apply':
      if (p['compatibilityChecked'] != true) {
        throw const RuleException(
          'Confirma la compatibilidad con este vehículo',
        );
      }
      final template = state.templates
          .where((t) => t['id'] == p['templateId'] && t['active'] != false)
          .firstOrNull;
      if (template == null || template['version'] != p['templateVersion']) {
        throw const RuleException('Plantilla inexistente o modificada');
      }
      if (order.tasks.any((t) => t['templateApplicationId'] == op.id)) return;
      if (p['taskIds'] is! List ||
          (p['taskIds'] as List).length != (template['tasks'] as List).length) {
        throw const RuleException('Tareas de plantilla inválidas');
      }
      final selected = assignees(p['assignees']);
      for (var i = 0; i < (template['tasks'] as List).length; i++) {
        final source = Map<String, dynamic>.from(template['tasks'][i]);
        final added = createTask({
          ...source,
          'id': p['taskIds'][i],
          'assignees': selected,
        });
        if (order.tasks.any((t) => t['id'] == added['id'])) {
          throw const RuleException('Tarea duplicada');
        }
        added.addAll({
          'templateId': template['id'],
          'templateVersion': template['version'],
          'templateApplicationId': op.id,
          'compatibilityChecked': true,
          'suggestedReferences': source['references'] ?? [],
        });
        order.tasks.add(added);
      }
  }
}
