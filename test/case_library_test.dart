import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/models.dart';
import 'package:tallerflow/domain/case_library.dart';
import 'package:tallerflow/domain/diagnosis_notebook.dart';

final tech = demoActors[0];
final office = demoActors.firstWhere((a) => a.isOffice);
WorkshopState fixture() {
  final s = demoState();
  final o = s.orders['o-1048']!;
  o.tasks.first['assignees'] = [tech.id];
  for (final stage in ['conclusion', 'verification']) {
    s.apply(
      Operation(
        id: stage,
        orderId: o.id,
        kind: 'diagnosis_add',
        actorId: tech.id,
        baseRevision: o.revision,
        at: DateTime.utc(2026, 10, 7),
        payload: {
          'stage': stage,
          'text': 'Fictional $stage',
          'confirmed': true,
        },
      ),
      tech,
    );
  }
  return s;
}

Map<String, dynamic> draft([int revision = 0]) => {
  'id': 'case-1',
  'revision': revision,
  'sourceOrderId': 'o-1048',
  'conclusionId': 'conclusion',
  'verificationId': 'verification',
  'content': {for (final key in caseFields.keys) key: 'Fictional $key'},
  'reason': 'Fictional draft',
};
Map<String, dynamic> validation(int revision, int version) => {
  'id': 'case-1',
  'revision': revision,
  'version': version,
  'technicalConfirmed': true,
  'privacyConfirmed': true,
  'reason': 'Human review',
};
void apply(
  WorkshopState s,
  String action,
  Map<String, dynamic> p, [
  Actor? a,
]) => applyCaseCommand(
  s,
  'cmd-${s.audit.length}',
  action,
  p,
  a ?? tech,
  DateTime.utc(2026, 10, 7),
);
void main() {
  test(
    'Publication needs two explicit human reviews and confirmed source evidence',
    () {
      final s = fixture();
      apply(s, 'case_draft', draft());
      expect(visibleLibrary(s, demoActors[1]), isEmpty);
      for (final flag in ['technicalConfirmed', 'privacyConfirmed']) {
        expect(
          () => apply(s, 'case_validate', {...validation(1, 1), flag: false}),
          throwsA(isA<RuleException>()),
        );
        expect(
          () => apply(s, 'case_validate', {...validation(1, 1), flag: 'true'}),
          throwsA(isA<RuleException>()),
        );
      }
      apply(s, 'case_validate', validation(1, 1));
      expect(visibleLibrary(s, demoActors[1]).length, 1);
      expect(
        () => apply(fixture(), 'case_draft', {
          ...draft(),
          'verificationId': 'unknown',
        }),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Other technicians see only validated technical content without source identity or drafts',
    () {
      final s = fixture();
      apply(s, 'case_draft', draft());
      apply(s, 'case_validate', validation(1, 1));
      apply(s, 'case_draft', {
        ...draft(2),
        'content': {...draft()['content'], 'title': 'Private draft title'},
      });
      final c = visibleLibrary(s, demoActors[1]).single;
      expect(c['sourceOrderId'], isNull);
      expect(c['authorId'], isNull);
      expect(c['events'], isEmpty);
      expect(c['versions'].length, 1);
      expect(c['versions'][0]['content']['title'], 'Fictional title');
      expect(c['versions'][0]['conclusionId'], isNull);
      expect(visibleLibrary(s, office).single['versions'].length, 2);
    },
  );
  test(
    'Revisions, privacy fields and other authors cannot overwrite versions',
    () {
      final s = fixture();
      apply(s, 'case_draft', draft());
      for (final p in [
        draft(),
        {...draft(1), 'sourceOrderId': 'o-1045'},
        {
          ...draft(1),
          'content': {...draft()['content'], 'phone': 'Private'},
        },
      ]) {
        expect(() => apply(s, 'case_draft', p), throwsA(isA<RuleException>()));
      }
      expect(
        () => apply(s, 'case_validate', validation(1, 1), demoActors[1]),
        throwsA(isA<RuleException>()),
      );
      expect(libraryCases(s).single['versions'].length, 1);
    },
  );
  test(
    'Withdrawal retains original versions and stops sharing; office may revise',
    () {
      final s = fixture();
      apply(s, 'case_draft', draft());
      apply(s, 'case_validate', validation(1, 1));
      final original = cloneMap(libraryCases(s).single['versions'][0]);
      apply(s, 'case_withdraw', {
        'id': 'case-1',
        'revision': 2,
        'reason': 'Fault reappeared',
      }, office);
      expect(visibleLibrary(s, demoActors[1]), isEmpty);
      expect(libraryCases(s).single['versions'][0], original);
      apply(s, 'case_draft', draft(3), office);
      apply(s, 'case_validate', validation(4, 2), office);
      expect(visibleLibrary(s, demoActors[1]).single['activeVersion'], 2);
    },
  );
  test(
    'Source correction or withdrawal flags published cases and stops revalidation',
    () {
      final s = fixture();
      apply(s, 'case_draft', draft());
      apply(s, 'case_validate', validation(1, 1));
      final o = s.orders['o-1048']!;
      s.apply(
        Operation(
          id: 'withdraw-evidence',
          orderId: o.id,
          kind: 'diagnosis_withdraw',
          actorId: tech.id,
          baseRevision: o.revision,
          at: DateTime.utc(2026, 10, 7),
          payload: {'sourceId': 'conclusion', 'reason': 'Fault reappeared'},
        ),
        tech,
      );
      expect(visibleLibrary(s, demoActors[1]).single['needsReview'], true);
      expect(
        () => apply(s, 'case_validate', validation(2, 1)),
        throwsA(isA<RuleException>()),
      );
      expect(diagnosisEntries(o).first['text'], 'Fictional conclusion');
    },
  );
  test('Copy retains case history and issued documents remain unchanged', () {
    final s = fixture(), o = safeOrder();
    s.orders['o-1048']!.data['document'] = o;
    apply(s, 'case_draft', draft());
    apply(s, 'case_validate', validation(1, 1));
    final restored = s.copy();
    expect(libraryCases(restored), libraryCases(s));
    expect(restored.orders['o-1048']!.data['document'], o);
  });
}

Map<String, dynamic> safeOrder() => {
  'totalCents': 12345,
  'recipient': 'Original personal document',
};
