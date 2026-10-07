import 'dart:convert';
import 'engine.dart';
import 'management.dart';
import 'models.dart';
import 'vehicles.dart';

class FleetLedger {
  final Map<String, dynamic> _data;
  FleetLedger([Map<String, dynamic>? data])
    : _data = cloneMap(data ?? {'revision': 0, 'groups': []});
  int get revision => _data['revision'];
  Map<String, dynamic> toJson() => cloneMap(_data);
  List<Map<String, dynamic>> get groups =>
      (toJson()['groups'] as List).cast<Map<String, dynamic>>();

  FleetLedger apply(
    String action,
    Map<String, dynamic> p,
    Actor actor,
    DateTime now,
    String cid,
    List<Map<String, dynamic>> vehicles,
  ) {
    if (!actor.active || !actor.isOffice) {
      throw const RuleException('Se requiere permiso de oficina');
    }
    if (p['revision'] != revision) {
      throw const RuleException('La flota ha cambiado. Actualiza y revisa');
    }
    final id = requiredText(p['id'], 'Flota', max: 100);
    final reason = requiredText(p['reason'], 'Motivo');
    final d = toJson(), rows = d['groups'] as List;
    final old = rows.where((x) => x['id'] == id).firstOrNull;
    final event = {
      'id': cid,
      'kind': action,
      'actorId': actor.id,
      'at': now.toUtc().toIso8601String(),
      'reason': reason,
    };
    Map<String, dynamic> value;
    if (action == 'fleet_group') {
      _keys(p, {'id', 'revision', 'name', 'organization', 'reason'});
      if (old?['status'] == 'archived') {
        throw const RuleException(
          'Crea una flota nueva para conservar la archivada',
        );
      }
      final version = {
        'name': requiredText(p['name'], 'Nombre de la flota', max: 300),
        'organization': requiredText(
          p['organization'],
          'Empresa o responsable',
          max: 300,
        ),
        'actorId': actor.id,
        'at': now.toUtc().toIso8601String(),
      };
      value = {
        'id': id,
        ...version,
        'status': 'active',
        'memberships': [...?old?['memberships']],
        'versions': [...?old?['versions'], version],
        'events': [...?old?['events'], event],
      };
    } else {
      if (old == null || old['status'] != 'active') {
        throw const RuleException('Selecciona una flota activa');
      }
      value = cloneMap(old);
      if (action == 'fleet_attach') {
        _keys(p, {
          'id',
          'revision',
          'membershipId',
          'vehicleId',
          'ownerId',
          'reference',
          'evidence',
          'reason',
        });
        final mid = requiredText(p['membershipId'], 'Vínculo', max: 100);
        if (rows.any(
          (g) => (g['memberships'] as List).any((m) => m['id'] == mid),
        )) {
          throw const RuleException('Identificador de vínculo ya utilizado');
        }
        final v = vehicles.where((v) => v['id'] == p['vehicleId']).firstOrNull;
        if (v == null || v['ownerId'] != p['ownerId']) {
          throw const RuleException(
            'Revisa el vehículo y su propietario actual',
          );
        }
        if (rows.any(
          (g) =>
              g['status'] == 'active' &&
              (g['memberships'] as List).any(
                (m) => m['status'] == 'active' && m['vehicleId'] == v['id'],
              ),
        )) {
          throw const RuleException(
            'Retira el vínculo anterior antes de incorporar el vehículo',
          );
        }
        (value['memberships'] as List).add({
          'id': mid,
          'vehicleId': v['id'],
          'ownerId': v['ownerId'],
          'ownerSnapshot': cloneMap(v['owner']),
          'reference': requiredText(
            p['reference'],
            'Referencia del vehículo',
            max: 100,
          ),
          'evidence': requiredText(
            p['evidence'],
            'Comprobación de pertenencia',
            max: 2000,
          ),
          'status': 'active',
          'addedBy': actor.id,
          'addedAt': now.toUtc().toIso8601String(),
          'removedBy': null,
          'removedAt': null,
        });
      } else if (action == 'fleet_detach') {
        _keys(p, {'id', 'revision', 'membershipId', 'reason'});
        final m = (value['memberships'] as List)
            .where((m) => m['id'] == p['membershipId'])
            .firstOrNull;
        if (m == null || m['status'] != 'active') {
          throw const RuleException('Selecciona un vínculo activo');
        }
        m['status'] = 'removed';
        m['removedBy'] = actor.id;
        m['removedAt'] = now.toUtc().toIso8601String();
      } else if (action == 'fleet_archive') {
        _keys(p, {'id', 'revision', 'reason'});
        if ((value['memberships'] as List).any(
          (m) => m['status'] == 'active',
        )) {
          throw const RuleException(
            'Retira los vehículos antes de archivar la flota',
          );
        }
        value['status'] = 'archived';
      } else {
        throw const RuleException('Acción de flota desconocida');
      }
      value['events'] = [...value['events'], event];
    }
    rows.removeWhere((x) => x['id'] == id);
    rows.add(value);
    d['revision'] = revision + 1;
    return FleetLedger(d);
  }

  static void _keys(Map<String, dynamic> p, Set<String> keys) {
    if (p.keys.any((k) => !keys.contains(k))) {
      throw const RuleException('Datos de flota no admitidos');
    }
  }
}

void applyFleetCommand(
  WorkshopState state,
  String id,
  String action,
  Map<String, dynamic> p,
  Actor actor,
  DateTime at,
) {
  if (!actor.active || !actor.isOffice) {
    throw const RuleException('Se requiere permiso de oficina');
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
  final result = FleetLedger(
    state.configuration['fleets'],
  ).apply(action, p, actor, at, id, vehicleProfiles(state));
  state.configuration['fleets'] = result.toJson();
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

Map<String, dynamic> visibleFleets(WorkshopState s, Actor actor) =>
    actor.isOffice
    ? FleetLedger(s.configuration['fleets']).toJson()
    : {'revision': 0, 'groups': []};

bool fleetMembershipCurrent(Map<String, dynamic> m, Map<String, dynamic>? v) =>
    m['status'] == 'active' && v != null && v['ownerId'] == m['ownerId'];
