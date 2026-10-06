import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../data/controller.dart';
import '../domain/models.dart';
import 'dialogs.dart';

class TaskManagement extends StatelessWidget {
  final WorkshopController controller;
  final WorkOrder order;
  final Future<void> Function(String, String, Map<String, dynamic>) perform;
  const TaskManagement({
    super.key,
    required this.controller,
    required this.order,
    required this.perform,
  });
  Future<void> edit(BuildContext context, Map<String, dynamic>? t) async {
    final chosen = <String>{...(t?['assignees'] as List? ?? []).cast<String>()};
    final members = controller.state.members.where((m) => m.active).toList();
    final assignment = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Asignar operarios'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final m in members)
                    CheckboxListTile(
                      title: Text(m.name),
                      value: chosen.contains(m.id),
                      onChanged: (v) => set(
                        () =>
                            v == true ? chosen.add(m.id) : chosen.remove(m.id),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: chosen.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, chosen.toList()),
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
    if (assignment == null || !context.mounted) return;
    final p = await formDialog(
      context,
      t == null ? 'Añadir tarea' : 'Editar tarea',
      [
        FieldSpec(
          'title',
          'Descripción del trabajo',
          initial: t?['title'] ?? '',
        ),
        FieldSpec(
          'estimate',
          'Minutos estimados',
          initial: '${t?['estimateMinutes'] ?? 30}',
          numeric: true,
        ),
        const FieldSpec('reason', 'Motivo del cambio', multiline: true),
      ],
      (v) => {
        'title': v['title'],
        'estimateMinutes': positiveInteger(v['estimate']!),
        'assignees': assignment,
        'reason': v['reason'],
      },
      help:
          'Cambiar la descripción requiere una nueva autorización para esta tarea. Los registros de tiempo y los consumos se conservan.',
    );
    if (p != null) {
      await perform(
        order.id,
        t == null ? 'task_add' : 'task_edit',
        t == null
            ? {
                'task': {...p, 'id': const Uuid().v4()},
                'reason': p['reason'],
              }
            : {...p, 'taskId': t['id']},
      );
    }
  }

  Future<void> plan(BuildContext context) async {
    final p = await formDialog(context, 'Organizar la orden', [
      FieldSpec(
        'priority',
        'Prioridad',
        initial: order.data['priority'] ?? 'Normal',
        choices: const {
          'Normal': 'Normal',
          'Alta': 'Alta',
          'Urgente': 'Urgente',
        },
      ),
      FieldSpec(
        'due',
        'Fecha prevista',
        initial: order.data['due'] ?? 'Por confirmar',
      ),
      FieldSpec(
        'location',
        'Ubicación del vehículo',
        initial: order.data['location'] ?? 'Recepción',
      ),
      FieldSpec(
        'keys',
        'Ubicación de las llaves',
        initial: order.data['keys'] ?? 'Recepción',
      ),
      const FieldSpec('reason', 'Motivo de la actualización', multiline: true),
    ], (v) => v);
    if (p != null) await perform(order.id, 'order_plan', p);
  }

  Future<void> action(
    BuildContext context,
    Map<String, dynamic> t,
    String kind,
  ) async {
    if (kind == 'task_block') {
      final members = controller.state.members.where((m) => m.active).toList();
      final p = await formDialog(
        context,
        'Bloquear tarea',
        [
          const FieldSpec('reason', 'Motivo del bloqueo', multiline: true),
          const FieldSpec(
            'nextAction',
            'Acción necesaria para continuar',
            multiline: true,
          ),
          FieldSpec(
            'ownerId',
            'Responsable de resolverlo',
            initial: controller.actor.id,
            choices: {for (final m in members) m.id: m.name},
          ),
        ],
        (v) => {...v, 'taskId': t['id']},
        help: 'Primero deben pausarse los cronómetros de esta tarea.',
      );
      if (p != null) await perform(order.id, kind, p);
      return;
    }
    final reason = await textDialog(
      context,
      kind == 'task_cancel'
          ? 'Cancelar tarea'
          : kind == 'task_reopen'
          ? 'Reabrir tarea'
          : 'Resolver bloqueo',
      'Motivo',
      multiline: true,
    );
    if (reason != null) {
      await perform(order.id, kind, {'taskId': t['id'], 'reason': reason});
    }
  }

  Future<void> template(BuildContext context) async {
    final list = controller.state.templates
        .where((t) => t['active'] != false)
        .toList();
    if (list.isEmpty) return;
    final p = await formDialog(
      context,
      'Aplicar plantilla',
      [
        FieldSpec(
          'template',
          'Plantilla',
          initial: list.first['id'],
          choices: {
            for (final t in list) t['id']: '${t['name']} · v${t['version']}',
          },
        ),
        FieldSpec(
          'assignee',
          'Operario inicial',
          initial: controller.state.members.firstWhere((m) => m.active).id,
          choices: {
            for (final m in controller.state.members.where((m) => m.active))
              m.id: m.name,
          },
        ),
        const FieldSpec(
          'compatibility',
          'Referencias, vehículo y motor comprobados',
          initial: 'no',
          choices: {
            'no': 'Pendiente de comprobar',
            'yes': 'Compatibilidad comprobada por el taller',
          },
        ),
        const FieldSpec('reason', 'Motivo de aplicación', multiline: true),
      ],
      (v) {
        final t = list.firstWhere((t) => t['id'] == v['template']);
        return {
          'templateId': t['id'],
          'templateVersion': t['version'],
          'taskIds': [for (final _ in t['tasks']) const Uuid().v4()],
          'assignees': [v['assignee']],
          'compatibilityChecked': v['compatibility'] == 'yes',
          'reason': v['reason'],
        };
      },
      help: list
          .map(
            (t) =>
                '${t['name']}: ${t['vehicleRule'] ?? ''} ${t['engineRule'] ?? ''}\n${(t['tasks'] as List).map((v) => v['title']).join(' · ')}',
          )
          .join('\n\n'),
    );
    if (p != null) await perform(order.id, 'template_apply', p);
  }

  @override
  Widget build(BuildContext context) {
    if (order.issued) return const SizedBox.shrink();
    final office = controller.actor.isOffice;
    return Card(
      child: ExpansionTile(
        title: const Text('Organización del trabajo'),
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                if (office)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => edit(context, null),
                        child: const Text('Añadir tarea'),
                      ),
                      OutlinedButton(
                        onPressed: () => plan(context),
                        child: const Text('Prioridad y ubicación'),
                      ),
                      if (controller.state.templates.any(
                        (t) => t['active'] != false,
                      ))
                        OutlinedButton(
                          onPressed: () => template(context),
                          child: const Text('Aplicar plantilla'),
                        ),
                      if (order.data['block'] != null)
                        OutlinedButton(
                          onPressed: () async {
                            final reason = await textDialog(
                              context,
                              'Resolver bloqueo de la orden',
                              'Motivo',
                              multiline: true,
                            );
                            if (reason != null) {
                              await perform(order.id, 'unblock', {
                                'reason': reason,
                              });
                            }
                          },
                          child: const Text('Resolver bloqueo de la orden'),
                        ),
                    ],
                  ),
                for (final t in order.tasks.where(
                  (t) =>
                      office ||
                      (t['assignees'] as List).contains(controller.actor.id),
                ))
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t['title'],
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Asignación: ${(t['assignees'] as List).map((id) => controller.state.members.where((m) => m.id == id).firstOrNull?.name ?? 'Cuenta histórica').join(', ')}',
                        ),
                        if (t['cancelled'] == true)
                          Text('Cancelada: ${t['cancellationReason']}'),
                        if (t['block'] != null)
                          Text(
                            'Bloqueo: ${t['block']['reason']}\nSiguiente acción: ${t['block']['nextAction']}',
                          ),
                        Wrap(
                          spacing: 4,
                          children: [
                            if (office && t['cancelled'] != true)
                              TextButton(
                                onPressed: () => edit(context, t),
                                child: const Text('Editar y asignar'),
                              ),
                            if (t['cancelled'] != true && t['done'] != true)
                              TextButton(
                                onPressed: () => action(
                                  context,
                                  t,
                                  t['block'] == null
                                      ? 'task_block'
                                      : 'task_unblock',
                                ),
                                child: Text(
                                  t['block'] == null
                                      ? 'Bloquear'
                                      : 'Resolver bloqueo',
                                ),
                              ),
                            if (office &&
                                t['done'] == true &&
                                t['cancelled'] != true)
                              TextButton(
                                onPressed: () =>
                                    action(context, t, 'task_reopen'),
                                child: const Text('Reabrir'),
                              ),
                            if (office &&
                                t['cancelled'] != true &&
                                t['done'] != true)
                              TextButton(
                                onPressed: () =>
                                    action(context, t, 'task_cancel'),
                                child: const Text('Cancelar tarea'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
