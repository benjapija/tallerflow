import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/domain/diagnosis_notebook.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/models.dart';

void main() {
  final tech = demoActors[0],
      office = demoActors[2],
      at = DateTime.utc(2026, 10, 7);
  Operation op(
    String id,
    Map<String, dynamic> p, {
    String kind = 'diagnosis_add',
    int revision = 0,
    Actor? actor,
  }) => Operation(
    id: id,
    orderId: 'o-1048',
    kind: kind,
    actorId: (actor ?? tech).id,
    baseRevision: revision,
    at: at,
    payload: p,
  );
  Map<String, dynamic> observation([String stage = 'result']) => {
    'stage': stage,
    'text': 'Fictional measured voltage: 12.2 V',
    'context': 'Ignition off; fictitious meter',
    'dtcs': 'P0000',
    'source': 'Fictional authorized document, p. 1',
    'confirmed': false,
  };
  WorkshopState state() =>
      demoState()..orders['o-1048']!.tasks.first['assignees'] = [tech.id];
  test(
    'Measurements append without authorizing work, adding time or consuming parts',
    () {
      final s = state(), o = s.orders['o-1048']!;
      final before = cloneMap(o.data);
      s.apply(op('first', observation()), tech);
      s.apply(op('second', observation('hypothesis')), tech);
      expect(diagnosisEntries(o).length, 2);
      expect(o.tasks, before['tasks']);
      expect(o.parts, before['parts']);
      expect(o.times, before['times']);
    },
  );
  test(
    'Conclusions and verification require explicit human confirmation and forged fields fail',
    () {
      for (final p in [
        observation('conclusion'),
        observation('verification'),
        {...observation(), 'confirmed': 'yes'},
        {...observation(), 'amountCents': 1},
      ]) {
        expect(
          () => state().apply(op('bad', p), tech),
          throwsA(isA<RuleException>()),
        );
      }
      final s = state();
      s.apply(
        op('confirmed', {...observation('conclusion'), 'confirmed': true}),
        tech,
      );
      expect(diagnosisEntries(s.orders['o-1048']!).single['confirmed'], true);
    },
  );
  test(
    'Correction and withdrawal preserve original, require current revision and remain once',
    () {
      final s = state(), o = s.orders['o-1048']!;
      s.apply(op('first', observation()), tech);
      final original = diagnosisEntries(o).single;
      final correction = {
        ...observation(),
        'text': 'Corrected fictitious unit',
        'replacesId': 'first',
        'reason': 'Meter reading transcription',
      };
      expect(
        () => s.apply(op('stale', correction), tech),
        throwsA(isA<RuleException>()),
      );
      s.apply(op('review', correction, revision: o.revision), tech);
      expect(diagnosisEntries(o).first, original);
      final withdrawal = op(
        'withdraw',
        {'sourceId': 'review', 'reason': 'Fictional fault returned'},
        kind: 'diagnosis_withdraw',
        revision: o.revision,
      );
      s.apply(withdrawal, tech);
      s.apply(withdrawal, tech);
      expect(diagnosisEntries(o).length, 3);
      expect(diagnosisEntryActive(diagnosisEntries(o), 'first'), false);
      expect(diagnosisEntryActive(diagnosisEntries(o), 'review'), false);
      expect(
        () => s.apply(
          op(
            'old',
            {'sourceId': 'first', 'reason': 'Already superseded'},
            kind: 'diagnosis_withdraw',
            revision: o.revision,
          ),
          tech,
        ),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Only the author or office may review an entry; other assignments are denied',
    () {
      final s = state(), o = s.orders['o-1048']!;
      s.apply(op('office', observation(), actor: office), office);
      final p = {...observation(), 'replacesId': 'office', 'reason': 'Review'};
      expect(
        () => s.apply(op('other', p, revision: o.revision), tech),
        throwsA(isA<RuleException>()),
      );
      expect(
        () => s.apply(
          op('unassigned', observation(), actor: demoActors[1]),
          demoActors[1],
        ),
        throwsA(isA<RuleException>()),
      );
      s.apply(
        op('office-review', p, revision: o.revision, actor: office),
        office,
      );
      expect(diagnosisEntries(o).length, 2);
    },
  );
  test(
    'New technical evidence after issuance preserves the note and survives serialization',
    () {
      final s = state(), o = s.orders['o-1048']!;
      o.data['document'] = {
        'totalCents': 12345,
        'clientSnapshot': 'Original recipient',
      };
      final doc = cloneMap(o.data['document']);
      s.apply(op('late-observation', observation()), tech);
      expect(o.data['document'], doc);
      final restored = WorkshopState.fromJson(s.toJson());
      expect(diagnosisEntries(restored.orders[o.id]!), diagnosisEntries(o));
      expect(restored.orders[o.id]!.data['document'], doc);
    },
  );
}
