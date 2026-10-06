import 'engine.dart';
import 'management.dart';
import 'models.dart';

bool vehicleMatches(
  Map<String, dynamic> profile,
  String query, {
  bool personal = false,
}) {
  final values = [
    profile['vehicle'],
    profile['engine'],
    profile['vin'],
    profile['plate'],
    ...(profile['identifiers'] as List? ?? []).map((i) => i['value']),
    if (personal) ...[
      (profile['owner'] as Map?)?['name'],
      (profile['owner'] as Map?)?['phone'],
    ],
  ].whereType<String>();
  final q = query.trim().toLowerCase();
  return values.any(
    (v) =>
        v.toLowerCase().contains(q) ||
        normalizePlate(v).contains(normalizePlate(q)),
  );
}

List<Map<String, dynamic>> vehicleProfiles(WorkshopState state) {
  final saved = (state.configuration['vehicleProfiles'] as List? ?? [])
      .map((p) => cloneMap(Map<String, dynamic>.from(p)))
      .toList();
  for (final o in state.orders.values) {
    final id = o.data['vehicleId'] ?? o.id;
    if (saved.any((p) => p['id'] == id)) continue;
    saved.add({
      'id': id,
      'revision': 0,
      'plate': o.plate,
      'country': o.data['country'],
      'vin': o.data['vin'] ?? '',
      'vehicle': o.vehicle,
      'engine': o.data['engine'] ?? '',
      'km': o.data['km'] ?? 0,
      'ownerId': o.data['ownerId'] ?? o.id,
      'owner': {'name': o.client, 'phone': o.data['phone'] ?? ''},
      'identifiers': [
        {'kind': 'plate', 'country': o.data['country'], 'value': o.plate},
        if ((o.data['vin'] ?? '').toString().isNotEmpty)
          {'kind': 'vin', 'country': '', 'value': o.data['vin']},
      ],
    });
  }
  return saved;
}

Map<String, dynamic> attachReceptionVehicle(
  WorkshopState state,
  Map<String, dynamic> data,
  String orderId,
) {
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(data['country']) ||
      (data['vin'] as String).length > 50) {
    throw const RuleException('Revisa el país y el VIN');
  }
  final profiles = vehicleProfiles(state);
  final matches = profiles
      .where(
        (v) => (v['identifiers'] as List).any(
          (i) =>
              (i['kind'] == 'plate' &&
                  i['country'] == data['country'] &&
                  normalizePlate(i['value']) == data['plate']) ||
              (i['kind'] == 'vin' &&
                  data['vin'] != '' &&
                  i['value'] == data['vin']),
        ),
      )
      .toList();
  if (matches.length > 1) {
    throw const RuleException(
      'Matrícula y VIN identifican vehículos distintos',
    );
  }
  Map<String, dynamic> profile;
  if (matches.isEmpty) {
    profile = {
      'id': orderId,
      'revision': 0,
      'plate': data['plate'],
      'country': data['country'],
      'vin': data['vin'],
      'vehicle': data['vehicle'],
      'engine': data['engine'],
      'km': data['km'],
      'ownerId': orderId,
      'owner': {'name': data['client'], 'phone': data['phone'] ?? ''},
      'identifiers': [
        {'kind': 'plate', 'country': data['country'], 'value': data['plate']},
        if (data['vin'] != '')
          {'kind': 'vin', 'country': '', 'value': data['vin']},
      ],
    };
    profiles.add(profile);
  } else {
    profile = matches.single;
    if (!(profile['identifiers'] as List).any(
      (i) =>
          i['kind'] == 'plate' &&
          i['country'] == data['country'] &&
          normalizePlate(i['value']) == data['plate'],
    )) {
      throw const RuleException('Confirma el cambio de matrícula en la ficha');
    }
    if (data['vin'] != '' &&
        !(profile['identifiers'] as List).any(
          (i) => i['kind'] == 'vin' && i['value'] == data['vin'],
        )) {
      throw const RuleException('VIN distinto: revisa la ficha del vehículo');
    }
    final owner = profile['owner'] as Map?;
    if (owner == null ||
        owner['name'].toString().trim().toLowerCase() !=
            data['client'].toString().trim().toLowerCase() ||
        (owner['phone'] ?? '') != (data['phone'] ?? '')) {
      throw const RuleException(
        'Confirma el propietario en la ficha antes de recibir',
      );
    }
    if ((data['km'] as int) > (profile['km'] as int)) {
      profile['km'] = data['km'];
    }
    profile['revision'] = (profile['revision'] as int) + 1;
  }
  state.configuration['vehicleProfiles'] = profiles;
  return {
    ...data,
    'vehicleId': profile['id'],
    'ownerId': profile['ownerId'],
    'plate': profile['plate'],
    'country': profile['country'],
    'vin': profile['vin'],
  };
}

void applyVehicleChange(
  WorkshopState state,
  String id,
  Map<String, dynamic> p,
  Actor actor,
  DateTime at,
) {
  if (!actor.active || !actor.isOffice) {
    throw const RuleException('Se requiere permiso de oficina');
  }
  if (p.keys.any(
    (k) => ![
      'vehicleId',
      'revision',
      'change',
      'reason',
      'plate',
      'country',
      'vin',
      'ownerId',
      'name',
      'phone',
    ].contains(k),
  )) {
    throw const RuleException('Campos de vehículo inesperados');
  }
  if (state.applied.contains(id)) return;
  final profiles = vehicleProfiles(state);
  final v = profiles.where((v) => v['id'] == p['vehicleId']).firstOrNull;
  if (v == null || v['revision'] != p['revision']) {
    throw const RuleException('La ficha ha cambiado. Actualiza y revisa');
  }
  final reason = requiredText(p['reason'], 'Motivo');
  final before = cloneMap(v);
  if (p['change'] == 'registration') {
    final plate = normalizePlate(
      requiredText(p['plate'], 'Matrícula', max: 30),
    );
    final country = requiredText(p['country'], 'País', max: 2).toUpperCase();
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(country)) {
      throw const RuleException('Indica un país de dos letras');
    }
    final vin = (p['vin'] as String? ?? '').trim().toUpperCase();
    if (vin.length > 50) throw const RuleException('VIN demasiado largo');
    final added = [
      {'kind': 'plate', 'country': country, 'value': plate},
      if (vin != '') {'kind': 'vin', 'country': '', 'value': vin},
    ];
    if (profiles
        .where((o) => o['id'] != v['id'])
        .any(
          (o) => (o['identifiers'] as List).any(
            (i) => added.any(
              (a) =>
                  i['kind'] == a['kind'] &&
                  i['country'] == a['country'] &&
                  i['value'] == a['value'],
            ),
          ),
        )) {
      throw const RuleException('Identificador registrado en otro vehículo');
    }
    for (final a in added) {
      if (!(v['identifiers'] as List).any(
        (i) =>
            i['kind'] == a['kind'] &&
            i['country'] == a['country'] &&
            i['value'] == a['value'],
      )) {
        (v['identifiers'] as List).add(a);
      }
    }
    v.addAll({
      'plate': plate,
      'country': country,
      'vin': vin == '' ? v['vin'] : vin,
    });
  } else if (p['change'] == 'owner') {
    final ownerId = requiredText(
      p['ownerId'],
      'Destinatario interno',
      max: 100,
    );
    if (profiles.any((v) => v['ownerId'] == ownerId) ||
        state.orders.values.any(
          (o) => (o.data['ownerId'] ?? o.id) == ownerId,
        ) ||
        state.audit.any(
          (a) =>
              a['kind'] == 'vehicle_change' &&
              (a['after'] as Map?)?['ownerId'] == ownerId,
        )) {
      throw const RuleException(
        'El nuevo destinatario requiere una identidad nueva',
      );
    }
    final phone = (p['phone'] as String? ?? '').trim();
    if (phone.length > 100) {
      throw const RuleException('Teléfono demasiado largo');
    }
    v.addAll({
      'ownerId': ownerId,
      'owner': {
        'name': requiredText(p['name'], 'Propietario', max: 300),
        'phone': phone,
      },
    });
  } else {
    throw const RuleException('Cambio de vehículo desconocido');
  }
  v['revision'] = (v['revision'] as int) + 1;
  state.configuration['vehicleProfiles'] = profiles;
  state.applied.add(id);
  state.audit.add({
    'id': id,
    'actorId': actor.id,
    'actor': actor.name,
    'kind': 'vehicle_change',
    'at': at.toUtc().toIso8601String(),
    'vehicleId': v['id'],
    'reason': reason,
    'before': before,
    'after': cloneMap(v),
  });
}

Map<String, dynamic> technicalHistoryEntry(WorkOrder o) => {
  for (final k in [
    'id',
    'number',
    'vehicleId',
    'plate',
    'country',
    'vin',
    'vehicle',
    'engine',
    'km',
    'symptom',
    'status',
    'receivedAt',
    'notes',
    'dtcs',
    'diagnoses',
    'photos',
  ])
    if (o.data.containsKey(k)) k: o.data[k],
  'tasks': o.tasks
      .map(
        (t) => {
          for (final k in [
            'id',
            'title',
            'done',
            'cancelled',
            'estimateMinutes',
            'assignees',
          ])
            if (t.containsKey(k)) k: t[k],
        },
      )
      .toList(),
  'times': o.times
      .map(
        (t) => {
          for (final k in ['id', 'taskId', 'actorId', 'start', 'end', 'source'])
            if (t.containsKey(k)) k: t[k],
        },
      )
      .toList(),
  'parts': o.parts
      .map(
        (p) => {
          for (final k in [
            'id',
            'taskId',
            'itemId',
            'description',
            'reference',
            'unit',
            'quantityMilli',
            'kind',
            'actorId',
          ])
            if (p.containsKey(k)) k: p[k],
        },
      )
      .toList(),
};
