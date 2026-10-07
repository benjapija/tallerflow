import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/models.dart';
import 'package:tallerflow/domain/planning.dart';
import 'package:tallerflow/domain/planning_time.dart';

final admin = demoActors.last, office = demoActors[2], tech = demoActors.first;
final now = DateTime.utc(2026, 10, 7);
Map<String, dynamic> resource(int rev, {bool active = true}) => {
  'id': 'lift',
  'revision': rev,
  'name': 'Elevador 1',
  'active': active,
  'reason': 'Disponibilidad ficticia',
};
Map<String, dynamic> booking(
  int rev, {
  String id = 'b1',
  String start = '2026-10-08T09:00:00+02:00',
  String end = '2026-10-08T10:00:00+02:00',
  List<String>? members,
  String? lift = 'lift',
}) => {
  'id': id,
  'revision': rev,
  'title': 'Cita ficticia',
  'start': start,
  'end': end,
  'kind': 'appointment',
  'assignees': members ?? [tech.id],
  'liftId': lift,
  'orderId': 'o-1048',
  'reason': 'Reserva comprobada',
};
void apply(
  WorkshopState s,
  String action,
  Map<String, dynamic> p, {
  Actor? actor,
  String? cid,
}) => applyPlanningCommand(
  s,
  cid ?? 'c${s.audit.length}',
  action,
  p,
  actor ?? admin,
  now,
);
WorkshopState fixture() {
  final s = demoState();
  apply(s, 'schedule_resource', resource(0));
  return s;
}

void main() {
  test(
    'Office books multiple technicians and lift without changing repair or prices',
    () {
      final s = fixture(), before = cloneMap(s.orders['o-1048']!.data);
      apply(
        s,
        'schedule_booking',
        booking(1, members: [tech.id, demoActors[1].id]),
        actor: office,
      );
      final b = PlanningLedger(s.configuration['planning']).bookings.single;
      expect(b['start'], '2026-10-08T07:00:00.000Z');
      expect(b['assignees'], hasLength(2));
      expect(s.orders['o-1048']!.data, before);
    },
  );
  test(
    'Overlaps by technician or lift fail atomically; touching intervals work',
    () {
      final s = fixture();
      apply(s, 'schedule_booking', booking(1));
      final before = s.toJson();
      for (final p in [
        booking(2, id: 'b2', members: [demoActors[1].id]),
        booking(2, id: 'b2', lift: null),
        booking(2, id: 'b2', members: [demoActors[1].id, tech.id], lift: null),
      ]) {
        expect(
          () => apply(s, 'schedule_booking', p),
          throwsA(isA<RuleException>()),
        );
        expect(s.toJson(), before);
      }
      apply(
        s,
        'schedule_booking',
        booking(
          2,
          id: 'b2',
          start: '2026-10-08T10:00:00+02:00',
          end: '2026-10-08T11:00:00+02:00',
        ),
      );
      apply(
        s,
        'schedule_booking',
        booking(3, id: 'b3', members: [demoActors[1].id], lift: null),
      );
    },
  );
  test('Reprogramming and cancellation keep original versions and history', () {
    final s = fixture();
    apply(s, 'schedule_booking', booking(1));
    apply(
      s,
      'schedule_booking',
      booking(
        2,
        start: '2026-10-08T11:00:00+02:00',
        end: '2026-10-08T12:00:00+02:00',
      ),
    );
    apply(s, 'schedule_status', {
      'id': 'b1',
      'revision': 3,
      'status': 'cancelled',
      'reason': 'Cliente cancela',
    });
    final b = PlanningLedger(s.configuration['planning']).bookings.single;
    expect(b['versions'], hasLength(2));
    expect(b['versions'][0]['kind'], 'appointment');
    expect(b['versions'][0]['start'], '2026-10-08T07:00:00.000Z');
    expect(b['events'], hasLength(3));
    expect(
      () => apply(s, 'schedule_booking', booking(4)),
      throwsA(isA<RuleException>()),
    );
    apply(s, 'schedule_booking', booking(4, id: 'replacement'));
    apply(s, 'schedule_status', {
      'id': 'replacement',
      'revision': 5,
      'status': 'done',
      'reason': 'Cita atendida',
    });
    expect(
      PlanningLedger(s.configuration['planning']).bookings.last['status'],
      'done',
    );
  });
  test(
    'Roles, foreign assignments, inactive resources and stale revisions fail',
    () {
      final s = fixture();
      for (final p in [
        booking(0),
        booking(1, members: ['foreign']),
        booking(1, members: [office.id]),
        booking(1, members: [tech.id, tech.id]),
        {...booking(1), 'orderId': 'foreign'},
        booking(1, lift: 'foreign'),
        booking(1, members: [], lift: null),
      ]) {
        expect(
          () => apply(s, 'schedule_booking', p),
          throwsA(isA<RuleException>()),
        );
      }
      expect(
        () => apply(s, 'schedule_booking', booking(1), actor: tech),
        throwsA(isA<RuleException>()),
      );
      expect(
        () => apply(s, 'schedule_resource', resource(1), actor: office),
        throwsA(isA<RuleException>()),
      );
      apply(s, 'schedule_booking', booking(1));
      expect(
        () => apply(s, 'schedule_resource', resource(2, active: false)),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test('Unavailability blocks slots and cannot link a repair', () {
    final s = fixture();
    apply(s, 'schedule_booking', {
      ...booking(1),
      'kind': 'unavailable',
      'orderId': null,
    });
    expect(
      () => apply(s, 'schedule_booking', booking(2, id: 'other')),
      throwsA(isA<RuleException>()),
    );
    expect(
      () => apply(fixture(), 'schedule_booking', {
        ...booking(1),
        'kind': 'unavailable',
      }),
      throwsA(isA<RuleException>()),
    );
  });
  test('Lost reply and persistence roundtrip cannot duplicate reservation', () {
    final s = fixture(), p = booking(1);
    apply(s, 'schedule_booking', p, cid: 'stable-command');
    final restored = WorkshopState.fromJson(s.toJson());
    apply(restored, 'schedule_booking', p, cid: 'stable-command');
    expect(
      PlanningLedger(restored.configuration['planning']).bookings,
      hasLength(1),
    );
    expect(
      () => apply(restored, 'schedule_booking', {
        ...p,
        'title': 'Changed',
      }, cid: 'stable-command'),
      throwsA(isA<RuleException>()),
    );
  });
  test(
    'Absolute dates reject missing zone, invalid days and excessive intervals',
    () {
      for (final input in [
        '2026-10-08T09:00',
        '2026-02-30T09:00:00Z',
        '2026-10-08T24:00:00Z',
        '2026-10-08T09:60:00Z',
        '2026-10-08T09:00:00+20:00',
      ]) {
        expect(() => planningDate(input), throwsA(isA<RuleException>()));
      }
      expect(
        () => apply(
          fixture(),
          'schedule_booking',
          booking(1, end: '2026-10-08T08:00:00+02:00'),
        ),
        throwsA(isA<RuleException>()),
      );
      expect(
        () => apply(
          fixture(),
          'schedule_booking',
          booking(1, end: '2026-10-16T10:00:00+02:00'),
        ),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Spanish zones handle missing and repeated daylight time independently of device',
    () {
      expect(
        PlanningTime.parse('08/10/2026 09:00', 'Europe/Madrid'),
        DateTime.utc(2026, 10, 8, 7),
      );
      expect(
        PlanningTime.parse('08/10/2026 09:00', 'Atlantic/Canary'),
        DateTime.utc(2026, 10, 8, 8),
      );
      expect(
        () => PlanningTime.parse('29/03/2026 02:30', 'Europe/Madrid'),
        throwsA(isA<RuleException>()),
      );
      expect(
        () => PlanningTime.parse('25/10/2026 02:30', 'Europe/Madrid'),
        throwsA(isA<RuleException>()),
      );
      expect(
        PlanningTime.parse(
          '25/10/2026 02:30',
          'Europe/Madrid',
          fold: 'second',
        ).difference(
          PlanningTime.parse(
            '25/10/2026 02:30',
            'Europe/Madrid',
            fold: 'first',
          ),
        ),
        const Duration(hours: 1),
      );
      expect(
        () => PlanningTime.parse('31/02/2026 09:00', 'Europe/Madrid'),
        throwsA(isA<RuleException>()),
      );
    },
  );
}
