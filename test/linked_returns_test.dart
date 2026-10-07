import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/simulation.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/models.dart';

void main() {
  final actor = demoActors.firstWhere((a) => a.role == Role.admin);
  final at = DateTime.utc(2026, 10, 7);
  WorkshopState base() {
    final s = demoState();
    s.orders['o-1048']!.data.addAll({
      'status': 'delivered',
      'document': {'totalCents': 12345, 'clientSnapshot': 'Original owner'},
    });
    return s;
  }

  Map<String, dynamic> reception(WorkshopState s) {
    final o = s.orders['o-1048']!;
    return {
      'plate': o.plate,
      'country': o.data['country'],
      'vin': o.data['vin'],
      'vehicle': o.vehicle,
      'engine': o.data['engine'],
      'client': o.client,
      'phone': o.data['phone'],
      'km': o.data['km'],
      'symptom': 'Original new symptom',
      'tasks': [
        {
          'id': 'new-task',
          'title': 'New diagnosis',
          'assignees': ['tech-alex'],
          'estimateMinutes': 30,
        },
      ],
      'returnLink': {
        'sourceOrderId': o.id,
        'classification': 'warranty',
        'reason': 'Office reviews return',
      },
    };
  }

  Operation operation(
    String id,
    String kind,
    Map<String, dynamic> p, {
    int revision = 0,
    String? actorId,
  }) => Operation(
    id: id,
    orderId: 'new-order',
    kind: kind,
    actorId: actorId ?? actor.id,
    baseRevision: revision,
    at: at,
    payload: p,
  );
  test(
    'Linked return keeps original note, fresh tasks and human classification',
    () {
      final s = base(), original = cloneMap(base().orders['o-1048']!.data);
      s.apply(operation('receive', 'receive', reception(s)), actor);
      expect(s.orders['o-1048']!.data, original);
      final o = s.orders['new-order']!;
      expect(o.data['returnHistory'].single['classification'], 'warranty');
      expect(o.tasks.single['authorized'], false);
      expect(o.tasks.single['approvedCents'], 0);
      expect(o.issued, false);
      expect(o.parts, isEmpty);
    },
  );
  test(
    'Reclassification appends evidence and refuses stale revisions or another original',
    () {
      final s = base();
      s.apply(operation('receive', 'receive', reception(s)), actor);
      final p = {
        'sourceOrderId': 'o-1048',
        'classification': 'different',
        'reason': 'Measurement shows another cause',
      };
      s.apply(operation('classify', 'return_classify', p), actor);
      final history = s.orders['new-order']!.data['returnHistory'];
      expect(history.length, 2);
      expect(history.first['classification'], 'warranty');
      expect(
        () => s.apply(operation('stale', 'return_classify', p), actor),
        throwsA(isA<RuleException>()),
      );
      expect(
        () => s.apply(
          operation('changed', 'return_classify', {
            ...p,
            'sourceOrderId': 'o-1045',
          }, revision: 1),
          actor,
        ),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test('Foreign vehicle, unknown source and active repair are refused', () {
    for (final change in ['foreign', 'unknown', 'active']) {
      final s = base(), p = reception(base());
      if (change == 'foreign') {
        p['plate'] = '0000FIC';
        p['vin'] = 'OTHER-VIN';
      }
      if (change == 'unknown') {
        p['returnLink']['sourceOrderId'] = 'missing';
      }
      if (change == 'active') {
        s.orders['o-1048']!.data.remove('document');
        s.orders['o-1048']!.data['status'] = 'repair';
      }
      expect(
        () => s.copy().apply(operation('receive', 'receive', p), actor),
        throwsA(isA<RuleException>()),
      );
      expect(s.orders.containsKey('new-order'), false);
    }
  });
  test(
    'Operators cannot classify and their snapshots omit personal classification evidence',
    () {
      final s = base();
      s.apply(operation('receive', 'receive', reception(s)), actor);
      final tech = demoActors[0];
      expect(
        () => s.apply(
          operation('classify', 'return_classify', {
            'sourceOrderId': 'o-1048',
            'classification': 'warranty',
            'reason': 'Private evidence',
          }, actorId: tech.id),
          tech,
        ),
        throwsA(isA<RuleException>()),
      );
      final server = SimulatedWorkshop()..state = s;
      final newOrder = (server.snapshot(tech, 'tech-device')['orders'] as List)
          .firstWhere((o) => o['id'] == 'new-order');
      expect(newOrder.containsKey('returnHistory'), false);
    },
  );
  test(
    'Serialization preserves original source and classification history',
    () {
      final s = base();
      s.apply(operation('receive', 'receive', reception(s)), actor);
      final restored = WorkshopState.fromJson(s.toJson());
      expect(
        restored.orders['new-order']!.data['returnHistory'],
        s.orders['new-order']!.data['returnHistory'],
      );
      expect(
        restored.orders['o-1048']!.data['document'],
        s.orders['o-1048']!.data['document'],
      );
    },
  );
}
