import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../domain/engine.dart';
import '../domain/models.dart';
import 'cloud.dart';
import 'demo.dart';
import '../domain/vehicles.dart';

/// An explicitly fictional, in-memory server for exercising the actual Flutter
/// client screens. PostgreSQL remains the authority for real installations.
class SimulatedWorkshop {
  WorkshopState state = demoState();
  SimulatedWorkshop() {
    state.orders['o-1045']!.tasks.first['assignees'] = [
      'tech-alex',
      'tech-lucia',
    ];
  }
  final Map<String, Actor> devices = {};
  final Set<String> retired = {};
  final Map<String, Set<String>> enrolled = {};
  final List<Map<String, dynamic>> requests = [];
  final Map<String, Map<String, dynamic>> records = {}, commands = {};
  void invalidate(String order) {
    for (final r in requests.where(
      (r) => r['orderId'] == order && r['status'] == 'active',
    )) {
      r['status'] = 'invalidated';
    }
  }

  Map<String, dynamic> snapshot(Actor actor, String device) {
    actor = state.members.firstWhere((m) => m.id == actor.id);
    if (!actor.active) {
      throw const PostgrestException(
        message: 'Membership required',
        code: '42501',
      );
    }
    if (retired.contains(device)) {
      throw const PostgrestException(message: 'Device retired', code: '42501');
    }
    if (devices[device] != null && devices[device]!.id != actor.id) {
      throw const RuleException('Identidad de dispositivo incompatible');
    }
    devices[device] = actor;
    final visible = state.orders.values
        .where((o) => actor.isOffice || o.assigned(actor.id))
        .toList();
    for (final o in visible) {
      if ((enrolled[o.id] ??= {}).add(device)) invalidate(o.id);
    }
    return {
      ...cloneMap(state.toJson()),
      'orders': visible.map((o) => o.data).toList(),
      'actor': actor.toJson(),
      'serverTime': DateTime.now().toUtc().toIso8601String(),
      'receipts': records.values
          .where((r) => r['deviceId'] == device)
          .map(
            (r) => {
              'id': r['operation']['id'],
              'status': r['status'],
              'reason': r['reason'],
              'resolved': r['resolution'] != null,
            },
          )
          .toList(),
      'closures': requests,
      'devices': devices.entries
          .where((d) => actor.isOffice || d.value.id == actor.id)
          .map(
            (d) => {
              'id': d.key,
              'userId': d.value.id,
              'lastSeen': 'Simulación',
              'retiredAt': retired.contains(d.key) ? 'Simulación' : null,
              'reason': 'Retirada simulada',
            },
          )
          .toList(),
      'retiredTimers': state.orders.values
          .expand(
            (o) => o.times
                .where((t) => t['end'] == null)
                .map((t) => {...t, 'orderId': o.id}),
          )
          .where(
            (t) =>
                records[t['id']] != null &&
                retired.contains(records[t['id']]!['deviceId']),
          )
          .toList(),
    };
  }

  Map<String, dynamic> push(Actor actor, String device, Operation op) {
    actor = state.members.firstWhere((m) => m.id == actor.id);
    if (!actor.active) {
      throw const PostgrestException(
        message: 'Membership required',
        code: '42501',
      );
    }
    final previous = records[op.id];
    if (previous != null) {
      if (previous['deviceId'] != device ||
          previous['operation'].toString() != op.toJson().toString()) {
        throw const RuleException('Identificador reutilizado con otros datos');
      }
      return {'status': previous['status'], 'reason': previous['reason']};
    }
    if (devices[device]?.id != actor.id || op.actorId != actor.id) {
      throw const RuleException('Cuenta o dispositivo incompatible');
    }
    String status = 'accepted', reason = '';
    if (retired.contains(device) || state.orders[op.orderId]?.issued == true) {
      status = 'late';
      reason = 'Registro tardío o de dispositivo retirado';
    } else {
      try {
        final current = state.orders[op.orderId];
        if ([
              'authorize',
              'billable',
              'quality',
              'review_parts',
              'deliver',
              'task_add',
              'task_edit',
              'task_cancel',
              'task_reopen',
              'task_block',
              'task_unblock',
              'order_plan',
              'unblock',
              'template_apply',
            ].contains(op.kind) &&
            current?.revision != op.baseRevision) {
          throw const RuleException(
            'Cambio concurrente: revisar la versión actual',
          );
        }
        final next = state.copy();
        next.apply(op, actor);
        if (next.catalog.any((i) => next.stock(i.id) < 0)) {
          throw const RuleException(
            'Conflicto de stock: conservar consumo para revisión',
          );
        }
        state = next;
        (enrolled[op.orderId] ??= {}).add(device);
      } catch (e) {
        status = 'conflict';
        reason = '$e';
      }
    }
    final record = {
      'operation': op.toJson(),
      'deviceId': device,
      'status': status,
      'reason': reason,
    };
    records[op.id] = record;
    if (status != 'accepted') state.incidents.add(record);
    invalidate(op.orderId);
    return {'status': status, 'reason': reason};
  }

  Map<String, dynamic> command(
    Actor actor,
    String device,
    String id,
    String action,
    Map<String, dynamic> p,
  ) {
    actor = state.members.firstWhere((m) => m.id == actor.id);
    if (!actor.active) {
      throw const PostgrestException(
        message: 'Membership required',
        code: '42501',
      );
    }
    final prior = commands[id];
    if (prior != null) {
      if (prior['device'] != device ||
          prior['action'] != action ||
          prior['payload'].toString() != p.toString()) {
        throw const RuleException('Identificador de comando incompatible');
      }
      return Map<String, dynamic>.from(prior['result']);
    }
    if (devices[device]?.id != actor.id ||
        (retired.contains(device) && action != 'replace_device')) {
      throw const PostgrestException(message: 'Device retired', code: '42501');
    }
    if (action == 'vehicle_change') {
      final next = state.copy();
      applyVehicleChange(next, id, p, actor, DateTime.now().toUtc());
      state = next;
      for (final r in requests) {
        if (r['status'] == 'active' &&
            state.orders[r['orderId']]?.data['vehicleId'] == p['vehicleId']) {
          r['status'] = 'invalidated';
        }
      }
      final result = {'saved': true};
      commands[id] = {
        'device': device,
        'action': action,
        'payload': cloneMap(p),
        'result': result,
      };
      return result;
    }
    if ([
      'settings_save',
      'member_save',
      'catalog_save',
      'template_save',
    ].contains(action)) {
      final next = state.copy();
      next.manage(id, action, p, actor, DateTime.now().toUtc());
      state = next;
      for (final r in requests) {
        if (r['status'] == 'active') r['status'] = 'invalidated';
      }
      final result = {'saved': true, 'revision': state.managementRevision};
      commands[id] = {
        'device': device,
        'action': action,
        'payload': cloneMap(p),
        'result': result,
      };
      return result;
    }
    if (!actor.isOffice && !['ack_close', 'replace_device'].contains(action)) {
      throw const RuleException('Se requiere oficina');
    }
    final orderId = p['orderId'] as String?;
    final order = state.orders[orderId];
    Map<String, dynamic> result = {};
    switch (action) {
      case 'request_close':
        if (order == null || order.issued || order.revision != p['revision']) {
          throw const RuleException('Revisión actual necesaria');
        }
        final lost = (enrolled[orderId] ?? {}).where(retired.contains).toList();
        if (lost.isNotEmpty &&
            (actor.role != Role.admin ||
                (p['exceptionReason'] as String? ?? '').trim().isEmpty)) {
          throw const RuleException(
            'Dispositivos retirados: exige excepción administrativa explícita',
          );
        }
        invalidate(orderId!);
        final requestId = const Uuid().v4();
        requests.add({
          'id': requestId,
          'orderId': orderId,
          'revision': order.revision,
          'status': 'active',
          'requiredDevices': (enrolled[orderId] ?? {})
              .where((d) => !retired.contains(d))
              .toList(),
          'confirmedDevices': <String>[],
          'retiredDevices': lost,
          'exceptionReason': p['exceptionReason'],
        });
        result = {'requestId': requestId, 'revision': order.revision};
      case 'ack_close':
        final r = _request(p);
        if (order!.times.any(
          (t) => t['actorId'] == actor.id && t['end'] == null,
        )) {
          throw const RuleException(
            'Pausa tu cronómetro y renueva la solicitud',
          );
        }
        if (p['locallyFrozen'] != true || p['revision'] != r['revision']) {
          throw const RuleException('Confirmación obsoleta');
        }
        if (state.incidents.any(
          (i) =>
              i['deviceId'] == device &&
              i['operation']['orderId'] == orderId &&
              i['resolution'] == null,
        )) {
          throw const RuleException('Hay registros pendientes de revisión');
        }
        final confirmed = r['confirmedDevices'] as List;
        if (!confirmed.contains(device)) confirmed.add(device);
        result = {'confirmed': true};
      case 'issue':
        final r = _request(p);
        if ((r['requiredDevices'] as List).any(
          (d) => !(r['confirmedDevices'] as List).contains(d),
        )) {
          throw const RuleException(
            'Dispositivo sin reconciliar: cierre bloqueado',
          );
        }
        if (state.incidents.any(
          (i) =>
              i['operation']['orderId'] == orderId && i['resolution'] == null,
        )) {
          throw const RuleException('Resuelve las incidencias antes de emitir');
        }
        final next = state.copy();
        next.apply(
          Operation(
            id: id,
            orderId: orderId!,
            kind: 'issue',
            actorId: actor.id,
            baseRevision: order!.revision,
            at: DateTime.now().toUtc(),
            payload: {'pending': 0, 'connected': true, 'conflict': false},
          ),
          actor,
        );
        next.orders[orderId]!.data['document'].addAll({
          'closureRequestId': r['id'],
          'closureException': r['exceptionReason'],
          'retiredDevices': r['retiredDevices'],
        });
        state = next;
        r['status'] = 'issued';
        result = {'document': state.orders[orderId]!.data['document']};
      case 'retire_device':
        final target = p['deviceId'];
        if (target == device ||
            !devices.containsKey(target) ||
            (p['reason'] as String? ?? '').trim().isEmpty) {
          throw const RuleException('Otro dispositivo y motivo requeridos');
        }
        retired.add(target);
        for (final o in enrolled.keys.where(
          (o) => enrolled[o]!.contains(target),
        )) {
          invalidate(o);
        }
        result = {'retired': true};
      case 'resolve':
        final original = records[p['operationId']];
        if (original == null ||
            original['status'] == 'accepted' ||
            original['resolution'] != null ||
            (p['reason'] as String? ?? '').trim().isEmpty) {
          throw const RuleException('Registro y motivo de revisión requeridos');
        }
        final source = Operation.fromJson(
          Map<String, dynamic>.from(original['operation']),
        );
        final current = state.orders[source.orderId];
        if (p['revision'] != current?.revision) {
          throw const RuleException('Revisión obsoleta');
        }
        String? correctionId;
        if (p['outcome'] == 'retry') {
          if (current?.issued == true) {
            throw const RuleException(
              'Nota inmutable: conservar incidencia para seguimiento',
            );
          }
          correctionId = const Uuid().v4();
          final next = state.copy();
          final op = Operation(
            id: correctionId,
            orderId: source.orderId,
            kind: source.kind,
            actorId: source.actorId,
            baseRevision: current?.revision ?? 0,
            at: source.at,
            payload: source.payload,
          );
          next.apply(op, demoActors.firstWhere((a) => a.id == source.actorId));
          if (next.catalog.any((i) => next.stock(i.id) < 0)) {
            throw const RuleException('El conflicto de stock sigue pendiente');
          }
          state = next;
        } else if (p['outcome'] != 'archive') {
          throw const RuleException('Resultado inválido');
        }
        final resolution = {
          'responsibleId': actor.id,
          'reason': p['reason'],
          'outcome': p['outcome'],
          'correctionId': correctionId,
          'at': DateTime.now().toUtc().toIso8601String(),
        };
        records[source.id]!['resolution'] = resolution;
        state.incidents.firstWhere(
          (i) => i['operation']['id'] == source.id,
        )['resolution'] = resolution;
        invalidate(source.orderId);
        result = {'resolved': true, 'correctionId': correctionId};
      case 'replace_device':
        if (!retired.contains(device)) {
          throw const RuleException('Solo sustituye un dispositivo retirado');
        }
        devices[p['newDeviceId']] = actor;
        result = {
          'newDeviceId': p['newDeviceId'],
          'previousCommands': commands.entries
              .where((c) => c.value['device'] == device)
              .map((c) => {'id': c.key, 'result': c.value['result']})
              .toList(),
        };
      case 'end_retired_timer':
        final record = records[p['sessionId']];
        if (record == null || !retired.contains(record['deviceId'])) {
          throw const RuleException('Cronómetro retirado requerido');
        }
        final o = state.orders[record['operation']['orderId']]!;
        if (o.issued) throw const RuleException('Nota inmutable');
        final t = o.times.firstWhere((t) => t['id'] == p['sessionId']);
        final end = DateTime.parse(p['end']);
        if (t['end'] != null ||
            end.isBefore(DateTime.parse(t['start'])) ||
            end.isAfter(DateTime.now()) ||
            (p['reason'] as String).trim().isEmpty) {
          throw const RuleException('Hora real y motivo requeridos');
        }
        t.addAll({
          'end': end.toUtc().toIso8601String(),
          'recoveryAuthor': actor.id,
          'recoveryReason': p['reason'],
        });
        o.data['revision'] = o.revision + 1;
        o.data['quality'] = null;
        invalidate(o.id);
        result = {'stopped': true};
      default:
        throw const RuleException('Acción no implementada en la simulación');
    }
    state.audit.add({
      'id': id,
      'actorId': actor.id,
      'actor': actor.name,
      'orderId': orderId,
      'kind': action,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
    commands[id] = {
      'device': device,
      'action': action,
      'payload': p,
      'result': result,
    };
    return result;
  }

  Map<String, dynamic> _request(Map<String, dynamic> p) {
    final r = requests
        .where((r) => r['id'] == p['requestId'] && r['orderId'] == p['orderId'])
        .firstOrNull;
    if (r == null ||
        r['status'] != 'active' ||
        r['revision'] != state.orders[p['orderId']]?.revision) {
      throw const RuleException('Solicitud de cierre obsoleta');
    }
    return r;
  }
}

class SimulatedRemote extends Remote {
  final SimulatedWorkshop workshop;
  final Actor actor;
  String device = '';
  bool disconnected = false;
  SimulatedRemote(this.workshop, this.actor);
  @override
  void bindDevice(String id) => device = id;
  void _connected() {
    if (disconnected) {
      throw StateError('Dispositivo desconectado en la simulación');
    }
  }

  @override
  Future<Map<String, dynamic>> snapshot() async {
    _connected();
    return cloneMap(workshop.snapshot(actor, device));
  }

  @override
  Future<Map<String, dynamic>> push(Operation op, String deviceId) async {
    _connected();
    return workshop.push(actor, deviceId, op);
  }

  @override
  Future<Map<String, dynamic>> command(
    String id,
    String action,
    Map<String, dynamic> payload,
  ) async {
    _connected();
    try {
      return workshop.command(actor, device, id, action, payload);
    } on RuleException catch (e) {
      throw PostgrestException(message: e.message, code: 'P0001');
    }
  }
}
