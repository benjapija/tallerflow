import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/simulation.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/models.dart';

class LostManagementReply extends SimulatedRemote {
  bool lose = true;
  LostManagementReply(super.workshop, super.actor);
  @override
  Future<Map<String, dynamic>> command(
    String id,
    String action,
    Map<String, dynamic> p,
  ) async {
    final r = await super.command(id, action, p);
    if (lose) {
      lose = false;
      throw StateError('Synthetic lost response');
    }
    return r;
  }
}

Operation op(
  WorkshopState s,
  String kind,
  Map<String, dynamic> p, {
  String? actor,
  int? revision,
}) => Operation(
  id: 'operation-${s.audit.length}',
  orderId: 'o-1048',
  kind: kind,
  actorId: actor ?? 'office',
  baseRevision: revision ?? s.orders['o-1048']!.revision,
  at: DateTime.utc(2026, 10, 6, 14),
  payload: p,
);
void main() {
  test(
    'Reception clears forged authorization, documents and prior charges before work can start',
    () {
      final s = demoState();
      final source = cloneMap(s.orders['o-1048']!.data);
      source['document'] = {'totalCents': 1};
      source['quality'] = {'result': 'Forged'};
      source['reviewedParts'] = true;
      source['tasks'] = [
        {
          ...source['tasks'][0],
          'authorized': true,
          'billableMinutes': 90,
          'rateCents': 1,
          'done': true,
        },
      ];
      s.apply(
        Operation(
          id: 'receive-clean',
          orderId: 'new-clean',
          kind: 'receive',
          actorId: 'office',
          baseRevision: 0,
          at: DateTime.now(),
          payload: source,
        ),
        demoActors[2],
      );
      final order = s.orders['new-clean']!;
      expect(order.data['document'], isNull);
      expect(order.data['quality'], isNull);
      expect(order.data.containsKey('reviewedParts'), false);
      expect(order.tasks.single['authorized'], false);
      expect(order.tasks.single['billableMinutes'], 0);
      expect(order.tasks.single['rateCents'], 4800);
      expect(
        () => s.apply(
          Operation(
            id: 'cannot-start',
            orderId: order.id,
            kind: 'start',
            actorId: 'tech-alex',
            baseRevision: 0,
            at: DateTime.now(),
            payload: {'taskId': order.tasks.single['id']},
          ),
          demoActors[0],
        ),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Reception rejects duplicate task IDs and foreign assignments without creating an order',
    () {
      final s = demoState();
      final source = cloneMap(s.orders['o-1048']!.data);
      source['tasks'] = [source['tasks'][0], source['tasks'][0]];
      void receive(Map<String, dynamic> p) => s.apply(
        Operation(
          id: 'bad-receive',
          orderId: 'bad-order',
          kind: 'receive',
          actorId: 'office',
          baseRevision: 0,
          at: DateTime.now(),
          payload: p,
        ),
        demoActors[2],
      );
      expect(() => receive(source), throwsA(isA<RuleException>()));
      expect(s.orders.containsKey('bad-order'), false);
      source['tasks'] = [
        {
          ...source['tasks'][0],
          'assignees': ['foreign'],
        },
      ];
      expect(() => receive(source), throwsA(isA<RuleException>()));
      expect(s.orders.containsKey('bad-order'), false);
    },
  );
  test(
    'Administration requires admin and preserves latest revision with valid tax',
    () {
      final s = demoState();
      final p = {
        'revision': 0,
        'reason': 'Fictional rate review',
        'settings': {
          'hourlyRateCents': 6000,
          'taxBps': 1000,
          'internalHourlyCostCents': 2500,
          'internalCostKnown': true,
        },
      };
      expect(
        () => s.manage('m1', 'settings_save', p, demoActors[2], DateTime.now()),
        throwsA(isA<RuleException>()),
      );
      s.manage('m1', 'settings_save', p, demoActors[3], DateTime.now());
      expect(s.managementRevision, 1);
      expect(s.settings['taxBps'], 1000);
      expect(s.copy().settings, s.settings);
      expect(
        () => s.manage('m2', 'settings_save', p, demoActors[3], DateTime.now()),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Catalog updates retain prior consumption prices and adjust available stock',
    () {
      final s = demoState();
      s.apply(
        op(s, 'part', {
          'taskId': 't-1',
          'itemId': 'p-3',
          'quantityMilli': 500,
          'kind': 'consume',
        }),
        demoActors[2],
      );
      final c = s.catalog.firstWhere((c) => c.id == 'p-3');
      s.manage(
        'catalog',
        'catalog_save',
        {
          'revision': 0,
          'reason': 'Counted',
          'item': {
            ...c.toJson(),
            'priceCents': 2000,
            'stockMilli': 8000,
            'taxBps': 1000,
          },
        },
        demoActors[3],
        DateTime.now(),
      );
      expect(s.stock('p-3'), 8000);
      expect(s.orders['o-1048']!.parts.first['priceCents'], 1450);
      s.apply(
        op(s, 'part', {
          'taskId': 't-1',
          'itemId': 'p-3',
          'quantityMilli': 500,
          'kind': 'consume',
        }),
        demoActors[2],
      );
      expect(s.orders['o-1048']!.parts.last['taxBps'], 1000);
      expect(s.stock('p-3'), 7500);
    },
  );
  test('Last admin and active technicians cannot be disabled', () {
    final s = demoState();
    final p = {
      'revision': 0,
      'reason': 'Test',
      'userId': 'admin',
      'name': 'Admin',
      'role': 'office',
      'active': true,
      'seePrices': true,
      'seeCosts': true,
    };
    expect(
      () => s.manage('x', 'member_save', p, demoActors[3], DateTime.now()),
      throwsA(isA<RuleException>()),
    );
    s.apply(
      op(s, 'start', {'taskId': 't-1'}, actor: 'tech-alex'),
      demoActors[0],
    );
    expect(
      () => s.manage(
        'y',
        'member_save',
        {...p, 'userId': 'tech-alex', 'role': 'technician', 'active': false},
        demoActors[3],
        DateTime.now(),
      ),
      throwsA(isA<RuleException>()),
    );
  });
  test(
    'Multi-technician assignment, task block and scope consent retain history',
    () {
      final s = demoState();
      final t = s.orders['o-1048']!.tasks.first;
      s.apply(
        op(s, 'task_edit', {
          'taskId': 't-1',
          'title': t['title'],
          'estimateMinutes': 90,
          'assignees': ['tech-alex', 'tech-lucia'],
          'reason': 'Shared work',
        }),
        demoActors[2],
      );
      expect(t['authorized'], true);
      expect(t['assignees'], ['tech-alex', 'tech-lucia']);
      s.apply(
        op(s, 'task_block', {
          'taskId': 't-1',
          'reason': 'Parts',
          'nextAction': 'Check arrival',
          'ownerId': 'office',
        }, actor: 'tech-lucia'),
        demoActors[1],
      );
      expect(
        () => s.apply(
          op(s, 'start', {'taskId': 't-1'}, actor: 'tech-alex'),
          demoActors[0],
        ),
        throwsA(isA<RuleException>()),
      );
      s.apply(
        op(s, 'task_unblock', {
          'taskId': 't-1',
          'reason': 'Arrived',
        }, actor: 'tech-lucia'),
        demoActors[1],
      );
      s.apply(
        op(s, 'task_edit', {
          'taskId': 't-1',
          'title': 'Revised scope',
          'estimateMinutes': 95,
          'assignees': ['tech-alex'],
          'reason': 'Expansion',
        }),
        demoActors[2],
      );
      expect(t['authorized'], false);
      expect(t['previousAuthorizations'], hasLength(1));
      expect(s.orders['o-1048']!.tasks[1]['authorized'], true);
    },
  );
  test('Tasks refuse stale edits and cancellation of recorded work', () {
    final s = demoState();
    s.apply(
      op(s, 'start', {'taskId': 't-1'}, actor: 'tech-alex'),
      demoActors[0],
    );
    expect(
      () => s.apply(
        op(s, 'task_edit', {
          'taskId': 't-1',
          'title': 'x',
          'assignees': ['tech-lucia'],
          'estimateMinutes': 30,
          'reason': 'Change',
        }),
        demoActors[2],
      ),
      throwsA(isA<RuleException>()),
    );
    expect(
      () => s.apply(
        op(s, 'order_plan', {
          'reason': 'Change',
          'priority': 'Alta',
          'due': 'Today',
          'location': 'Bay',
          'keys': 'Board',
        }, revision: 0),
        demoActors[2],
      ),
      throwsA(isA<RuleException>()),
    );
    expect(
      () => s.apply(
        op(s, 'task_cancel', {'taskId': 't-1', 'reason': 'Remove'}),
        demoActors[2],
      ),
      throwsA(isA<RuleException>()),
    );
  });
  test(
    'Applying a template requires compatibility and leaves tasks unauthorized',
    () {
      final s = demoState();
      s.manage(
        'template',
        'template_save',
        {
          'revision': 0,
          'reason': 'Template',
          'template': {
            'id': 'tpl',
            'name': 'Service',
            'active': true,
            'tasks': [
              {
                'title': 'Check oil',
                'estimateMinutes': 30,
                'references': [
                  {'itemId': 'p-3', 'quantityMilli': 500},
                ],
              },
            ],
          },
        },
        demoActors[3],
        DateTime.now(),
      );
      final p = {
        'templateId': 'tpl',
        'templateVersion': 1,
        'taskIds': ['added'],
        'assignees': ['tech-alex'],
        'reason': 'Reviewed',
        'compatibilityChecked': false,
      };
      expect(
        () => s.apply(op(s, 'template_apply', p), demoActors[2]),
        throwsA(isA<RuleException>()),
      );
      s.apply(
        op(s, 'template_apply', {...p, 'compatibilityChecked': true}),
        demoActors[2],
      );
      final t = s.orders['o-1048']!.tasks.last;
      expect(t['authorized'], false);
      expect(t['suggestedReferences'], hasLength(1));
      expect(calculateNote(s.orders['o-1048']!).totalCents, 0);
    },
  );
  test(
    'Lost administration response and restart retain the same command and one effect',
    () async {
      final remote = LostManagementReply(SimulatedWorkshop(), demoActors[3]);
      final store = MemoryStore(),
          key = await AesGcm.with256bits().newSecretKey();
      final c = WorkshopController(
        Vault(store, key),
        remote: remote,
        actor: demoActors[3],
      );
      await c.load();
      final p = {
        'reason': 'Test retry',
        'settings': {
          'hourlyRateCents': 6000,
          'taxBps': 2100,
          'internalHourlyCostCents': 2500,
          'internalCostKnown': true,
        },
      };
      await expectLater(c.manage('settings_save', p), throwsStateError);
      expect(c.pendingCommands, hasLength(1));
      final id = c.pendingCommands.first['id'];
      c.dispose();
      final next = WorkshopController(
        Vault(store, key),
        remote: remote,
        actor: demoActors[3],
      );
      await next.load();
      expect(next.pendingCommands.first['id'], id);
      await next.synchronize();
      expect(next.pendingCommands, isEmpty);
      expect(remote.workshop.state.managementRevision, 1);
      expect(next.state.settings['hourlyRateCents'], 6000);
      next.dispose();
    },
  );
}
