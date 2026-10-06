import 'models.dart';
import 'management.dart';
import 'tasks.dart';

class RuleException implements Exception {
  final String message;
  const RuleException(this.message);
  @override
  String toString() => message;
}

class Operation {
  final String id, orderId, kind, actorId;
  final int baseRevision;
  final DateTime at;
  final Map<String, dynamic> payload;
  Operation({
    required this.id,
    required this.orderId,
    required this.kind,
    required this.actorId,
    required this.baseRevision,
    required this.at,
    required this.payload,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'orderId': orderId,
    'kind': kind,
    'actorId': actorId,
    'baseRevision': baseRevision,
    'at': at.toUtc().toIso8601String(),
    'payload': payload,
  };
  factory Operation.fromJson(Map<String, dynamic> j) => Operation(
    id: j['id'],
    orderId: j['orderId'],
    kind: j['kind'],
    actorId: j['actorId'],
    baseRevision: j['baseRevision'],
    at: DateTime.parse(j['at']),
    payload: j['payload'],
  );
}

class WorkshopState {
  final String workshopId;
  final Map<String, WorkOrder> orders;
  final List<CatalogItem> catalog;
  final List<Actor> members;
  final List<Map<String, dynamic>> audit;
  final Set<String> applied;
  final List<Map<String, dynamic>> incidents;
  final Map<String, dynamic> configuration;
  WorkshopState({
    required this.workshopId,
    required this.orders,
    required List<CatalogItem> catalog,
    List<Actor> members = const [],
    Map<String, dynamic>? configuration,
    List<Map<String, dynamic>>? audit,
    Set<String>? applied,
    List<Map<String, dynamic>>? incidents,
  }) : catalog = List.of(catalog),
       members = List.of(members),
       configuration = configuration ?? {},
       audit = audit ?? [],
       applied = applied ?? {},
       incidents = incidents ?? [];
  Map<String, dynamic> toJson() => {
    'workshopId': workshopId,
    'orders': orders.values.map((o) => o.data).toList(),
    'catalog': catalog.map((i) => i.toJson()).toList(),
    'members': members.map((a) => a.toJson()).toList(),
    'audit': audit,
    'applied': applied.toList(),
    'incidents': incidents,
    ...configuration,
  };
  factory WorkshopState.fromJson(Map<String, dynamic> j) => WorkshopState(
    workshopId: j['workshopId'],
    orders: {
      for (final o in j['orders'])
        o['id'] as String: WorkOrder(Map<String, dynamic>.from(o)),
    },
    catalog: (j['catalog'] as List)
        .map((c) => CatalogItem.fromJson(Map<String, dynamic>.from(c)))
        .toList(),
    members: (j['members'] as List? ?? [])
        .map((a) => Actor.fromJson(Map<String, dynamic>.from(a)))
        .toList(),
    audit: (j['audit'] as List? ?? []).cast<Map<String, dynamic>>(),
    applied: (j['applied'] as List? ?? []).cast<String>().toSet(),
    incidents: (j['incidents'] as List? ?? []).cast<Map<String, dynamic>>(),
    configuration: {
      for (final k in ['settings', 'templates', 'managementRevision'])
        if (j.containsKey(k)) k: j[k],
    },
  );
  Map<String, dynamic> get settings =>
      Map<String, dynamic>.from(configuration['settings'] ?? defaultSettings);
  List<Map<String, dynamic>> get templates =>
      (configuration['templates'] as List? ?? []).cast<Map<String, dynamic>>();
  int get managementRevision => configuration['managementRevision'] ?? 0;
  void manage(
    String id,
    String action,
    Map<String, dynamic> payload,
    Actor actor,
    DateTime at,
  ) => applyManagement(this, id, action, payload, actor, at);
  WorkshopState copy() => WorkshopState.fromJson(cloneMap(toJson()));
  int stock(String itemId) {
    final item = catalog.firstWhere((c) => c.id == itemId);
    var used = 0;
    for (final order in orders.values) {
      for (final p in order.parts.where((p) => p['itemId'] == itemId)) {
        if (p['kind'] == 'consume') used += p['quantityMilli'] as int;
        if (p['kind'] == 'return') used -= p['quantityMilli'] as int;
      }
    }
    return item.stockMilli - used;
  }

  int reserved(String itemId) => orders.values
      .expand((o) => o.parts)
      .where((p) => p['itemId'] == itemId && p['kind'] == 'reserve')
      .fold(0, (s, p) => s + (p['quantityMilli'] as int));

  /// Applied to a copy by the repository; failed operations never mutate live state.
  void apply(Operation op, Actor actor, {bool replay = false}) {
    if (applied.contains(op.id)) return;
    if (!actor.active) throw const RuleException('Cuenta desactivada');
    if (op.actorId != actor.id) {
      throw const RuleException('La identidad no coincide');
    }
    if (op.kind == 'receive') {
      if (!actor.isOffice) {
        throw const RuleException('Solo oficina puede abrir una recepción');
      }
      if (orders.containsKey(op.orderId)) {
        throw const RuleException('La orden ya existe');
      }
      final d = cloneMap(op.payload);
      if ((d['symptom'] as String).trim().isEmpty ||
          normalizePlate(d['plate']).isEmpty) {
        throw const RuleException('Matrícula y síntoma son obligatorios');
      }
      d['plate'] = normalizePlate(d['plate']);
      final existing = orders.values
          .where(
            (o) =>
                (o.data['vin'] != '' && o.data['vin'] == d['vin']) ||
                (o.data['country'] == d['country'] &&
                    o.plate == normalizePlate(d['plate'])),
          )
          .firstOrNull;
      if (existing != null) d['vehicleId'] = existing.data['vehicleId'];
      d['id'] = op.orderId;
      d['revision'] = 0;
      d['status'] = 'pending';
      d['times'] = <Map<String, dynamic>>[];
      d['parts'] = <Map<String, dynamic>>[];
      d['notes'] = <Map<String, dynamic>>[];
      orders[op.orderId] = WorkOrder(d);
      _record(op, actor);
      return;
    }
    final order = orders[op.orderId];
    if (order == null) throw const RuleException('Orden no descargada');
    if (!actor.isOffice && !order.assigned(actor.id)) {
      throw const RuleException('Esta orden no está asignada a tu cuenta');
    }
    if (order.issued && op.kind != 'deliver') {
      if (!replay) {
        throw const RuleException(
          'La nota está emitida. Registra una incidencia en oficina',
        );
      }
      incidents.add({
        'operation': op.toJson(),
        'reason': 'Registro recibido después de emitir la nota',
      });
      _record(op, actor);
      return;
    }
    final d = order.data;
    final p = op.payload;
    Map<String, dynamic> task() => order.tasks.firstWhere(
      (t) => t['id'] == p['taskId'],
      orElse: () => throw const RuleException('Tarea no encontrada'),
    );
    void office() {
      if (!actor.isOffice) {
        throw const RuleException('Se requiere permiso de oficina');
      }
    }

    void assignedTask(Map<String, dynamic> t) {
      if (!actor.isOffice && !(t['assignees'] as List).contains(actor.id)) {
        throw const RuleException('Tarea no asignada');
      }
    }

    switch (op.kind) {
      case 'start':
        final t = task();
        if (t['block'] != null || d['block'] != null) {
          throw const RuleException('Resuelve el bloqueo antes de iniciar');
        }
        assignedTask(t);
        if (t['authorized'] != true) {
          throw const RuleException('Esta tarea espera autorización');
        }
        if (t['done'] == true) {
          throw const RuleException('La tarea ya está terminada');
        }
        if (orders.values
            .expand((o) => o.times)
            .any((e) => e['actorId'] == actor.id && e['end'] == null)) {
          throw const RuleException(
            'Pausa tu cronómetro actual antes de iniciar otro',
          );
        }
        order.times.add({
          'id': op.id,
          'taskId': t['id'],
          'actorId': actor.id,
          'start': op.at.toUtc().toIso8601String(),
          'end': null,
          'source': 'timer',
        });
        d['status'] = 'repair';
      case 'stop':
        final e = order.times.firstWhere(
          (e) => e['id'] == p['sessionId'],
          orElse: () => throw const RuleException('Sesión no encontrada'),
        );
        if (e['actorId'] != actor.id) {
          throw const RuleException('Solo puedes pausar tu cronómetro');
        }
        if (e['end'] != null) {
          throw const RuleException('La sesión ya está cerrada');
        }
        if (op.at.isBefore(DateTime.parse(e['start']))) {
          throw const RuleException('El reloj del dispositivo ha retrocedido');
        }
        e['end'] = op.at.toUtc().toIso8601String();
      case 'manual_time':
        final t = task();
        assignedTask(t);
        if (t['authorized'] != true) {
          throw const RuleException('La tarea espera autorización');
        }
        if ((p['reason'] as String? ?? '').trim().isEmpty) {
          throw const RuleException('Indica el motivo del tiempo manual');
        }
        final start = DateTime.parse(p['start']);
        final end = DateTime.parse(p['end']);
        if (!end.isAfter(start) || end.isAfter(op.at)) {
          throw const RuleException('Intervalo de tiempo inválido');
        }
        if (orders.values
            .expand((o) => o.times)
            .any(
              (e) =>
                  e['actorId'] == actor.id &&
                  start.isBefore(
                    e['end'] == null ? op.at : DateTime.parse(e['end']),
                  ) &&
                  end.isAfter(DateTime.parse(e['start'])),
            )) {
          throw const RuleException(
            'Este intervalo se solapa con otro registro',
          );
        }
        order.times.add({
          'id': op.id,
          'taskId': t['id'],
          'actorId': actor.id,
          'start': start.toUtc().toIso8601String(),
          'end': end.toUtc().toIso8601String(),
          'source': 'manual',
          'reason': p['reason'],
        });
      case 'part':
        final t = task();
        assignedTask(t);
        if (t['authorized'] != true) {
          throw const RuleException('La tarea espera autorización');
        }
        if (!['consume', 'reserve', 'customer'].contains(p['kind'])) {
          throw const RuleException('Movimiento inválido');
        }
        final item = catalog.firstWhere((c) => c.id == p['itemId']);
        final q = p['quantityMilli'] as int;
        if (!item.active) throw const RuleException('Referencia desactivada');
        if (q <= 0) throw const RuleException('La cantidad debe ser positiva');
        order.parts.add({
          'id': op.id,
          'taskId': t['id'],
          'itemId': item.id,
          'description': item.description,
          'reference': item.reference,
          'unit': item.unit,
          'quantityMilli': q,
          'priceCents': item.priceCents,
          'costCents': item.costCents,
          'taxBps': item.taxBps ?? settings['taxBps'] ?? 2100,
          'costKnown': item.costKnown,
          'kind': p['kind'],
          'charge': p['kind'] == 'consume',
          'reviewed': false,
          'actorId': actor.id,
        });
      case 'return':
        final source = order.parts.firstWhere((r) => r['id'] == p['sourceId']);
        assignedTask(
          order.tasks.firstWhere((t) => t['id'] == source['taskId']),
        );
        if (source['kind'] != 'consume') {
          throw const RuleException('Selecciona un consumo');
        }
        final returned = order.parts
            .where((r) => r['sourceId'] == source['id'])
            .fold<int>(0, (s, r) => s + (r['quantityMilli'] as int));
        final q = p['quantityMilli'] as int;
        if (q <= 0 || q + returned > source['quantityMilli']) {
          throw const RuleException('La devolución supera el consumo');
        }
        order.parts.add({
          ...source,
          'id': op.id,
          'kind': 'return',
          'sourceId': source['id'],
          'quantityMilli': q,
          'charge': false,
          'reviewed': false,
          'actorId': actor.id,
        });
      case 'note':
        if ((p['text'] as String? ?? '').trim().isEmpty) {
          throw const RuleException('Escribe una observación');
        }
        order.notes.add({
          'id': op.id,
          'text': p['text'],
          'author': actor.name,
          'at': op.at.toUtc().toIso8601String(),
        });
      case 'finish_task':
        final t = task();
        if (t['block'] != null || t['cancelled'] == true) {
          throw const RuleException('Tarea bloqueada o cancelada');
        }
        assignedTask(t);
        if (t['authorized'] != true) {
          throw const RuleException('La tarea no está autorizada');
        }
        if (order.times.any(
          (e) => e['taskId'] == t['id'] && e['end'] == null,
        )) {
          throw const RuleException('Pausa los cronómetros de esta tarea');
        }
        t['done'] = true;
        if (order.tasks
            .where((t) => t['authorized'] == true)
            .every((t) => t['done'] == true)) {
          d['status'] = 'finished';
        }
      case 'authorize':
        office();
        final t = task();
        if ((p['evidence'] as String? ?? '').trim().isEmpty ||
            (p['customer'] as String? ?? '').trim().isEmpty) {
          throw const RuleException(
            'Indica destinatario y soporte de autorización',
          );
        }
        final amount = p['approvedCents'] as int;
        if (amount < 0) throw const RuleException('Importe inválido');
        t['authorized'] = true;
        t['approvedCents'] = amount;
        t['authorization'] = {
          'version': p['version'],
          'customer': p['customer'],
          'evidence': p['evidence'],
          'actorId': actor.id,
          'at': op.at.toUtc().toIso8601String(),
          'approvedCents': amount,
        };
      case 'billable':
        office();
        final t = task();
        final minutes = p['minutes'] as int;
        if (minutes < 0 || minutes > 14400) {
          throw const RuleException('Minutos facturables inválidos');
        }
        if (t['authorized'] != true && minutes > 0) {
          throw const RuleException('Falta autorización');
        }
        if ((p['reason'] as String? ?? '').trim().isEmpty) {
          throw const RuleException('Indica el motivo de la revisión');
        }
        t['billableMinutes'] = minutes;
      case 'review_parts':
        office();
        for (final part in order.parts) {
          part['reviewed'] = true;
        }
      case 'quality':
        if (order.times.any((e) => e['end'] == null)) {
          throw const RuleException('Pausa los cronómetros antes de verificar');
        }
        if (order.tasks
            .where((t) => t['authorized'] == true)
            .any((t) => t['done'] != true)) {
          throw const RuleException('Termina las tareas autorizadas');
        }
        if ((p['result'] as String? ?? '').trim().isEmpty) {
          throw const RuleException('Registra el resultado de la comprobación');
        }
        d['quality'] = {
          'result': p['result'],
          'pendingSymptoms': p['pendingSymptoms'],
          'actorId': actor.id,
          'at': op.at.toUtc().toIso8601String(),
        };
        d['status'] = 'verified';
      case 'block':
        if ((p['reason'] as String? ?? '').trim().isEmpty) {
          throw const RuleException('Indica el motivo del bloqueo');
        }
        d['block'] = p['reason'];
        d['nextAction'] = p['nextAction'];
        d['status'] = 'parts';
      case 'task_add':
      case 'task_edit':
      case 'task_cancel':
      case 'task_reopen':
      case 'task_block':
      case 'task_unblock':
      case 'order_plan':
      case 'unblock':
      case 'template_apply':
        applyTaskChange(this, order, op, actor);
      case 'issue':
        office();
        final issues = closeIssues(
          order,
          pending: p['pending'] ?? 0,
          connected: p['connected'] == true,
          conflict: p['conflict'] == true,
        );
        if (catalog.any((c) => stock(c.id) < 0)) {
          issues.add('Hay discrepancias de stock');
        }
        if (issues.isNotEmpty) throw RuleException(issues.join('\n'));
        d['document'] = {
          ...calculateNote(order).toJson(),
          'issuedAt': op.at.toUtc().toIso8601String(),
          'issuedBy': actor.id,
          'revision': order.revision,
          'clientSnapshot': d['client'],
          'plateSnapshot': d['plate'],
        };
      case 'deliver':
        office();
        if (!order.issued) {
          throw const RuleException('Revisa y emite la nota antes de entregar');
        }
        if ((p['reason'] as String? ?? '').trim().isEmpty) {
          throw const RuleException(
            'Indica el motivo de entrega con saldo pendiente',
          );
        }
        d['status'] = 'delivered';
        d['delivery'] = {
          'reason': p['reason'],
          'actorId': actor.id,
          'at': op.at.toUtc().toIso8601String(),
        };
      default:
        throw RuleException('Operación no soportada: ${op.kind}');
    }
    if ([
      'start',
      'manual_time',
      'part',
      'return',
      'finish_task',
      'task_add',
      'task_edit',
      'task_cancel',
      'task_reopen',
      'template_apply',
    ].contains(op.kind)) {
      d['quality'] = null;
    }
    d['revision'] = order.revision + 1;
    _record(op, actor);
  }

  void _record(Operation op, Actor actor) {
    applied.add(op.id);
    audit.add({
      'id': op.id,
      'orderId': op.orderId,
      'actor': actor.name,
      'actorId': actor.id,
      'kind': op.kind,
      'at': op.at.toUtc().toIso8601String(),
      'payload': op.payload,
    });
  }
}
