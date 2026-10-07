import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../data/controller.dart';
import '../domain/models.dart';
import '../domain/planning.dart';
import '../domain/planning_time.dart';
import 'dialogs.dart';

class PlanningPanel extends StatefulWidget {
  final WorkshopController controller;
  final Future<void> Function(Future<void> Function()) run;
  const PlanningPanel({super.key, required this.controller, required this.run});
  @override
  State<PlanningPanel> createState() => _PlanningPanelState();
}

class _PlanningPanelState extends State<PlanningPanel> {
  String zone = 'Europe/Madrid', query = '';
  bool history = false;
  WorkshopController get c => widget.controller;
  PlanningLedger get ledger =>
      PlanningLedger(c.state.configuration['planning']);
  bool get edit =>
      c.actor.isOffice &&
      c.accessAllowed &&
      c.pendingCommands.isEmpty &&
      c.outbox.isEmpty;
  Future<void> resource([Map<String, dynamic>? r]) async {
    final revision = ledger.revision;
    final p = await formDialog(
      context,
      r == null ? 'Añadir elevador' : 'Configurar elevador',
      [
        FieldSpec('name', 'Nombre', initial: r?['name'] ?? ''),
        FieldSpec(
          'active',
          'Disponible',
          initial: r?['active'] == false ? 'no' : 'yes',
          choices: const {'yes': 'Disponible', 'no': 'Retirado'},
        ),
        const FieldSpec('reason', 'Motivo', multiline: true),
      ],
      (v) => {
        'id': r?['id'] ?? const Uuid().v4(),
        'revision': revision,
        'name': v['name'],
        'active': v['active'] == 'yes',
        'reason': v['reason'],
      },
    );
    if (p != null) await widget.run(() => c.planning('schedule_resource', p));
  }

  Future<void> booking({
    Map<String, dynamic>? previous,
    bool unavailable = false,
  }) async {
    final current = ledger;
    final p = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BookingDialog(
        ledger: current,
        actor: c.actor,
        members: c.state.members,
        orders: c.visibleOrders.toList(),
        previous: previous,
        zone: zone,
        now: c.clock(),
        unavailable: unavailable,
      ),
    );
    if (p != null) await widget.run(() => c.planning('schedule_booking', p));
  }

  Future<void> status(Map<String, dynamic> b, String value) async {
    final revision = ledger.revision;
    final p = await formDialog(
      context,
      value == 'done' ? 'Finalizar cita' : 'Cancelar reserva',
      [const FieldSpec('reason', 'Motivo y comprobación', multiline: true)],
      (v) => {
        'id': b['id'],
        'revision': revision,
        'status': value,
        'reason': v['reason'],
      },
      help:
          'Se conserva el horario original y su historial. Esta acción no factura ni autoriza reparaciones.',
    );
    if (p != null) await widget.run(() => c.planning('schedule_status', p));
  }

  @override
  Widget build(BuildContext context) {
    final l = ledger, all = l.bookings;
    final rows =
        all
            .where(
              (b) =>
                  (c.actor.isOffice ||
                      (b['assignees'] as List).contains(c.actor.id)) &&
                  (history || b['status'] == 'planned') &&
                  (query.isEmpty ||
                      '${b['title']} ${b['start']}'.toLowerCase().contains(
                        query.toLowerCase(),
                      )),
            )
            .toList()
          ..sort(
            (a, b) => DateTime.parse(
              a['start'],
            ).compareTo(DateTime.parse(b['start'])),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Agenda',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          c.actor.isOffice
              ? 'Reservas de operarios y elevadores. La confirmación depende de sincronizar con el taller.'
              : 'Tus citas e indisponibilidades asignadas por oficina.',
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: zone,
                decoration: const InputDecoration(
                  labelText: 'Mostrar horas de',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Europe/Madrid',
                    child: Text('Península y Baleares'),
                  ),
                  DropdownMenuItem(
                    value: 'Atlantic/Canary',
                    child: Text('Canarias'),
                  ),
                ],
                onChanged: (v) => setState(() => zone = v!),
              ),
            ),
            if (c.actor.isOffice)
              FilledButton.icon(
                onPressed: edit ? () => booking() : null,
                icon: const Icon(Icons.add),
                label: const Text('Reservar cita'),
              ),
            if (c.actor.isOffice)
              OutlinedButton(
                onPressed: edit ? () => booking(unavailable: true) : null,
                child: const Text('Indisponibilidad'),
              ),
            if (c.actor.role == Role.admin)
              OutlinedButton(
                onPressed: edit ? () => resource() : null,
                child: const Text('Añadir elevador'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          decoration: const InputDecoration(labelText: 'Buscar cita'),
          onChanged: (v) => setState(() => query = v),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Incluir reservas finalizadas y canceladas'),
          value: history,
          onChanged: (v) => setState(() => history = v!),
        ),
        for (final p in c.pendingCommands.where(
          (p) => (p['action'] as String).startsWith('schedule_'),
        ))
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Pendiente de confirmar · ${p['payload']['title'] ?? p['payload']['name'] ?? 'Cambio de agenda'}. No ocupa un horario confirmado.',
              ),
            ),
          ),
        if (c.syncError != null)
          Text(
            'Revisa la sincronización: ${c.syncError}',
            style: const TextStyle(color: Colors.red),
          ),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('No hay reservas en esta vista.'),
          ),
        for (final b in rows)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    b['title'],
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${PlanningTime.format(DateTime.parse(b['start']), zone)} → ${PlanningTime.format(DateTime.parse(b['end']), zone)}',
                  ),
                  Text(
                    '${b['kind'] == 'unavailable' ? 'Indisponibilidad' : 'Cita'} · ${b['status'] == 'planned'
                        ? 'Reservada'
                        : b['status'] == 'done'
                        ? 'Finalizada'
                        : 'Cancelada'}',
                  ),
                  Text(
                    'Operarios: ${(b['assignees'] as List).map((id) => c.state.members.where((m) => m.id == id).firstOrNull?.name ?? 'Cuenta retirada').join(', ')}',
                  ),
                  if (b['liftId'] != null)
                    Text(
                      'Elevador: ${l.resources.where((r) => r['id'] == b['liftId']).firstOrNull?['name'] ?? 'Retirado'}',
                    ),
                  if (b['orderId'] != null)
                    Text(
                      'Orden: ${c.state.orders[b['orderId']]?.number ?? 'No disponible para este perfil'}',
                    ),
                  if (b['status'] == 'planned' &&
                      DateTime.parse(b['end']).isBefore(c.clock()))
                    const Text(
                      'Horario vencido: oficina debe revisar el resultado.',
                      style: TextStyle(color: Colors.deepOrange),
                    ),
                  if (c.actor.isOffice && b['status'] == 'planned')
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: edit ? () => booking(previous: b) : null,
                          child: const Text('Reprogramar'),
                        ),
                        TextButton(
                          onPressed: edit ? () => status(b, 'done') : null,
                          child: const Text('Finalizar'),
                        ),
                        TextButton(
                          onPressed: edit ? () => status(b, 'cancelled') : null,
                          child: const Text('Cancelar'),
                        ),
                      ],
                    ),
                  if (c.actor.isOffice && (b['events'] as List).isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Historial de reserva'),
                      children: [
                        for (final e in b['events'])
                          ListTile(
                            title: Text(e['reason']),
                            subtitle: Text(
                              PlanningTime.format(
                                DateTime.parse(e['at']),
                                zone,
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        if (c.actor.role == Role.admin) ...[
          const SizedBox(height: 20),
          const Text(
            'Elevadores',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          for (final r in l.resources)
            ListTile(
              title: Text(r['name']),
              subtitle: Text(r['active'] == true ? 'Disponible' : 'Retirado'),
              trailing: TextButton(
                onPressed: edit ? () => resource(r) : null,
                child: const Text('Configurar'),
              ),
            ),
        ],
      ],
    );
  }
}

class _BookingDialog extends StatefulWidget {
  final PlanningLedger ledger;
  final Actor actor;
  final List<Actor> members;
  final List<WorkOrder> orders;
  final Map<String, dynamic>? previous;
  final String zone;
  final DateTime now;
  final bool unavailable;
  const _BookingDialog({
    required this.ledger,
    required this.actor,
    required this.members,
    required this.orders,
    required this.zone,
    required this.now,
    required this.unavailable,
    this.previous,
  });
  @override
  State<_BookingDialog> createState() => _BookingDialogState();
}

class _BookingDialogState extends State<_BookingDialog> {
  final form = GlobalKey<FormState>();
  late final title = TextEditingController(
    text: widget.previous?['title'] ?? '',
  );
  late final start = TextEditingController(
    text: PlanningTime.format(
      widget.previous == null
          ? widget.now.add(const Duration(days: 1))
          : DateTime.parse(widget.previous!['start']),
      widget.zone,
    ),
  );
  late final end = TextEditingController(
    text: PlanningTime.format(
      widget.previous == null
          ? widget.now.add(const Duration(days: 1, hours: 1))
          : DateTime.parse(widget.previous!['end']),
      widget.zone,
    ),
  );
  final reason = TextEditingController();
  late final selected = Set<String>.from(widget.previous?['assignees'] ?? []);
  late String lift = widget.previous?['liftId'] ?? '',
      order = widget.previous?['orderId'] ?? '',
      kind =
          widget.previous?['kind'] ??
          (widget.unavailable ? 'unavailable' : 'appointment');
  String fold = '', error = '';
  @override
  void dispose() {
    for (final c in [title, start, end, reason]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.previous == null
          ? (kind == 'unavailable'
                ? 'Reservar indisponibilidad'
                : 'Reservar cita')
          : 'Reprogramar reserva',
    ),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Hora de ${widget.zone == 'Europe/Madrid' ? 'Península y Baleares' : 'Canarias'}. Los cambios de horario se comprueban antes de reservar.',
              ),
              for (final f in [
                (title, 'Título de la reserva'),
                (start, 'Inicio (dd/mm/aaaa hh:mm)'),
                (end, 'Fin (dd/mm/aaaa hh:mm)'),
                (reason, 'Motivo y comprobación'),
              ])
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: TextFormField(
                    key: ValueKey(f.$2),
                    controller: f.$1,
                    decoration: InputDecoration(labelText: f.$2),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Completa este campo' : null,
                  ),
                ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: fold,
                decoration: const InputDecoration(
                  labelText: 'Si la hora se repite al cambiar de horario',
                ),
                items: const [
                  DropdownMenuItem(
                    value: '',
                    child: Text('Solicitar revisión'),
                  ),
                  DropdownMenuItem(
                    value: 'first',
                    child: Text('Primera aparición de la hora'),
                  ),
                  DropdownMenuItem(
                    value: 'second',
                    child: Text('Segunda aparición de la hora'),
                  ),
                ],
                onChanged: (v) => setState(() => fold = v!),
              ),
              const SizedBox(height: 16),
              const Text('Operarios'),
              for (final m in widget.members.where(
                (m) => m.active && m.role == Role.technician,
              ))
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(m.name),
                  value: selected.contains(m.id),
                  onChanged: (v) => setState(
                    () => v! ? selected.add(m.id) : selected.remove(m.id),
                  ),
                ),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue:
                    widget.ledger.resources.any(
                      (r) => r['id'] == lift && r['active'] == true,
                    )
                    ? lift
                    : '',
                decoration: const InputDecoration(labelText: 'Elevador'),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Sin elevador'),
                  ),
                  for (final r in widget.ledger.resources.where(
                    (r) => r['active'] == true,
                  ))
                    DropdownMenuItem(
                      value: r['id'] as String,
                      child: Text(r['name']),
                    ),
                ],
                onChanged: (v) => lift = v!,
              ),
              if (kind == 'appointment')
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: widget.orders.any((o) => o.id == order)
                        ? order
                        : '',
                    decoration: const InputDecoration(
                      labelText: 'Orden vinculada',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Sin orden'),
                      ),
                      for (final o in widget.orders)
                        DropdownMenuItem(
                          value: o.id,
                          child: Text('${o.number} · ${o.plate}'),
                        ),
                    ],
                    onChanged: (v) => order = v!,
                  ),
                ),
              if (error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(error, style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate()) return;
          try {
            final p = {
              'id': widget.previous?['id'] ?? const Uuid().v4(),
              'revision': widget.ledger.revision,
              'title': title.text,
              'start': PlanningTime.parse(
                start.text,
                widget.zone,
                fold: fold,
              ).toIso8601String(),
              'end': PlanningTime.parse(
                end.text,
                widget.zone,
                fold: fold,
              ).toIso8601String(),
              'kind': kind,
              'assignees': selected.toList(),
              'liftId': lift.isEmpty ? null : lift,
              'orderId': kind == 'appointment' && order.isNotEmpty
                  ? order
                  : null,
              'reason': reason.text,
            };
            widget.ledger.apply(
              'schedule_booking',
              p,
              widget.actor,
              widget.now,
              'preview',
              widget.members,
              widget.orders.map((o) => o.id).toSet(),
            );
            Navigator.pop(context, p);
          } catch (e) {
            setState(() => error = e.toString());
          }
        },
        child: const Text('Guardar reserva'),
      ),
    ],
  );
}
