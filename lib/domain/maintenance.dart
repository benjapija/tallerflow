import 'dart:convert';
import 'engine.dart';
import 'management.dart';
import 'models.dart';
import 'planning.dart';
import 'planning_time.dart';
import 'vehicles.dart';

class MaintenanceLedger {
  final Map<String, dynamic> _data;
  MaintenanceLedger([Map<String, dynamic>? data])
    : _data = cloneMap(data ?? {'revision': 0, 'plans': []});
  int get revision => _data['revision'];
  Map<String, dynamic> toJson() => cloneMap(_data);
  List<Map<String, dynamic>> get plans =>
      (toJson()['plans'] as List).cast<Map<String, dynamic>>();
  MaintenanceLedger apply(
    String action,
    Map<String, dynamic> p,
    Actor actor,
    DateTime now,
    String commandId,
    List<Map<String, dynamic>> vehicles,
    Map<String, WorkOrder> orders,
  ) {
    if (!actor.active || !actor.isOffice) {
      throw const RuleException('Oficina gestiona el mantenimiento');
    }
    if (p['revision'] != revision) {
      throw const RuleException(
        'El mantenimiento ha cambiado. Actualiza y revisa',
      );
    }
    final id = requiredText(p['id'], 'Plan', max: 100),
        reason = requiredText(p['reason'], 'Motivo');
    final next = toJson(), list = next['plans'] as List;
    final previous = list.where((x) => x['id'] == id).firstOrNull;
    final event = {
      'id': commandId,
      'kind': action,
      'actorId': actor.id,
      'at': now.toUtc().toIso8601String(),
      'reason': reason,
    };
    Map<String, dynamic> value;
    if (action == 'care_plan') {
      _keys(p, {
        'id',
        'revision',
        'vehicleId',
        'title',
        'source',
        'dueDate',
        'dueKm',
        'intervalMonths',
        'intervalKm',
        'zone',
        'reason',
      });
      if (previous != null &&
          (previous['vehicleId'] != p['vehicleId'] ||
              previous['status'] != 'active')) {
        throw const RuleException(
          'Conserva el vehículo original y crea un plan nuevo si está terminado',
        );
      }
      if (!vehicles.any((v) => v['id'] == p['vehicleId'])) {
        throw const RuleException('Selecciona un vehículo del taller');
      }
      final zone = requiredText(p['zone'], 'Zona horaria', max: 100);
      PlanningTime.location(zone);
      final due = p['dueDate'] == null ? null : maintenanceDay(p['dueDate']);
      final km = p['dueKm'] == null
          ? null
          : boundedInt(p['dueKm'], 9999999, 'Kilometraje previsto');
      if (due == null && km == null) {
        throw const RuleException('Indica una fecha o kilometraje previsto');
      }
      final months = p['intervalMonths'] == null
          ? null
          : boundedInt(p['intervalMonths'], 120, 'Intervalo en meses', min: 1);
      final interval = p['intervalKm'] == null
          ? null
          : boundedInt(p['intervalKm'], 2000000, 'Intervalo en km', min: 1);
      if ((months != null && due == null) || (interval != null && km == null)) {
        throw const RuleException('El intervalo necesita su previsión inicial');
      }
      final version = {
        'zone': zone,
        'title': requiredText(p['title'], 'Mantenimiento', max: 300),
        'source': requiredText(
          p['source'],
          'Fuente o criterio confirmado',
          max: 2000,
        ),
        'dueDate': due,
        'dueKm': km,
        'intervalMonths': months,
        'intervalKm': interval,
        'actorId': actor.id,
        'at': now.toUtc().toIso8601String(),
      };
      value = {
        'id': id,
        'vehicleId': p['vehicleId'],
        ...version,
        'status': 'active',
        'versions': [...?previous?['versions'], version],
        'completions': [...?previous?['completions']],
        'events': [...?previous?['events'], event],
      };
    } else if (action == 'care_complete') {
      _keys(p, {
        'id',
        'revision',
        'performedAt',
        'km',
        'orderId',
        'evidence',
        'reason',
      });
      if (previous == null || previous['status'] != 'active') {
        throw const RuleException('Selecciona un plan activo');
      }
      final at = planningDate(p['performedAt']),
          km = boundedInt(p['km'], 9999999, 'Kilometraje realizado');
      if (at.isAfter(now.add(const Duration(minutes: 2)))) {
        throw const RuleException(
          'No se puede registrar un mantenimiento futuro',
        );
      }
      final local = maintenanceLocalDay(at, previous['zone']);
      final last = (previous['completions'] as List).lastOrNull;
      if (last != null &&
          (!at.isAfter(DateTime.parse(last['performedAt'])) ||
              km < last['km'])) {
        throw const RuleException(
          'Conserva el orden de fechas y kilometraje de las intervenciones',
        );
      }
      final oid = p['orderId'];
      if (oid != null &&
          (orders[oid] == null ||
              (orders[oid]!.data['vehicleId'] ?? oid) !=
                  previous['vehicleId'])) {
        throw const RuleException(
          'La orden debe corresponder al mismo vehículo',
        );
      }
      final completed = {
        'id': commandId,
        'performedAt': at.toIso8601String(),
        'performedDate': local,
        'valueSource': 'manual',
        'km': km,
        'orderId': oid,
        'evidence': requiredText(
          p['evidence'],
          'Evidencia de la intervención',
          max: 2000,
        ),
        'actorId': actor.id,
        'planVersion': (previous['versions'] as List).length,
        'dueDate': previous['dueDate'],
        'dueKm': previous['dueKm'],
      };
      final months = previous['intervalMonths'] as int?,
          interval = previous['intervalKm'] as int?;
      final nextKm = interval == null
          ? null
          : boundedInt(km + interval, 9999999, 'Próximo kilometraje');
      value = {
        ...previous,
        'dueDate': months == null
            ? null
            : maintenanceDay(
                addMaintenanceMonths(DateTime.parse(local), months),
              ),
        'dueKm': nextKm,
        'status': months == null && interval == null ? 'completed' : 'active',
        'completions': [...previous['completions'], completed],
        'events': [...previous['events'], event],
      };
    } else if (action == 'care_pause') {
      _keys(p, {'id', 'revision', 'reason'});
      if (previous == null || previous['status'] != 'active') {
        throw const RuleException('Selecciona un plan activo');
      }
      value = {
        ...previous,
        'status': 'paused',
        'events': [...previous['events'], event],
      };
    } else {
      throw const RuleException('Acción de mantenimiento desconocida');
    }
    list.removeWhere((x) => x['id'] == id);
    list.add(value);
    next['revision'] = revision + 1;
    return MaintenanceLedger(next);
  }

  static void _keys(Map<String, dynamic> p, Set<String> keys) {
    if (p.keys.any((k) => !keys.contains(k))) {
      throw const RuleException('Datos de mantenimiento no admitidos');
    }
  }
}

String maintenanceDay(dynamic value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const RuleException('Fecha prevista: aaaa-mm-dd');
  }
  final d = planningDate('${value}T00:00:00Z');
  return d.toIso8601String().substring(0, 10);
}

String addMaintenanceMonths(DateTime at, int months) {
  final date = DateTime.utc(at.year, at.month + months, 1),
      last = DateTime.utc(date.year, date.month + 1, 0).day;
  return DateTime.utc(
    date.year,
    date.month,
    at.day > last ? last : at.day,
  ).toIso8601String().substring(0, 10);
}

String maintenanceStatus(
  Map<String, dynamic> plan,
  DateTime today,
  int? knownKm,
) {
  if (plan['status'] == 'completed') return 'Realizado';
  if (plan['status'] == 'paused') return 'Pausado';
  final day = today.toIso8601String().substring(0, 10),
      due = plan['dueDate'] as String?,
      km = plan['dueKm'] as int?;
  if ((due != null && due.compareTo(day) <= 0) ||
      (km != null && knownKm != null && knownKm >= km)) {
    return 'Revisar mantenimiento';
  }
  if (km != null && knownKm == null) return 'Kilometraje por comprobar';
  return 'Previsto';
}

void applyMaintenanceCommand(
  WorkshopState state,
  String id,
  String action,
  Map<String, dynamic> p,
  Actor actor,
  DateTime at,
) {
  if (!actor.active || !actor.isOffice) {
    throw const RuleException('Oficina gestiona el mantenimiento');
  }
  if (state.applied.contains(id)) {
    final old = state.audit.where((x) => x['id'] == id).firstOrNull;
    if (old == null ||
        old['actorId'] != actor.id ||
        old['kind'] != action ||
        jsonEncode(old['payload']) != jsonEncode(p)) {
      throw const RuleException(
        'Identificador reutilizado con datos diferentes',
      );
    }
    return;
  }
  final result = MaintenanceLedger(
    state.configuration['maintenance'],
  ).apply(action, p, actor, at, id, vehicleProfiles(state), state.orders);
  if (action == 'care_complete') {
    final completed = result.plans.firstWhere((plan) => plan['id'] == p['id']);
    final profiles = vehicleProfiles(state);
    final profile = profiles.firstWhere(
      (v) => v['id'] == completed['vehicleId'],
    );
    final km = p['km'] as int;
    if (km > (profile['km'] as int? ?? 0)) profile['km'] = km;
    state.configuration['vehicleProfiles'] = profiles;
  }
  state.configuration['maintenance'] = result.toJson();
  state.applied.add(id);
  state.audit.add({
    'id': id,
    'actorId': actor.id,
    'actor': actor.name,
    'kind': action,
    'at': at.toUtc().toIso8601String(),
    'payload': cloneMap(p),
  });
}

Map<String, dynamic> visibleMaintenance(WorkshopState state, Actor actor) {
  final data = MaintenanceLedger(state.configuration['maintenance']).toJson();
  if (actor.isOffice) return data;
  final visible = state.orders.values
      .where((o) => o.assigned(actor.id))
      .map((o) => o.data['vehicleId'] ?? o.id)
      .toSet();
  data['plans'] = [
    for (final p in data['plans'])
      if (visible.contains(p['vehicleId']))
        {
          ...p,
          'events': [],
          'versions': [],
          'completions': [
            for (final e in p['completions'])
              {
                ...e,
                'orderId':
                    state.orders[e['orderId']]?.assigned(actor.id) == true
                    ? e['orderId']
                    : null,
              },
          ],
        },
  ];
  return data;
}

String maintenanceLocalDay(DateTime at, String zone) {
  final date = PlanningTime.format(at, zone).split(' ').first.split('/');
  return '${date[2]}-${date[1]}-${date[0]}';
}
