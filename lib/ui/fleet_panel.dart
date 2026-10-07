import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../data/controller.dart';
import '../domain/fleets.dart';
import '../domain/maintenance.dart';
import '../domain/vehicles.dart';
import 'dialogs.dart';

class FleetPanel extends StatefulWidget {
  final WorkshopController controller;
  final Future<void> Function(Future<void> Function()) run;
  final void Function(String) openOrder;
  const FleetPanel({
    super.key,
    required this.controller,
    required this.run,
    required this.openOrder,
  });
  @override
  State<FleetPanel> createState() => _FleetPanelState();
}

class _FleetPanelState extends State<FleetPanel> {
  bool history = false;
  String query = '';
  WorkshopController get c => widget.controller;
  FleetLedger get ledger => FleetLedger(c.state.configuration['fleets']);
  bool get edit =>
      c.actor.isOffice &&
      c.accessAllowed &&
      c.pendingCommands.isEmpty &&
      c.outbox.isEmpty;
  Future<void> group([Map<String, dynamic>? old]) async {
    final rev = ledger.revision;
    final p = await formDialog(
      context,
      old == null ? 'Crear flota' : 'Revisar flota',
      [
        FieldSpec('name', 'Nombre de la flota', initial: old?['name'] ?? ''),
        FieldSpec(
          'organization',
          'Empresa o responsable',
          initial: old?['organization'] ?? '',
        ),
        const FieldSpec('reason', 'Motivo y comprobación', multiline: true),
      ],
      (v) => {'id': old?['id'] ?? const Uuid().v4(), 'revision': rev, ...v},
      help:
          'Agrupa vehículos para seguir su trabajo. El responsable debe estar comprobado; esta agrupación no concede acceso a documentos ni autoriza presupuestos.',
    );
    if (p != null) await widget.run(() => c.fleet('fleet_group', p));
  }

  Future<void> attach(Map<String, dynamic> g) async {
    final rev = ledger.revision, vehicles = vehicleProfiles(c.state);
    final p = await formDialog(
      context,
      'Incorporar vehículo',
      [
        FieldSpec(
          'vehicleId',
          'Vehículo y propietario actual',
          initial: '',
          choices: {
            '': 'Selecciona el vehículo',
            for (final v in vehicles)
              v['id']:
                  '${v['plate']} · ${v['owner']?['name'] ?? 'Por comprobar'}',
          },
        ),
        const FieldSpec('reference', 'Referencia dentro de la flota'),
        const FieldSpec(
          'evidence',
          'Comprobación de pertenencia',
          multiline: true,
        ),
        const FieldSpec('reason', 'Motivo', multiline: true),
      ],
      (v) {
        final vehicle = vehicles
            .where((p) => p['id'] == v['vehicleId'])
            .firstOrNull;
        final p = {
          'id': g['id'],
          'revision': rev,
          'membershipId': const Uuid().v4(),
          ...v,
          'ownerId': vehicle?['ownerId'],
        };
        ledger.apply(
          'fleet_attach',
          p,
          c.actor,
          c.clock(),
          'preview',
          vehicles,
        );
        return p;
      },
      help:
          'Confirma que el vehículo pertenece a esta agrupación y quién es su propietario. Si cambia, se pedirá revisar el vínculo. Incluye solo los datos imprescindibles.',
    );
    if (p != null) await widget.run(() => c.fleet('fleet_attach', p));
  }

  Future<void> remove(Map<String, dynamic> g, Map<String, dynamic>? m) async {
    final rev = ledger.revision;
    final p = await formDialog(
      context,
      m == null ? 'Archivar flota' : 'Retirar vehículo de la flota',
      [const FieldSpec('reason', 'Motivo', multiline: true)],
      (v) => {
        'id': g['id'],
        'revision': rev,
        ...v,
        if (m != null) 'membershipId': m['id'],
      },
      help:
          'Se conserva el historial. Para archivar una flota, retira antes sus vínculos activos.',
    );
    if (p != null) {
      await widget.run(
        () => c.fleet(m == null ? 'fleet_archive' : 'fleet_detach', p),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!c.actor.isOffice) return const Text('Se requiere permiso de oficina');
    final vehicles = vehicleProfiles(c.state),
        care = MaintenanceLedger(c.state.configuration['maintenance']).plans;
    final groups = ledger.groups.where(
      (g) =>
          (history || g['status'] == 'active') &&
          '${g['name']} ${g['organization']}'.toLowerCase().contains(
            query.toLowerCase(),
          ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Flotas',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Seguimiento de vehículos, reparaciones y mantenimiento. Cada incorporación conserva su comprobación.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: edit ? () => group() : null,
              icon: const Icon(Icons.add),
              label: const Text('Crear flota'),
            ),
            SizedBox(
              width: 280,
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Buscar flota o responsable',
                ),
                onChanged: (v) => setState(() => query = v),
              ),
            ),
            FilterChip(
              label: const Text('Ver historial'),
              selected: history,
              onSelected: (v) => setState(() => history = v),
            ),
          ],
        ),
        for (final p in c.pendingCommands.where(
          (x) => x['action'].toString().startsWith('fleet_'),
        ))
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Solicitud de flota pendiente de sincronizar: ${p['payload']['reason']}',
            ),
          ),
        if (groups.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('No hay flotas en esta vista.'),
          ),
        for (final g in groups)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    g['name'],
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${g['organization']} · ${g['status'] == 'active' ? 'Activa' : 'Archivada'}',
                  ),
                  if (g['status'] == 'active')
                    Wrap(
                      children: [
                        TextButton(
                          onPressed: edit ? () => group(g) : null,
                          child: const Text('Revisar datos'),
                        ),
                        TextButton(
                          onPressed: edit ? () => attach(g) : null,
                          child: const Text('Incorporar vehículo'),
                        ),
                        TextButton(
                          onPressed: edit ? () => remove(g, null) : null,
                          child: const Text('Archivar'),
                        ),
                      ],
                    ),
                  for (final m in g['memberships'])
                    if (history || m['status'] == 'active')
                      Builder(
                        builder: (context) {
                          final v = vehicles
                                  .where((v) => v['id'] == m['vehicleId'])
                                  .firstOrNull,
                              effective = fleetMembershipCurrent(
                                m,
                                vehicles
                                    .where((v) => v['id'] == m['vehicleId'])
                                    .firstOrNull,
                              );
                          final orders = c.visibleOrders.where(
                            (o) =>
                                effective &&
                                (o.data['vehicleId'] ?? o.id) ==
                                    m['vehicleId'] &&
                                (o.data['ownerId'] ?? o.id) == m['ownerId'],
                          );
                          final plans = care.where(
                            (p) =>
                                effective &&
                                p['vehicleId'] == m['vehicleId'] &&
                                p['status'] == 'active',
                          );
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${m['reference']} · ${v?['plate'] ?? 'Vehículo por comprobar'}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  m['status'] == 'removed'
                                      ? 'Vínculo retirado'
                                      : effective
                                      ? 'Vínculo confirmado'
                                      : 'Revisar vínculo: propietario cambiado',
                                ),
                                Text(
                                  'Propietario al incorporar: ${m['ownerSnapshot']['name']}',
                                ),
                                Text('Comprobación: ${m['evidence']}'),
                                if (m['status'] == 'active')
                                  TextButton(
                                    onPressed: edit ? () => remove(g, m) : null,
                                    child: const Text('Retirar vínculo'),
                                  ),
                                if (effective)
                                  Text(
                                    '${orders.where((o) => o.data['document'] == null).length} órdenes sin nota emitida · ${plans.length} previsiones activas',
                                  ),
                                for (final p in plans)
                                  Text(
                                    '${p['title']}: ${maintenanceStatus(p, DateTime.parse(maintenanceLocalDay(c.clock(), p['zone'])), v?['km'])}',
                                  ),
                                for (final o in orders)
                                  TextButton(
                                    onPressed: () => widget.openOrder(o.id),
                                    child: Text('${o.number} · ${o.vehicle}'),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                  ExpansionTile(
                    title: const Text('Historial de la flota'),
                    tilePadding: EdgeInsets.zero,
                    children: [
                      for (final e in g['events'])
                        ListTile(
                          title: Text(e['reason']),
                          subtitle: Text(e['at']),
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
