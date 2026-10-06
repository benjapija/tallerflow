import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/models.dart';
import 'package:tallerflow/domain/vehicles.dart';

void main() {
  final office = demoActors[2];
  final now = DateTime.utc(2026, 10, 6);
  test(
    'Registration aliases retain technical identity and immutable issued data',
    () {
      final s = demoState();
      final o = s.orders['o-1048']!;
      o.data['document'] = {
        'clientSnapshot': o.client,
        'plateSnapshot': o.plate,
      };
      final original = cloneMap(o.data);
      final v = vehicleProfiles(
        s,
      ).firstWhere((v) => v['id'] == o.data['vehicleId']);
      final p = {
        'vehicleId': v['id'],
        'revision': 0,
        'change': 'registration',
        'plate': '9876 XYZ',
        'country': 'es',
        'vin': v['vin'],
        'reason': 'Document checked',
      };
      applyVehicleChange(s, 'change-1', p, office, now);
      applyVehicleChange(s, 'change-1', p, office, now);
      final saved = vehicleProfiles(s).firstWhere((p) => p['id'] == v['id']);
      expect(saved['revision'], 1);
      expect(saved['plate'], '9876XYZ');
      expect(saved['engine'], v['engine']);
      expect(vehicleMatches(saved, '48-21 lkr'), isTrue);
      expect(vehicleMatches(saved, '98-76 XYZ'), isTrue);
      expect(
        (saved['identifiers'] as List).where((i) => i['kind'] == 'plate'),
        hasLength(2),
      );
      expect(s.orders['o-1048']!.data, original);
      expect(
        () => applyVehicleChange(s, 'stale', p, office, now),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Owner transfer preserves old recipient and reception uses the new identity',
    () {
      final s = demoState(), old = cloneMap(demoState().orders['o-1048']!.data);
      final v = vehicleProfiles(s).first;
      applyVehicleChange(
        s,
        'owner-1',
        {
          'vehicleId': v['id'],
          'revision': 0,
          'change': 'owner',
          'ownerId': 'new-recipient',
          'name': 'New fictional owner',
          'phone': '600000000',
          'reason': 'Transfer checked',
        },
        office,
        now,
      );
      expect(s.orders['o-1048']!.data, old);
      final payload = {
        ...old,
        'client': 'New fictional owner',
        'phone': '600000000',
        'tasks': [
          {
            'id': 'new-task',
            'title': 'Inspection',
            'assignees': ['tech-alex'],
            'estimateMinutes': 30,
          },
        ],
      };
      s.apply(
        Operation(
          id: 'receive-2',
          orderId: 'new-order',
          kind: 'receive',
          actorId: office.id,
          baseRevision: 0,
          at: now,
          payload: payload,
        ),
        office,
      );
      expect(s.orders['new-order']!.data['vehicleId'], v['id']);
      expect(s.orders['new-order']!.data['ownerId'], 'new-recipient');
      expect(s.orders['new-order']!.data['document'], isNull);
      expect(
        () => s.copy().apply(
          Operation(
            id: 'old-receive',
            orderId: 'other-order',
            kind: 'receive',
            actorId: office.id,
            baseRevision: 0,
            at: now,
            payload: {
              ...payload,
              'client': old['client'],
              'phone': old['phone'],
            },
          ),
          office,
        ),
        throwsA(isA<RuleException>()),
      );
      expect(
        () => applyVehicleChange(
          s,
          'reused-recipient',
          {
            'vehicleId': v['id'],
            'revision': 2,
            'change': 'owner',
            'ownerId': old['id'],
            'name': 'Impersonation',
            'reason': 'Invalid',
          },
          office,
          now,
        ),
        throwsA(isA<RuleException>()),
      );
      expect(
        WorkshopState.fromJson(s.toJson()).configuration['vehicleProfiles'],
        s.configuration['vehicleProfiles'],
      );
    },
  );
  test(
    'Technical history omits personal documents, prices and authorization evidence',
    () {
      final o = demoState().orders['o-1048']!;
      o.data['document'] = {'clientSnapshot': o.client};
      final h = technicalHistoryEntry(o);
      expect(h.containsKey('client'), isFalse);
      expect(h.containsKey('phone'), isFalse);
      expect(h.containsKey('document'), isFalse);
      expect((h['tasks'] as List).first.containsKey('authorization'), isFalse);
      expect((h['tasks'] as List).first.containsKey('rateCents'), isFalse);
      expect(h['symptom'], o.symptom);
    },
  );
  test(
    'Identifier collisions and technician changes are refused before mutation',
    () {
      final s = demoState(), v = vehicleProfiles(demoState()).first;
      final p = {
        'vehicleId': v['id'],
        'revision': 0,
        'change': 'registration',
        'plate': s.orders['o-1047']!.plate,
        'country': 'ES',
        'vin': v['vin'],
        'reason': 'Wrong car',
      };
      expect(
        () => applyVehicleChange(s.copy(), 'collision', p, office, now),
        throwsA(isA<RuleException>()),
      );
      expect(
        () => applyVehicleChange(s.copy(), 'tech', p, demoActors[0], now),
        throwsA(isA<RuleException>()),
      );
      expect(s.audit, isEmpty);
    },
  );
}
