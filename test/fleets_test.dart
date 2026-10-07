import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/domain/models.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/fleets.dart';
import 'package:tallerflow/domain/vehicles.dart';

final office = demoActors[2], now = DateTime.utc(2026, 10, 7, 12);
Map<String, dynamic> group(int rev, {String id = 'fleet'}) => {
  'id': id,
  'revision': rev,
  'name': 'Flota ficticia',
  'organization': 'Responsable comprobado',
  'reason': 'Criterio ficticio',
};
Map<String, dynamic> attach(
  WorkshopState s,
  int rev, {
  String id = 'fleet',
  String mid = 'membership',
}) {
  final v = vehicleProfiles(s).first;
  return {
    'id': id,
    'revision': rev,
    'membershipId': mid,
    'vehicleId': v['id'],
    'ownerId': v['ownerId'],
    'reference': 'Unidad ficticia 1',
    'evidence': 'Pertenencia comprobada manualmente',
    'reason': 'Prueba ficticia',
  };
}

void apply(
  WorkshopState s,
  String a,
  Map<String, dynamic> p, {
  String? cid,
  Actor? actor,
}) => applyFleetCommand(
  s,
  cid ?? 'cid${s.audit.length}',
  a,
  p,
  actor ?? office,
  now,
);
void main() {
  test(
    'Group versions and manual membership preserve original customer and repair documents',
    () {
      final s = demoState(),
          before = s.orders.values.map((o) => cloneMap(o.data)).toList();
      apply(s, 'fleet_group', group(0));
      apply(s, 'fleet_attach', attach(s, 1));
      apply(s, 'fleet_group', {...group(2), 'name': 'Nombre revisado'});
      final g = FleetLedger(s.configuration['fleets']).groups.single;
      expect(g['versions'], hasLength(2));
      expect(g['versions'][0]['name'], 'Flota ficticia');
      expect(g['memberships'][0]['evidence'], contains('comprobada'));
      expect(s.orders.values.map((o) => o.data).toList(), before);
    },
  );
  test(
    'Single active membership requires explicit removal before transfer',
    () {
      final s = demoState();
      apply(s, 'fleet_group', group(0));
      apply(s, 'fleet_group', group(1, id: 'other'));
      apply(s, 'fleet_attach', attach(s, 2));
      expect(
        () => apply(
          s,
          'fleet_attach',
          attach(s, 3, id: 'other', mid: 'othermember'),
        ),
        throwsA(isA<RuleException>()),
      );
      apply(s, 'fleet_detach', {
        'id': 'fleet',
        'revision': 3,
        'membershipId': 'membership',
        'reason': 'Transferencia comprobada',
      });
      apply(s, 'fleet_attach', attach(s, 4, id: 'other', mid: 'othermember'));
      expect(
        FleetLedger(s.configuration['fleets']).groups.firstWhere(
          (g) => g['id'] == 'fleet',
        )['memberships'][0]['status'],
        'removed',
      );
    },
  );
  test(
    'Owner changes require review and preserve original binding evidence',
    () {
      final s = demoState();
      apply(s, 'fleet_group', group(0));
      apply(s, 'fleet_attach', attach(s, 1));
      final m = FleetLedger(
        s.configuration['fleets'],
      ).groups.single['memberships'][0];
      final v = vehicleProfiles(s).first;
      expect(fleetMembershipCurrent(m, v), isTrue);
      final old = cloneMap(m['ownerSnapshot']);
      v['ownerId'] = 'new-owner';
      v['owner'] = {'name': 'Nuevo propietario'};
      expect(fleetMembershipCurrent(m, v), isFalse);
      expect(m['ownerSnapshot'], old);
      expect(
        () => apply(s, 'fleet_attach', {
          ...attach(s, 2, mid: 'second'),
          'ownerId': 'foreign',
        }),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Archiving requires removing vehicles and keeps history without reopening',
    () {
      final s = demoState();
      apply(s, 'fleet_group', group(0));
      apply(s, 'fleet_attach', attach(s, 1));
      final p = {'id': 'fleet', 'revision': 2, 'reason': 'Archivo comprobado'};
      expect(() => apply(s, 'fleet_archive', p), throwsA(isA<RuleException>()));
      apply(s, 'fleet_detach', {
        'id': 'fleet',
        'revision': 2,
        'membershipId': 'membership',
        'reason': 'Retirada comprobada',
      });
      apply(s, 'fleet_archive', {...p, 'revision': 3});
      expect(
        FleetLedger(s.configuration['fleets']).groups.single['events'],
        hasLength(4),
      );
      expect(
        () => apply(s, 'fleet_group', group(4)),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Roles, unknown vehicles, empty evidence and stale revisions fail atomically',
    () {
      final s = demoState();
      apply(s, 'fleet_group', group(0));
      final before = s.toJson();
      for (final p in [
        {...attach(s, 1), 'vehicleId': 'foreign'},
        {...attach(s, 1), 'evidence': ''},
        {...attach(s, 1), 'revision': 0},
      ]) {
        expect(
          () => apply(s, 'fleet_attach', p),
          throwsA(isA<RuleException>()),
        );
        expect(s.toJson(), before);
      }
      expect(
        () => apply(s, 'fleet_group', group(1), actor: demoActors.first),
        throwsA(isA<RuleException>()),
      );
      expect(visibleFleets(s, demoActors.first)['groups'], isEmpty);
    },
  );
  test(
    'Restart and lost committed reply keep identity and reject altered reuse',
    () {
      final s = demoState();
      final p = group(0);
      apply(s, 'fleet_group', p, cid: 'stable');
      final next = WorkshopState.fromJson(s.toJson());
      apply(next, 'fleet_group', p, cid: 'stable');
      expect(FleetLedger(next.configuration['fleets']).groups, hasLength(1));
      expect(
        () => apply(next, 'fleet_group', {
          ...p,
          'name': 'Changed',
        }, cid: 'stable'),
        throwsA(isA<RuleException>()),
      );
    },
  );
}
