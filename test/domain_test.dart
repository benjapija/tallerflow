import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/models.dart';

void main() {
  late WorkshopState state;
  final time = DateTime.utc(2026, 10, 6, 10);
  var sequence = 0;
  void apply(
    String kind,
    Map<String, dynamic> p, {
    Actor? actor,
    DateTime? at,
    String id = 'o-1048',
    String? opId,
  }) {
    final a = actor ?? demoActors[0];
    state.apply(
      Operation(
        id: opId ?? 'e-${sequence++}',
        orderId: id,
        kind: kind,
        actorId: a.id,
        baseRevision: state.orders[id]?.revision ?? 0,
        at: at ?? time,
        payload: p,
      ),
      a,
    );
  }

  setUp(() {
    state = demoState();
    sequence = 0;
  });
  test('Plate normalization preserves country and stable vehicle identity', () {
    expect(normalizePlate('48-21 lkr'), '4821LKR');
    final data = cloneMap(state.orders['o-1048']!.data)
      ..['plate'] = '4821-LKR'
      ..['tasks'] = [demoTask('new', 'Diagnosis', authorized: false)];
    apply('receive', data, actor: demoActors[2], id: 'new-order');
    expect(state.orders['new-order']!.data['vehicleId'], 'vehicle-0');
  });
  test('Two technicians may work; each user has only one active timer', () {
    state.orders['o-1048']!.tasks.first['assignees'] = [
      'tech-alex',
      'tech-lucia',
    ];
    apply('start', {'taskId': 't-1'});
    apply('start', {'taskId': 't-1'}, actor: demoActors[1]);
    expect(state.orders['o-1048']!.times.length, 2);
    expect(
      () => apply('start', {'taskId': 't-2'}),
      throwsA(isA<RuleException>()),
    );
    apply('stop', {
      'sessionId': 'e-0',
    }, at: time.add(const Duration(minutes: 30)));
    expect(state.orders['o-1048']!.billableMinutes, 0);
    expect(
      state.orders['o-1048']!.workedSeconds(
        time.add(const Duration(minutes: 30)),
      ),
      3600,
    );
  });
  test(
    'Unassigned technician and unauthorized extension cannot record work',
    () {
      expect(
        () => apply('start', {'taskId': 't-1'}, actor: demoActors[1]),
        throwsA(isA<RuleException>()),
      );
      expect(
        () => apply('start', {'taskId': 't-4'}, id: 'o-1047'),
        throwsA(isA<RuleException>()),
      );
      expect(calculateNote(state.orders['o-1047']!).lines.length, 1);
      expect(
        () => apply(
          'billable',
          {'taskId': 't-4', 'minutes': 60, 'reason': 'test'},
          id: 'o-1047',
          actor: demoActors[2],
        ),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test('Retry is idempotent and a manual entry cannot overlap a timer', () {
    apply('start', {'taskId': 't-1'}, opId: 'timer-1');
    apply('start', {'taskId': 't-1'}, opId: 'timer-1');
    expect(state.orders['o-1048']!.times.length, 1);
    apply('stop', {
      'sessionId': 'timer-1',
    }, at: time.add(const Duration(minutes: 20)));
    expect(
      () => apply('manual_time', {
        'taskId': 't-1',
        'start': time.toIso8601String(),
        'end': time.add(const Duration(minutes: 15)).toIso8601String(),
        'reason': 'forgot timer',
      }, at: time.add(const Duration(hours: 1))),
      throwsA(isA<RuleException>()),
    );
  });
  test(
    'Decimal quantities, frozen prices and partial returns preserve stock',
    () {
      apply('part', {
        'taskId': 't-1',
        'itemId': 'p-3',
        'kind': 'reserve',
        'quantityMilli': 4500,
      });
      expect(state.stock('p-3'), 48000);
      apply('part', {
        'taskId': 't-1',
        'itemId': 'p-3',
        'kind': 'consume',
        'quantityMilli': parseQuantity('4,5'),
      }, opId: 'consume');
      apply('part', {
        'taskId': 't-1',
        'itemId': 'p-3',
        'kind': 'consume',
        'quantityMilli': 4500,
      }, opId: 'consume');
      expect(state.stock('p-3'), 43500);
      apply('return', {'sourceId': 'consume', 'quantityMilli': 500});
      expect(state.stock('p-3'), 44000);
      expect(calculateNote(state.orders['o-1048']!).netCents, 5800);
      expect(
        () => apply('return', {'sourceId': 'consume', 'quantityMilli': 4500}),
        throwsA(isA<RuleException>()),
      );
      expect(parseQuantity('0,125'), 125);
      expect(() => parseQuantity('0.1234'), throwsFormatException);
      expect(state.orders['o-1048']!.parts[1]['priceCents'], 1450);
    },
  );
  test(
    'Money uses exact integer arithmetic and per-line half-up tax rounding',
    () {
      apply('billable', {
        'taskId': 't-1',
        'minutes': 7,
        'reason': 'Reviewed',
      }, actor: demoActors[2]);
      final total = calculateNote(state.orders['o-1048']!);
      expect(total.netCents, 560);
      expect(total.taxCents, 118);
      expect(total.totalCents, 678);
      expect(roundRatio(5, 2), 3);
    },
  );
  test(
    'Close blocks active work, pending uploads, missing quality and authorization cap',
    () {
      final o = state.orders['o-1048']!;
      expect(
        closeIssues(o, pending: 1, connected: false, conflict: false).length,
        greaterThanOrEqualTo(4),
      );
      apply('billable', {
        'taskId': 't-1',
        'minutes': 600,
        'reason': 'Reviewed',
      }, actor: demoActors[2]);
      expect(
        closeIssues(
          o,
          pending: 0,
          connected: true,
          conflict: false,
        ).any((i) => i.contains('supera')),
        true,
      );
    },
  );
  test('Issued note remains unchanged when late data arrives', () {
    apply(
      'issue',
      {'pending': 0, 'connected': true, 'conflict': false},
      actor: demoActors[2],
      id: 'o-1045',
    );
    final before = cloneMap(state.orders['o-1045']!.data['document']);
    final op = Operation(
      id: 'late',
      orderId: 'o-1045',
      kind: 'note',
      actorId: demoActors[0].id,
      baseRevision: 0,
      at: time,
      payload: {'text': 'Additional observation'},
    );
    state.apply(op, demoActors[0], replay: true);
    expect(state.orders['o-1045']!.data['document'], before);
    expect(state.incidents.length, 1);
    expect(
      () => state.apply(
        Operation(
          id: 'edit',
          orderId: 'o-1045',
          kind: 'billable',
          actorId: demoActors[2].id,
          baseRevision: 0,
          at: time,
          payload: {'taskId': 't-6', 'minutes': 50, 'reason': 'edit'},
        ),
        demoActors[2],
      ),
      throwsA(isA<RuleException>()),
    );
  });
  test(
    'Reopening restores an active timer and worked time does not become billed',
    () {
      apply('start', {'taskId': 't-1'});
      final restored = WorkshopState.fromJson(cloneMap(state.toJson()));
      expect(
        restored.orders['o-1048']!.workedSeconds(
          time.add(const Duration(hours: 2)),
        ),
        7200,
      );
      expect(restored.orders['o-1048']!.billableMinutes, 0);
    },
  );
}
