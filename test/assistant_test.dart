import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/simulation.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/domain/models.dart';
import 'package:tallerflow/ui/assistant_panel.dart';

class FictionalAssistantRemote extends SimulatedRemote {
  void Function()? onDraft, onPreview, onReceipt;
  bool enabled = true, loseReply = false, changedSource = false;
  int drafts = 0, reads = 0;
  final receipts = <String, Map<String, dynamic>>{};
  FictionalAssistantRemote(super.workshop, super.actor);
  @override
  Future<Map<String, dynamic>> assistant(Map<String, dynamic> b) async {
    final source = {
      'id': 'notebook:fictional',
      'kind': 'symptom',
      'text': changedSource ? 'Observación revisada' : 'Síntoma registrado',
    };
    if (b['action'] == 'preview') {
      onPreview?.call();
      return {
        'available': enabled,
        'revision': workshop.state.orders[b['orderId']]!.revision,
        'sources': [source],
      };
    }
    if (b['action'] == 'receipt') {
      reads++;
      onReceipt?.call();
      return cloneMap(receipts[b['requestId']] ?? {'state': 'not_found'});
    }
    drafts++;
    final result = <String, dynamic>{
      'state': 'completed',
      'reviewRequired': true,
      'sourceRevision': b['revision'],
      'mode': b['mode'],
      'sources': [source],
      'documentationAvailable': false,
      'draft': {
        'hypotheses': [
          {
            'text': 'Revisar el síntoma registrado',
            'sourceIds': ['notebook:fictional'],
          },
        ],
        'checks': [],
        'missingInfo': ['Falta documentación autorizada'],
      },
    };
    receipts[b['requestId']] = result;
    onDraft?.call();
    if (loseReply) {
      loseReply = false;
      throw Exception('Fictional lost reply');
    }
    return cloneMap(result);
  }
}

class FailingAssistantStore extends MemoryStore {
  bool fail = false;
  @override
  Future<void> write(String value) async {
    if (fail) throw StateError('Fictional disk unavailable');
    await super.write(value);
  }
}

Future<
  ({
    WorkshopController c,
    FictionalAssistantRemote remote,
    Vault vault,
    MemoryStore store,
  })
>
setup({Actor? actor, MemoryStore? suppliedStore}) async {
  final a = actor ?? demoActors[2],
      remote = FictionalAssistantRemote(SimulatedWorkshop(), a),
      store = suppliedStore ?? MemoryStore();
  final vault = Vault(store, await AesGcm.with256bits().newSecretKey());
  final c = WorkshopController(vault, remote: remote, actor: a);
  await c.load();
  return (c: c, remote: remote, vault: vault, store: store);
}

Map<String, dynamic> query(WorkshopController c) => {
  'mode': 'technical',
  'revision': c.state.orders['o-1045']!.revision,
  'question': 'Revisar síntoma ficticio',
  'privacyConfirmed': true,
  'identityConfirmed': true,
  'identity': {
    'make': 'Fictional',
    'model': 'Vehicle',
    'year': '2020',
    'engine': 'Example',
  },
  'sourceIds': ['notebook:fictional'],
};

void main() {
  test('A failed review or archive write keeps the durable original', () async {
    final store = FailingAssistantStore();
    final f = await setup(suppliedStore: store);
    await f.c.requestAssistant('o-1045', query(f.c));
    final original = cloneMap(f.c.assistantRecords.single);
    final id = original['id'];
    f.remote.onPreview = () => store.fail = true;
    await expectLater(
      f.c.reviewAssistant(id, 'Texto comprobado'),
      throwsStateError,
    );
    expect(f.c.assistantRecords.single, original);
    await expectLater(f.c.archiveAssistant(id, 'Conservar'), throwsStateError);
    expect(f.c.assistantRecords.single, original);
    store.fail = false;
    f.remote.onPreview = null;
    await f.c.reviewAssistant(id, 'Texto comprobado');
    await f.c.archiveAssistant(id, 'Conservar revisión');
    expect(f.c.assistantRecords.single['archivedFrom'], 'reviewed');
    expect(
      (await f.vault.read())!['assistantRecords'].single,
      f.c.assistantRecords.single,
    );
    f.c.dispose();
  });
  test(
    'Response and receipt disk failures preserve recovery without resending',
    () async {
      final store = FailingAssistantStore();
      final f = await setup(suppliedStore: store);
      f.remote.onDraft = () => store.fail = true;
      await expectLater(
        f.c.requestAssistant('o-1045', query(f.c)),
        throwsStateError,
      );
      final original = cloneMap(f.c.assistantRecords.single);
      expect(original['status'], 'pending');
      expect((await f.vault.read())!['assistantRecords'].single, original);
      store.fail = false;
      f.remote.onReceipt = () => store.fail = true;
      await expectLater(f.c.recoverAssistant(original['id']), throwsStateError);
      expect(f.c.assistantRecords.single, original);
      f.c.dispose();
      store.fail = false;
      f.remote.onReceipt = null;
      final reopened = WorkshopController(
        f.vault,
        remote: f.remote,
        actor: demoActors[2],
      );
      await reopened.load();
      await reopened.recoverAssistant(original['id']);
      expect(reopened.assistantRecords.single['status'], 'completed');
      expect(f.remote.drafts, 1);
      expect(f.remote.reads, 2);
      reopened.dispose();
    },
  );
  test(
    'Disabled preview creates no pending query or generated repair',
    () async {
      final f = await setup();
      f.remote.enabled = false;
      expect(
        (await f.c.previewAssistant('o-1045', 'technical'))['available'],
        false,
      );
      expect(f.c.assistantRecords, isEmpty);
      expect(f.remote.drafts, 0);
      f.c.dispose();
    },
  );
  test(
    'Lost reply survives restart and copy; recovery reads the original without resending',
    () async {
      final f = await setup(),
          before = cloneMap(f.remote.workshop.state.toJson());
      f.remote.loseReply = true;
      await expectLater(
        f.c.requestAssistant('o-1045', query(f.c)),
        throwsException,
      );
      final record = cloneMap(f.c.assistantRecords.single);
      expect(record['status'], 'pending');
      expect(f.store.value, isNot(contains('Revisar síntoma ficticio')));
      final backup = await f.c.exportBackup();
      expect(backup['local']['assistantRecords'].single, record);
      await expectLater(
        f.c.requestAssistant('o-1045', query(f.c)),
        throwsException,
      );
      expect(f.remote.drafts, 1);
      f.c.dispose();
      final reopened = WorkshopController(
        f.vault,
        remote: f.remote,
        actor: demoActors[2],
      );
      await reopened.load();
      await reopened.recoverAssistant(record['id']);
      expect(reopened.assistantRecords.single['status'], 'completed');
      expect(f.remote.drafts, 1);
      expect(f.remote.reads, 1);
      await reopened.reviewAssistant(
        record['id'],
        'Hipótesis revisada personalmente',
      );
      expect(reopened.assistantRecords.single['status'], 'reviewed');
      expect(
        reopened.assistantRecords.single['review']['actorId'],
        demoActors[2].id,
      );
      expect(f.remote.workshop.state.toJson(), before);
      reopened.dispose();
    },
  );
  test(
    'Changed repair revision or withdrawn original source requires new human review',
    () async {
      final f = await setup();
      await f.c.requestAssistant('o-1045', query(f.c));
      final id = f.c.assistantRecords.single['id'];
      f.remote.changedSource = true;
      await expectLater(
        f.c.reviewAssistant(id, 'Texto revisado'),
        throwsException,
      );
      expect(f.c.assistantRecords.single['status'], 'completed');
      f.remote.changedSource = false;
      f.remote.workshop.state.orders['o-1045']!.data['revision']++;
      await expectLater(
        f.c.reviewAssistant(id, 'Texto revisado'),
        throwsException,
      );
      f.c.dispose();
    },
  );
  test('Offline and unsynced records never reach the AI service', () async {
    final f = await setup();
    f.c.offline = true;
    await expectLater(
      f.c.previewAssistant('o-1045', 'technical'),
      throwsException,
    );
    await f.c.execute('o-1045', 'note', {'text': 'Observación pendiente'});
    f.c.offline = false;
    await expectLater(
      f.c.requestAssistant('o-1045', query(f.c)),
      throwsException,
    );
    expect(f.remote.drafts, 0);
    f.c.dispose();
  });
  test(
    'Technician cannot request office drafting or an unassigned repair',
    () async {
      final f = await setup(actor: demoActors[0]);
      await expectLater(
        f.c.previewAssistant('o-1045', 'office'),
        throwsException,
      );
      await expectLater(
        f.c.previewAssistant('missing', 'technical'),
        throwsException,
      );
      expect(f.remote.drafts, 0);
      f.c.dispose();
    },
  );
  test(
    'Backup validation rejects a provider key and archive retains the uncertain identity',
    () async {
      final f = await setup();
      f.remote.loseReply = true;
      await expectLater(
        f.c.requestAssistant('o-1045', query(f.c)),
        throwsException,
      );
      final id = f.c.assistantRecords.single['id'];
      await f.c.archiveAssistant(id, 'Conservar consulta incierta');
      final ar = await f.c.exportBackup();
      expect(ar['local']['assistantRecords'].single['id'], id);
      final damaged = cloneMap(ar);
      damaged['local']['assistantRecords'][0]['request']['apiKey'] =
          'not-a-real-key';
      await expectLater(f.c.restoreLocalBackup(damaged), throwsException);
      expect(f.c.assistantRecords.single['status'], 'archived');
      f.c.dispose();
    },
  );
  testWidgets('A draft remains unreviewed until personal confirmation', (
    tester,
  ) async {
    final f = await setup();
    await f.c.requestAssistant('o-1045', query(f.c));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AssistantPanel(
              controller: f.c,
              order: f.c.state.orders['o-1045']!,
              run: (fn) => fn(),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Revisar texto y fuentes'));
    await tester.pumpAndSettle();
    expect(find.text('Revisar borrador y fuentes'), findsOneWidget);
    expect(find.text('Todavía no revisados'), findsNothing);
    expect(find.text('Todavía no comprobada'), findsNothing);
    expect(f.c.assistantRecords.single['status'], 'completed');
    await tester.tap(find.text('Confirmar y guardar'));
    await tester.pumpAndSettle();
    expect(f.c.assistantRecords.single['status'], 'completed');
    expect(find.textContaining('Revisa las fuentes'), findsNothing);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    f.c.dispose();
  });
}
