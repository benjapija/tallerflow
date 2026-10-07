import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../data/controller.dart';
import '../domain/models.dart';
import '../domain/vehicles.dart';
import 'dialogs.dart';
import 'csv_panel.dart';
import 'photo_panel.dart';
import 'inspection_panel.dart';
import 'maintenance_panel.dart';

class VehicleHistory extends StatelessWidget {
  final WorkshopController controller;
  final void Function(String) openOrder;
  final String query;
  const VehicleHistory({
    super.key,
    required this.controller,
    required this.openOrder,
    this.query = '',
  });
  Future<void> change(
    BuildContext context,
    Map<String, dynamic> v,
    bool owner,
  ) async {
    final p = await formDialog(
      context,
      owner ? 'Cambiar propietario' : 'Actualizar matrícula y VIN',
      [
        if (owner) ...[
          const FieldSpec('name', 'Nuevo propietario'),
          const FieldSpec('phone', 'Teléfono', required: false),
        ] else ...[
          FieldSpec('plate', 'Matrícula', initial: v['plate']),
          FieldSpec('country', 'País de dos letras', initial: v['country']),
          FieldSpec('vin', 'VIN', initial: v['vin'] ?? '', required: false),
        ],
        const FieldSpec(
          'reason',
          'Motivo y comprobación realizada',
          multiline: true,
        ),
      ],
      (p) => {
        ...p,
        'vehicleId': v['id'],
        'revision': v['revision'],
        'change': owner ? 'owner' : 'registration',
        if (owner) 'ownerId': const Uuid().v4(),
      },
      help:
          'Las órdenes conservan sus datos de entrada y destinatarios originales. Este cambio no concede acceso a documentos anteriores.',
    );
    if (p == null) return;
    try {
      await controller.changeVehicle(p);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  String date(dynamic value) {
    final d = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    return d == null
        ? 'Fecha de entrada pendiente'
        : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final visible = c.visibleOrders
        .map((o) => o.data['vehicleId'] ?? o.id)
        .toSet();
    final profiles = vehicleProfiles(c.state).where(
      (v) =>
          (c.actor.isOffice || visible.contains(v['id'])) &&
          vehicleMatches(v, query, personal: c.actor.isOffice),
    );
    final history =
        (c.state.configuration['vehicleHistory'] as List?) ??
        c.state.orders.values
            .map(
              (o) => {
                ...technicalHistoryEntry(o),
                if (c.actor.isOffice) 'recipient': {'name': o.client},
                if (c.actor.isOffice) 'document': o.data['document'],
              },
            )
            .toList();
    String author(String id) =>
        c.state.members.where((m) => m.id == id).firstOrNull?.name ?? 'Usuario';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Vehículos e historial',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Una ficha por vehículo. Las reparaciones y sus documentos conservan el destinatario original.',
        ),
        const SizedBox(height: 24),
        if (c.actor.isOffice) ...[
          CsvPanel(controller: c),
          const SizedBox(height: 18),
        ],
        for (final v in profiles)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${v['vehicle']} · ${v['plate']}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${v['country']} · VIN ${v['vin'] == '' ? 'pendiente' : v['vin']} · ${v['km']} km registrados',
                    ),
                    Text('Identificador estable: ${v['id']}'),
                    if (c.actor.isOffice && v['owner'] is Map)
                      Text(
                        'Propietario actual: ${v['owner']['name']} · ${v['owner']['phone']}',
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Matrículas registradas: ${(v['identifiers'] as List).where((i) => i['kind'] == 'plate').map((i) => '${i['country']} ${i['value']}').join(' · ')}',
                    ),
                    if (c.actor.isOffice)
                      Wrap(
                        spacing: 12,
                        children: [
                          TextButton.icon(
                            onPressed: () => change(context, v, false),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Matrícula y VIN'),
                          ),
                          TextButton.icon(
                            onPressed: () => change(context, v, true),
                            icon: const Icon(Icons.person_outline),
                            label: const Text('Cambiar propietario'),
                          ),
                        ],
                      ),
                    MaintenancePanel(controller: c, vehicle: v),
                    const Divider(height: 24),
                    for (final entry in history.where(
                      (h) => h['vehicleId'] == v['id'],
                    ))
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(
                          '${entry['number']} · ${date(entry['receivedAt'])}',
                        ),
                        subtitle: Text(
                          '${entry['km']} km · ${entry['symptom']}',
                        ),
                        childrenPadding: const EdgeInsets.only(bottom: 16),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Matrícula de entrada: ${entry['plate']}'),
                          if (c.actor.isOffice && entry['recipient'] is Map)
                            Text(
                              'Destinatario de esta reparación: ${entry['recipient']['name']}',
                            ),
                          const SizedBox(height: 10),
                          for (final t in entry['tasks'] as List? ?? [])
                            Text(
                              '• ${t['title']} · ${t['cancelled'] == true
                                  ? 'cancelada'
                                  : t['done'] == true
                                  ? 'terminada'
                                  : 'en curso'}',
                            ),
                          for (final t in entry['times'] as List? ?? [])
                            Text(
                              '${author(t['actorId'])} · ${hours((t['end'] == null ? DateTime.now() : DateTime.parse(t['end'])).difference(DateTime.parse(t['start'])).inSeconds)} · tiempo real',
                            ),
                          for (final p in entry['parts'] as List? ?? [])
                            Text(
                              '${p['description']} · ${quantity(p['quantityMilli'])} ${p['unit']} · ${p['kind'] == 'return'
                                  ? 'devuelto'
                                  : p['kind'] == 'reserve'
                                  ? 'reservado'
                                  : p['kind'] == 'customer'
                                  ? 'aportado por cliente'
                                  : 'consumido'}',
                            ),
                          for (final n in entry['notes'] as List? ?? [])
                            Text(
                              '${n['author'] ?? 'Observación'} · ${n['text']}',
                            ),
                          HistoricalPhotoGallery(
                            controller: c,
                            orderId: entry['id'],
                          ),
                          if ((entry['inspections'] as List? ?? []).isNotEmpty)
                            InspectionPanel(
                              order: WorkOrder(
                                Map<String, dynamic>.from(entry),
                              ),
                              canEdit: false,
                              onSave: (_) async {},
                            ),
                          if (c.actor.isOffice && entry['document'] != null)
                            const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Text(
                                'Documento original conservado para su destinatario.',
                              ),
                            ),
                          if (c.visibleOrders.any((o) => o.id == entry['id']))
                            TextButton(
                              onPressed: () => openOrder(entry['id']),
                              child: const Text('Ver orden y registros'),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
