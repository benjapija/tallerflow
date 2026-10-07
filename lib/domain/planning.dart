import 'dart:convert';
import 'engine.dart';
import 'management.dart';
import 'models.dart';

/// Reservations are confirmed only by the server. They do not authorize work,
/// bill time or change the commercial documents of a repair.
class PlanningLedger {
  final Map<String, dynamic> _data;
  PlanningLedger([Map<String, dynamic>? data])
    : _data = cloneMap(
        data ?? {'revision': 0, 'resources': [], 'bookings': []},
      );
  int get revision => _data['revision'];
  Map<String, dynamic> toJson() => cloneMap(_data);
  List<Map<String, dynamic>> get resources =>
      (toJson()['resources'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get bookings =>
      (toJson()['bookings'] as List).cast<Map<String, dynamic>>();

  PlanningLedger apply(
    String action,
    Map<String, dynamic> p,
    Actor actor,
    DateTime now,
    String commandId,
    List<Actor> members,
    Set<String> orders,
  ) {
    if (!actor.active || !actor.isOffice) {
      throw const RuleException('Se requiere oficina activa');
    }
    if (p['revision'] != revision) {
      throw const RuleException('La agenda ha cambiado. Actualiza y revisa');
    }
    final id = requiredText(p['id'], 'Identificador', max: 100);
    final reason = requiredText(p['reason'], 'Motivo');
    final next = toJson();
    final event = {
      'id': commandId,
      'actorId': actor.id,
      'at': now.toUtc().toIso8601String(),
      'kind': action,
      'reason': reason,
    };
    if (action == 'schedule_resource') {
      if (actor.role != Role.admin) {
        throw const RuleException('Administración configura los elevadores');
      }
      _keys(p, {'id', 'revision', 'name', 'active', 'reason'});
      if (p['active'] is! bool) {
        throw const RuleException('Confirma la disponibilidad del elevador');
      }
      if (p['active'] == false &&
          bookings.any(
            (b) =>
                b['liftId'] == id &&
                b['status'] == 'planned' &&
                DateTime.parse(b['end']).isAfter(now),
          )) {
        throw const RuleException(
          'Reasigna o cancela las reservas del elevador',
        );
      }
      final list = next['resources'] as List;
      final previous = list.where((r) => r['id'] == id).firstOrNull;
      list.removeWhere((r) => r['id'] == id);
      list.add({
        'id': id,
        'name': requiredText(p['name'], 'Elevador', max: 120),
        'active': p['active'],
        'events': [...?previous?['events'], event],
      });
    } else if (action == 'schedule_booking') {
      _keys(p, {
        'id',
        'revision',
        'title',
        'start',
        'end',
        'kind',
        'assignees',
        'liftId',
        'orderId',
        'reason',
      });
      final start = planningDate(p['start']), end = planningDate(p['end']);
      if (!end.isAfter(start) ||
          end.difference(start) > const Duration(days: 7)) {
        throw const RuleException('Reserva entre un minuto y siete días');
      }
      if (end.difference(start) < const Duration(minutes: 1)) {
        throw const RuleException('La reserva necesita al menos un minuto');
      }
      if (!['appointment', 'unavailable'].contains(p['kind'])) {
        throw const RuleException('Selecciona cita o indisponibilidad');
      }
      final raw = p['assignees'];
      if (raw is! List ||
          raw.length > 50 ||
          raw.any((v) => v is! String) ||
          raw.toSet().length != raw.length ||
          raw.any(
            (id) => !members.any(
              (m) => m.id == id && m.active && m.role == Role.technician,
            ),
          )) {
        throw const RuleException(
          'Selecciona operarios activos sin duplicados',
        );
      }
      final liftId = p['liftId'];
      if (liftId != null &&
          !resources.any((r) => r['id'] == liftId && r['active'] == true)) {
        throw const RuleException('Selecciona un elevador disponible');
      }
      if (raw.isEmpty && liftId == null) {
        throw const RuleException('Reserva al menos un operario o elevador');
      }
      if (p['orderId'] != null && !orders.contains(p['orderId'])) {
        throw const RuleException('La orden no pertenece al taller');
      }
      if (p['kind'] == 'unavailable' && p['orderId'] != null) {
        throw const RuleException(
          'La indisponibilidad no se vincula a una reparación',
        );
      }
      final list = next['bookings'] as List;
      final previous = list.where((b) => b['id'] == id).firstOrNull;
      if (previous != null && previous['status'] != 'planned') {
        throw const RuleException(
          'Conserva la reserva terminada; crea una nueva',
        );
      }
      for (final b in bookings.where(
        (b) => b['id'] != id && b['status'] == 'planned',
      )) {
        if (start.isBefore(DateTime.parse(b['end'])) &&
            end.isAfter(DateTime.parse(b['start'])) &&
            ((liftId != null && liftId == b['liftId']) ||
                raw.any((a) => (b['assignees'] as List).contains(a)))) {
          throw const RuleException(
            'Se solapa con una reserva de operario o elevador',
          );
        }
      }
      final value = {
        'id': id,
        'title': requiredText(p['title'], 'Cita', max: 300),
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'kind': p['kind'],
        'assignees': List.of(raw),
        'liftId': liftId,
        'orderId': p['orderId'],
        'status': 'planned',
      };
      list.removeWhere((b) => b['id'] == id);
      list.add({
        ...value,
        'versions': [
          ...?previous?['versions'],
          {...value, ...event, 'kind': p['kind'], 'commandKind': action},
        ],
        'events': [...?previous?['events'], event],
      });
    } else if (action == 'schedule_status') {
      _keys(p, {'id', 'revision', 'status', 'reason'});
      final booking = (next['bookings'] as List)
          .where((b) => b['id'] == id)
          .firstOrNull;
      if (booking == null ||
          booking['status'] != 'planned' ||
          !['done', 'cancelled'].contains(p['status'])) {
        throw const RuleException('La reserva debe estar pendiente');
      }
      booking['status'] = p['status'];
      (booking['events'] as List).add({...event, 'status': p['status']});
    } else {
      throw const RuleException('Acción de agenda desconocida');
    }
    next['revision'] = revision + 1;
    return PlanningLedger(next);
  }

  static void _keys(Map<String, dynamic> p, Set<String> keys) {
    if (p.keys.any((k) => !keys.contains(k))) {
      throw const RuleException('Datos de agenda no admitidos');
    }
  }
}

DateTime planningDate(dynamic value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,6})?)?(Z|[+-]\d{2}:\d{2})$',
      ).hasMatch(value)) {
    throw const RuleException(
      'Indica fecha, hora y zona: 2026-10-08T09:00+02:00',
    );
  }
  final parsed = DateTime.tryParse(value);
  final year = int.parse(value.substring(0, 4)),
      month = int.parse(value.substring(5, 7)),
      day = int.parse(value.substring(8, 10));
  if (parsed == null ||
      year < 2000 ||
      year > 2100 ||
      month < 1 ||
      month > 12 ||
      day < 1 ||
      day > DateTime.utc(year, month + 1, 0).day ||
      int.parse(value.substring(11, 13)) > 23 ||
      int.parse(value.substring(14, 16)) > 59 ||
      (value.length > 16 &&
          value[16] == ':' &&
          int.parse(value.substring(17, 19)) > 59)) {
    throw const RuleException('Fecha de agenda inválida');
  }
  if (!value.endsWith('Z') &&
      (int.parse(value.substring(value.length - 5, value.length - 3)) > 14 ||
          int.parse(value.substring(value.length - 2)) > 59)) {
    throw const RuleException('Zona horaria inválida');
  }
  return parsed.toUtc();
}

void applyPlanningCommand(
  WorkshopState state,
  String id,
  String action,
  Map<String, dynamic> p,
  Actor actor,
  DateTime at,
) {
  if (!actor.active || !actor.isOffice) {
    throw const RuleException('Se requiere oficina activa');
  }
  if (state.applied.contains(id)) {
    final previous = state.audit.where((e) => e['id'] == id).firstOrNull;
    if (previous == null ||
        previous['actorId'] != actor.id ||
        previous['kind'] != action ||
        jsonEncode(previous['payload']) != jsonEncode(p)) {
      throw const RuleException(
        'Identificador reutilizado con datos diferentes',
      );
    }
    return;
  }
  final next = PlanningLedger(
    state.configuration['planning'],
  ).apply(action, p, actor, at, id, state.members, state.orders.keys.toSet());
  state.configuration['planning'] = next.toJson();
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

Map<String, dynamic> visiblePlanning(WorkshopState state, Actor actor) {
  final data = PlanningLedger(state.configuration['planning']).toJson();
  if (actor.isOffice) return data;
  data['resources'] = [
    for (final r in data['resources'])
      <String, dynamic>{...r}..remove('events'),
  ];
  data['bookings'] = [
    for (final b in data['bookings'])
      if ((b['assignees'] as List).contains(actor.id))
        {
          ...b,
          'versions': [],
          'events': [],
          'orderId': state.orders[b['orderId']]?.assigned(actor.id) == true
              ? b['orderId']
              : null,
        },
  ];
  return data;
}
