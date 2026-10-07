import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/maintenance.dart';
import 'package:tallerflow/domain/models.dart';
import 'package:tallerflow/domain/vehicles.dart';

final vehicleId = demoState().orders['o-1048']!.data['vehicleId'] as String;
final office = demoActors[2],
    tech = demoActors.first,
    now = DateTime.utc(2026, 10, 7, 12);
Map<String, dynamic> plan(int revision, {String id = 'plan'}) => {
  'id': id,
  'revision': revision,
  'vehicleId': vehicleId,
  'title': 'Cambio de aceite',
  'source': 'Criterio manual ficticio revisado por oficina',
  'zone': 'Europe/Madrid',
  'dueDate': '2026-10-08',
  'dueKm': 130000,
  'intervalMonths': 12,
  'intervalKm': 15000,
  'reason': 'Previsión ficticia',
};
Map<String, dynamic> complete(
  int revision, {
  String at = '2026-10-07T10:00:00Z',
  int km = 129000,
}) => {
  'id': 'plan',
  'revision': revision,
  'performedAt': at,
  'km': km,
  'orderId': 'o-1048',
  'evidence': 'Intervención ficticia comprobada',
  'reason': 'Registro manual',
};
void apply(
  WorkshopState s,
  String action,
  Map<String, dynamic> p, {
  String? cid,
  Actor? actor,
}) => applyMaintenanceCommand(
  s,
  cid ?? 'care${s.audit.length}',
  action,
  p,
  actor ?? office,
  now,
);
void main() {
  test(
    'Office creates date/mileage plan with explicit criteria and immutable versions',
    () {
      final s = demoState();
      apply(s, 'care_plan', plan(0));
      apply(s, 'care_plan', {...plan(1), 'title': 'Aceite y filtro'});
      final p = MaintenanceLedger(s.configuration['maintenance']).plans.single;
      expect(p['versions'], hasLength(2));
      expect(p['versions'][0]['title'], 'Cambio de aceite');
      expect(p['source'], contains('manual'));
      expect(
        () => apply(s, 'care_plan', {
          ...plan(2),
          'vehicleId': demoState().orders['o-1047']!.data['vehicleId'],
        }),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test('First due threshold triggers review; unknown mileage is explicit', () {
    final p = plan(0)..['status'] = 'active';
    expect(
      maintenanceStatus(p, DateTime.utc(2026, 10, 8), 100),
      'Revisar mantenimiento',
    );
    expect(
      maintenanceStatus(p, DateTime.utc(2026, 10, 7), 130000),
      'Revisar mantenimiento',
    );
    expect(
      maintenanceStatus(p, DateTime.utc(2026, 10, 7), null),
      'Kilometraje por comprobar',
    );
    expect(maintenanceStatus(p, DateTime.utc(2026, 10, 7), 129000), 'Previsto');
  });
  test(
    'Completion records evidence, updates known mileage and next due, preserving issued notes',
    () {
      final s = demoState();
      final before = cloneMap(s.orders['o-1048']!.data);
      s.orders['o-1048']!.data['document'] = {
        'type': 'Immutable fictional note',
        'totalCents': 3300,
      };
      apply(s, 'care_plan', plan(0));
      apply(s, 'care_complete', complete(1));
      final p = MaintenanceLedger(s.configuration['maintenance']).plans.single;
      expect(p['dueDate'], '2027-10-07');
      expect(p['dueKm'], 144000);
      expect(p['completions'][0]['performedDate'], '2026-10-07');
      expect(p['completions'][0]['dueKm'], 130000);
      expect(
        vehicleProfiles(s).firstWhere((v) => v['id'] == vehicleId)['km'],
        129000,
      );
      expect(s.orders['o-1048']!.data['document']['totalCents'], 3300);
      expect(s.orders['o-1048']!.data['tasks'], before['tasks']);
    },
  );
  test(
    'Month boundaries and local midnight are retained across summer time and leap years',
    () {
      expect(addMaintenanceMonths(DateTime.utc(2026, 1, 31), 1), '2026-02-28');
      expect(addMaintenanceMonths(DateTime.utc(2028, 1, 31), 1), '2028-02-29');
      final s = demoState();
      apply(s, 'care_plan', {...plan(0), 'intervalMonths': 1});
      apply(s, 'care_complete', complete(1, at: '2026-09-30T22:30:00Z'));
      final p = MaintenanceLedger(s.configuration['maintenance']).plans.single;
      expect(p['completions'][0]['performedDate'], '2026-10-01');
      expect(p['dueDate'], '2026-11-01');
    },
  );
  test(
    'Completed single plans and paused plans keep evidence and require a new plan',
    () {
      final s = demoState();
      apply(s, 'care_plan', {
        ...plan(0),
        'intervalMonths': null,
        'intervalKm': null,
      });
      apply(s, 'care_complete', complete(1));
      expect(
        MaintenanceLedger(
          s.configuration['maintenance'],
        ).plans.single['status'],
        'completed',
      );
      expect(
        () => apply(s, 'care_plan', plan(2)),
        throwsA(isA<RuleException>()),
      );
      apply(s, 'care_plan', plan(2, id: 'other'));
      apply(s, 'care_pause', {
        'id': 'other',
        'revision': 3,
        'reason': 'Seguimiento pausado',
      });
      expect(
        MaintenanceLedger(s.configuration['maintenance']).plans.last['status'],
        'paused',
      );
    },
  );
  test(
    'Role, stale revision, malformed dates and missing thresholds are rejected atomically',
    () {
      final s = demoState(), before = s.toJson();
      for (final p in [
        {...plan(0), 'dueDate': null, 'dueKm': null},
        {...plan(0), 'dueDate': '2026-02-30'},
        {...plan(0), 'dueDate': null},
        {...plan(0), 'source': ''},
        {...plan(0), 'vehicleId': 'foreign'},
        {...plan(0), 'revision': 1},
      ]) {
        expect(() => apply(s, 'care_plan', p), throwsA(isA<RuleException>()));
        expect(s.toJson(), before);
      }
      expect(
        () => apply(s, 'care_plan', plan(0), actor: tech),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Completion cannot be future, repeat same visit, reduce mileage or reference another vehicle',
    () {
      final s = demoState();
      apply(s, 'care_plan', plan(0));
      for (final p in [
        complete(1, at: '2026-10-08T10:00:00Z'),
        {...complete(1), 'orderId': 'o-1047'},
        {...complete(1), 'evidence': ''},
      ]) {
        expect(
          () => apply(s, 'care_complete', p),
          throwsA(isA<RuleException>()),
        );
      }
      apply(s, 'care_complete', complete(1));
      for (final p in [
        complete(2),
        complete(2, at: '2026-10-06T10:00:00Z'),
        complete(2, at: '2026-10-07T11:00:00Z', km: 128000),
      ]) {
        expect(
          () => apply(s, 'care_complete', p),
          throwsA(isA<RuleException>()),
        );
      }
    },
  );
  test(
    'Restart and lost reply preserve completion identity; owner changes do not transfer documents',
    () {
      final s = demoState();
      apply(s, 'care_plan', plan(0));
      final p = complete(1);
      apply(s, 'care_complete', p, cid: 'stable');
      final copy = WorkshopState.fromJson(s.toJson());
      apply(copy, 'care_complete', p, cid: 'stable');
      expect(
        MaintenanceLedger(
          copy.configuration['maintenance'],
        ).plans.single['completions'],
        hasLength(1),
      );
      expect(
        () => apply(copy, 'care_complete', {...p, 'km': 129001}, cid: 'stable'),
        throwsA(isA<RuleException>()),
      );
      final profiles = vehicleProfiles(copy);
      profiles.firstWhere((v) => v['id'] == vehicleId)['ownerId'] = 'new-owner';
      profiles.firstWhere((v) => v['id'] == vehicleId)['plate'] = 'NEWPLATE';
      copy.configuration['vehicleProfiles'] = profiles;
      expect(
        MaintenanceLedger(
          copy.configuration['maintenance'],
        ).plans.single['vehicleId'],
        vehicleId,
      );
      final visible = visibleMaintenance(copy, tech);
      expect(visible['plans'][0]['events'], isEmpty);
      expect(visible['plans'][0]['versions'], isEmpty);
      expect(visible['plans'][0]['completions'][0]['orderId'], 'o-1048');
    },
  );
}
