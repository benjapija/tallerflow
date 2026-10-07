import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../data/controller.dart';
import '../domain/maintenance.dart';
import '../domain/planning_time.dart';
import 'dialogs.dart';

String _dayInput(dynamic iso) {
  if (iso == null) return '';
  final p = iso.toString().split('-');
  return '${p[2]}/${p[1]}/${p[0]}';
}

String? _dayOutput(String input) {
  if (input.trim().isEmpty) return null;
  final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(input.trim());
  if (m == null) throw const FormatException('Fecha prevista: dd/mm/aaaa');
  return maintenanceDay('${m[3]}-${m[2]}-${m[1]}');
}

int? _number(String input) {
  if (input.trim().isEmpty) return null;
  final n = int.tryParse(input.trim());
  if (n == null) throw const FormatException('Indica un número entero');
  return n;
}

class MaintenancePanel extends StatelessWidget {
  final WorkshopController controller;
  final Map<String, dynamic> vehicle;
  const MaintenancePanel({
    super.key,
    required this.controller,
    required this.vehicle,
  });
  MaintenanceLedger get ledger =>
      MaintenanceLedger(controller.state.configuration['maintenance']);
  bool get edit =>
      controller.actor.isOffice &&
      controller.accessAllowed &&
      controller.pendingCommands.isEmpty &&
      controller.outbox.isEmpty;
  Future<void> save(
    BuildContext context,
    String action,
    Map<String, dynamic> p,
  ) async {
    try {
      await controller.maintenance(action, p);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> plan(BuildContext context, [Map<String, dynamic>? old]) async {
    final rev = ledger.revision;
    final p = await formDialog(
      context,
      old == null
          ? 'Programar mantenimiento'
          : 'Revisar previsión de mantenimiento',
      [
        FieldSpec('title', 'Mantenimiento', initial: old?['title'] ?? ''),
        FieldSpec(
          'source',
          'Fuente o criterio de seguimiento',
          initial: old?['source'] ?? '',
          multiline: true,
        ),
        FieldSpec(
          'zone',
          'Hora del taller',
          initial: old?['zone'] ?? 'Europe/Madrid',
          choices: const {
            'Europe/Madrid': 'Península y Baleares',
            'Atlantic/Canary': 'Canarias',
          },
        ),
        FieldSpec(
          'dueDate',
          'Fecha prevista (dd/mm/aaaa)',
          initial: _dayInput(old?['dueDate']),
          required: false,
        ),
        FieldSpec(
          'dueKm',
          'Kilometraje previsto',
          initial: old?['dueKm']?.toString() ?? '',
          required: false,
          numeric: true,
        ),
        FieldSpec(
          'intervalMonths',
          'Repetir cada (meses)',
          initial: old?['intervalMonths']?.toString() ?? '',
          required: false,
          numeric: true,
        ),
        FieldSpec(
          'intervalKm',
          'Repetir cada (km)',
          initial: old?['intervalKm']?.toString() ?? '',
          required: false,
          numeric: true,
        ),
        const FieldSpec('reason', 'Motivo de la previsión', multiline: true),
      ],
      (v) {
        final p = {
          'id': old?['id'] ?? const Uuid().v4(),
          'revision': rev,
          'vehicleId': vehicle['id'],
          'title': v['title'],
          'source': v['source'],
          'zone': v['zone'],
          'dueDate': _dayOutput(v['dueDate']!),
          'dueKm': _number(v['dueKm']!),
          'intervalMonths': _number(v['intervalMonths']!),
          'intervalKm': _number(v['intervalKm']!),
          'reason': v['reason'],
        };
        ledger.apply(
          'care_plan',
          p,
          controller.actor,
          controller.clock(),
          'preview',
          [vehicle],
          controller.state.orders,
        );
        return p;
      },
      help:
          'Registra el criterio que has comprobado. Puedes usar fecha, kilometraje o ambos; se revisa al alcanzar el primero. Deja los intervalos vacíos para una previsión única. Incluye solo información técnica.',
    );
    if (p != null && context.mounted) await save(context, 'care_plan', p);
  }

  Future<void> complete(BuildContext context, Map<String, dynamic> old) async {
    final rev = ledger.revision, zone = old['zone'] as String;
    final orders = controller.visibleOrders.where(
      (o) => (o.data['vehicleId'] ?? o.id) == vehicle['id'],
    );
    final p = await formDialog(
      context,
      'Registrar mantenimiento realizado',
      [
        FieldSpec(
          'performedAt',
          'Fecha y hora realizadas (dd/mm/aaaa hh:mm)',
          initial: PlanningTime.format(controller.clock(), zone),
        ),
        const FieldSpec(
          'fold',
          'Hora repetida al cambiar al horario de invierno',
          initial: '',
          choices: {
            '': 'No es una hora repetida',
            'first': 'Primera vez',
            'second': 'Segunda vez',
          },
        ),
        FieldSpec(
          'km',
          'Kilometraje comprobado',
          initial: vehicle['km'].toString(),
          numeric: true,
        ),
        FieldSpec(
          'orderId',
          'Orden de trabajo relacionada',
          initial: '',
          choices: {
            '': 'Sin orden: evidencia manual',
            for (final o in orders) o.id: o.number,
          },
        ),
        const FieldSpec(
          'evidence',
          'Comprobación de la intervención realizada',
          multiline: true,
        ),
        const FieldSpec('reason', 'Motivo del registro', multiline: true),
      ],
      (v) {
        final p = {
          'id': old['id'],
          'revision': rev,
          'performedAt': PlanningTime.parse(
            v['performedAt']!,
            zone,
            fold: v['fold']!,
          ).toIso8601String(),
          'km': _number(v['km']!),
          'orderId': v['orderId']!.isEmpty ? null : v['orderId'],
          'evidence': v['evidence'],
          'reason': v['reason'],
        };
        ledger.apply(
          'care_complete',
          p,
          controller.actor,
          controller.clock(),
          'preview',
          [vehicle],
          controller.state.orders,
        );
        return p;
      },
      help:
          'Confirma una intervención que se ha realizado. Las próximas fechas e intervalos partirán de esta fecha y kilometraje. Este registro conserva la evidencia y el destinatario original de cada documento.',
    );
    if (p != null && context.mounted) await save(context, 'care_complete', p);
  }

  Future<void> pause(BuildContext context, Map<String, dynamic> old) async {
    final rev = ledger.revision;
    final p = await formDialog(
      context,
      'Pausar seguimiento de mantenimiento',
      [const FieldSpec('reason', 'Motivo', multiline: true)],
      (v) => {'id': old['id'], 'revision': rev, 'reason': v['reason']},
      help:
          'Se conservan la previsión y las intervenciones anteriores. Para reanudar, crea un plan nuevo con el criterio actualizado.',
    );
    if (p != null && context.mounted) await save(context, 'care_pause', p);
  }

  @override
  Widget build(BuildContext context) {
    final plans = ledger.plans.where((p) => p['vehicleId'] == vehicle['id']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 28),
        const Text(
          'Mantenimiento',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        if (controller.actor.isOffice)
          TextButton.icon(
            onPressed: edit ? () => plan(context) : null,
            icon: const Icon(Icons.add),
            label: const Text('Programar mantenimiento'),
          ),
        for (final command in controller.pendingCommands.where(
          (c) =>
              c['action'].toString().startsWith('care_') &&
              (c['payload']['vehicleId'] == vehicle['id'] ||
                  plans.any((p) => p['id'] == c['payload']['id'])),
        ))
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Solicitud pendiente de sincronizar: ${command['action'] == 'care_complete' ? 'intervención realizada' : 'previsión de mantenimiento'}',
            ),
          ),
        if (plans.isEmpty) const Text('Sin previsiones registradas.'),
        for (final p in plans)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p['title'],
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    maintenanceStatus(
                      p,
                      DateTime.parse(
                        maintenanceLocalDay(controller.clock(), p['zone']),
                      ),
                      vehicle['km'] as int?,
                    ),
                  ),
                  if (p['dueDate'] != null)
                    Text('Fecha prevista: ${_dayInput(p['dueDate'])}'),
                  if (p['dueKm'] != null)
                    Text('Kilometraje previsto: ${p['dueKm']} km'),
                  Text('Criterio: ${p['source']}'),
                  if (p['intervalMonths'] != null)
                    Text('Intervalo: ${p['intervalMonths']} meses'),
                  if (p['intervalKm'] != null)
                    Text('Intervalo: ${p['intervalKm']} km'),
                  if (controller.actor.isOffice && p['status'] == 'active')
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: edit ? () => plan(context, p) : null,
                          child: const Text('Revisar previsión'),
                        ),
                        TextButton(
                          onPressed: edit ? () => complete(context, p) : null,
                          child: const Text('Registrar realizado'),
                        ),
                        TextButton(
                          onPressed: edit ? () => pause(context, p) : null,
                          child: const Text('Pausar'),
                        ),
                      ],
                    ),
                  for (final e in p['completions'])
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        '${_dayInput(e['performedDate'])} · ${e['km']} km\n${e['evidence']}',
                      ),
                    ),
                  if (controller.actor.isOffice &&
                      (p['events'] as List).isNotEmpty)
                    ExpansionTile(
                      title: const Text('Historial del seguimiento'),
                      tilePadding: EdgeInsets.zero,
                      children: [
                        for (final e in p['events'])
                          ListTile(
                            title: Text(e['reason']),
                            subtitle: Text(
                              PlanningTime.format(
                                DateTime.parse(e['at']),
                                p['zone'],
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
