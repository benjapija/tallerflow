import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tallerflow/data/cloud.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/domain/models.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/fiscal_drafts.dart';
import 'package:tallerflow/domain/fiscal_draft_integrity.dart';
import 'package:tallerflow/domain/fiscal_profile.dart';

const workshopId = '00000000-0000-4000-8000-000000070000';
const admin = Actor(
  '00000000-0000-4000-8000-000000070001',
  'Admin ficticio',
  Role.admin,
);
Map<String, dynamic> draftInput({String installation = 'prueba-a'}) => {
  'issuerNif': 'B12345678',
  'installation': installation,
  'prefix': 'ENSAYO-A',
  'reason': 'Prueba ficticia',
  'issueDate': '2026-10-07',
  'recipient': {'name': 'Cliente ficticio', 'nif': '12345678Z'},
  'lines': [
    {
      'id': '00000000-0000-4000-8000-000000070002',
      'description': 'Pieza ficticia',
      'unitCents': 3333,
      'quantityMilli': 1500,
      'discountBps': 1250,
      'taxBps': 2100,
      'tax': 'iva',
      'treatment': 'taxable',
    },
  ],
};

class DraftTestStore extends MemoryStore {
  bool fail = false;
  @override
  Future<void> write(String value) async {
    if (fail) {
      throw StateError('Disco lleno ficticio');
    }
    await super.write(value);
  }
}

/// Fault-injectable protocol fixture. SQL/GoTrue evidence is tracked separately.
class DraftTestRemote extends Remote {
  Map<String, dynamic> ledger = emptyFiscalDraftLedger();
  final Map<String, Map<String, dynamic>> receipts = {};
  final List<Map<String, dynamic>> calls = [];
  bool lostReply = false, unavailable = false, lease = false, denyRead = false;
  bool malformedReply = false;
  void Function()? afterCommit;
  late String device;
  @override
  bool get requiresLease => lease;
  @override
  void bindDevice(String id) => device = id;
  @override
  Future<Map<String, dynamic>> snapshot() async {
    final state = demoState();
    state.configuration['settings'] = {
      ...state.settings,
      'fiscalProfile': {
        ...initialFiscalProfile(),
        'territory': 'common',
        'sii': 'no',
      },
    };
    final view = state.toJson()..['workshopId'] = workshopId;
    return {
      ...view,
      'actor': admin.toJson(),
      'serverTime': DateTime.now().toUtc().toIso8601String(),
    };
  }

  @override
  Future<Map<String, dynamic>> fiscalDrafts() async {
    if (denyRead) {
      throw const PostgrestException(
        message: 'Administrator/session denied',
        code: '42501',
      );
    }
    if (unavailable) {
      throw StateError('Sin conexión ficticia');
    }
    return cloneMap(ledger);
  }

  @override
  Future<Map<String, dynamic>> push(Operation operation, String deviceId) =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> command(
    String id,
    String action,
    Map<String, dynamic> payload,
  ) async {
    if (unavailable) {
      throw StateError('Sin conexión ficticia');
    }
    calls.add({
      'id': id,
      'action': action,
      'payload': cloneMap(payload),
      'device': device,
    });
    if (receipts.containsKey(id)) {
      return cloneMap(receipts[id]!);
    }
    final p = normalizeFiscalDraftPayload(action, payload);
    final heads = fiscalDraftRows(ledger['heads']),
        series = fiscalDraftRows(ledger['series']),
        records = fiscalDraftRows(ledger['records']);
    final head = heads
        .where(
          (h) =>
              h['issuer_nif'] == p['issuerNif'] &&
              h['installation'] == p['installation'],
        )
        .firstOrNull;
    if (head?['restored'] == true) {
      throw const PostgrestException(
        message: 'Restored draft installation is frozen',
        code: 'P0001',
      );
    }
    if ((head?['last_sequence'] ?? 0) != p['expectedSequence'] ||
        (head?['last_hash'] ?? '') != p['expectedHash']) {
      throw const PostgrestException(
        message: 'Draft chain conflict; refresh and review',
        code: 'P0001',
      );
    }
    Map<String, dynamic>? original;
    if (action == 'fiscal_draft_withdraw') {
      original = records.firstWhere((r) => r['id'] == p['targetId']);
    }
    final prefix = original?['prefix'] ?? p['prefix'];
    final counter = series
        .where(
          (s) =>
              s['issuer_nif'] == p['issuerNif'] &&
              s['installation'] == p['installation'] &&
              s['prefix'] == prefix,
        )
        .firstOrNull;
    final number = original?['number'] ?? ((counter?['last_number'] ?? 0) + 1);
    final sequence = p['expectedSequence'] + 1;
    final body = <String, dynamic>{
      'draftFormat': 1,
      'emissionEnabled': false,
      'transmissionEnabled': false,
      'scope': 'sandbox',
      'id': id,
      'issuerNif': p['issuerNif'],
      'installation': p['installation'],
      'sequence': sequence,
      'kind': original == null ? 'draft' : 'withdrawal',
      'prefix': prefix,
      'number': number,
      'reason': p['reason'],
      'actorId': admin.id,
      'deviceId': device,
      'createdAt': '2026-10-07T15:00:00.123456+00:00',
      if (original == null)
        'calculation': fiscalDraftCalculation(fiscalDraftRows(p['lines'])),
      if (original == null) 'issueDate': p['issueDate'],
      if (original == null) 'recipient': p['recipient'],
      if (original != null) 'targetId': original['id'],
      if (original != null) 'originalLedgerHash': original['ledger_hash'],
    };
    final hash = await fiscalDraftLedgerHash(body, p['expectedHash']);
    final row = {
      'workshop_id': workshopId,
      'id': id,
      'issuer_nif': p['issuerNif'],
      'installation': p['installation'],
      'sequence': sequence,
      'kind': body['kind'],
      'prefix': prefix,
      'number': number,
      'target_id': original?['id'],
      'actor_id': admin.id,
      'device_id': device,
      'body': body,
      'previous_hash': p['expectedHash'],
      'ledger_hash': hash,
    };
    heads.removeWhere(
      (h) =>
          h['issuer_nif'] == p['issuerNif'] &&
          h['installation'] == p['installation'],
    );
    heads.add({
      'workshop_id': workshopId,
      'issuer_nif': p['issuerNif'],
      'installation': p['installation'],
      'last_sequence': sequence,
      'last_hash': hash,
      'restored': false,
    });
    if (original == null) {
      series.removeWhere(
        (s) =>
            s['issuer_nif'] == p['issuerNif'] &&
            s['installation'] == p['installation'] &&
            s['prefix'] == prefix,
      );
      series.add({
        'workshop_id': workshopId,
        'issuer_nif': p['issuerNif'],
        'installation': p['installation'],
        'prefix': prefix,
        'last_number': number,
      });
    }
    ledger = {
      ...emptyFiscalDraftLedger(),
      'heads': heads,
      'series': series,
      'records': [...records, row],
    };
    final result = <String, dynamic>{
      'saved': true,
      'id': id,
      'sequence': sequence,
      'prefix': prefix,
      'number': number,
      'ledgerHash': hash,
      'emissionEnabled': false,
      'transmissionEnabled': false,
    };
    receipts[id] = cloneMap(result);
    afterCommit?.call();
    if (lostReply) {
      lostReply = false;
      throw StateError('Respuesta perdida después de confirmar');
    }
    return malformedReply ? {'saved': true} : result;
  }
}

Future<WorkshopController> draftController(
  DraftTestRemote remote, {
  Vault? vault,
}) async {
  final c = WorkshopController(
    vault ?? Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
    remote: remote,
    actor: admin,
  );
  await c.load();
  await c.refreshFiscalDrafts();
  return c;
}

void main() {
  test(
    'Offline command survives encrypted restart and has no number until server confirmation',
    () async {
      final remote = DraftTestRemote(),
          c = await draftController(DraftTestRemote());
      c.dispose();
      final first = await draftController(remote);
      first.offline = true;
      await first.prepareFiscalDraft(draftInput());
      final queued = first.fiscalDraftQueue.single, id = queued['id'];
      expect(queued['status'], 'pending');
      expect(queued.containsKey('result'), false);
      expect(remote.calls, isEmpty);
      expect(first.vault.store is MemoryStore, true);
      expect(
        (first.vault.store as MemoryStore).value,
        isNot(contains('Cliente ficticio')),
      );
      final restart = WorkshopController(
        first.vault,
        remote: remote,
        actor: admin,
      );
      await restart.load();
      expect(restart.fiscalDraftQueue.single['id'], id);
      await restart.synchronize();
      expect(restart.fiscalDraftQueue.single['status'], 'confirmed');
      expect(restart.fiscalDraftQueue.single['result']['number'], 1);
      expect(fiscalDraftRows(remote.ledger['records']), hasLength(1));
      expect(remote.calls.single['id'], id);
      expect(
        fiscalDraftSame(remote.calls.single['payload'], queued['payload']),
        true,
      );
      first.dispose();
      restart.dispose();
    },
  );
  test(
    'A committed reply lost during confirmation is reconciled with the same result after restart',
    () async {
      final remote = DraftTestRemote()..lostReply = true,
          c = await draftController(remote);
      await expectLater(c.prepareFiscalDraft(draftInput()), throwsStateError);
      final original = cloneMap(c.fiscalDraftQueue.single),
          restart = WorkshopController(c.vault, remote: remote, actor: admin);
      await restart.load();
      await restart.synchronize();
      expect(restart.fiscalDraftQueue.single['status'], 'confirmed');
      expect(restart.fiscalDraftQueue.single['id'], original['id']);
      expect(remote.calls, hasLength(1));
      expect(remote.receipts, hasLength(1));
      await restart.synchronize();
      expect(remote.calls, hasLength(1));
      c.dispose();
      restart.dispose();
    },
  );
  test('Failure saving the local request sends nothing', () async {
    final store = DraftTestStore(),
        remote = DraftTestRemote(),
        c = await draftController(
          remote,
          vault: Vault(store, await AesGcm.with256bits().newSecretKey()),
        );
    store.fail = true;
    await expectLater(c.prepareFiscalDraft(draftInput()), throwsStateError);
    expect(remote.calls, isEmpty);
    expect(c.fiscalDraftQueue, isEmpty);
    c.dispose();
  });
  test(
    'Failure persisting a confirmed response retains durable pending identity',
    () async {
      final store = DraftTestStore(),
          remote = DraftTestRemote(),
          c = await draftController(
            remote,
            vault: Vault(store, await AesGcm.with256bits().newSecretKey()),
          );
      remote.afterCommit = () => store.fail = true;
      await expectLater(c.prepareFiscalDraft(draftInput()), throwsStateError);
      expect(c.fiscalDraftQueue.single['status'], 'pending');
      store.fail = false;
      remote.afterCommit = null;
      final restart = WorkshopController(c.vault, remote: remote, actor: admin);
      await restart.load();
      await restart.synchronize();
      expect(restart.fiscalDraftQueue.single['status'], 'confirmed');
      expect(remote.calls, hasLength(1));
      c.dispose();
      restart.dispose();
    },
  );
  test(
    'Two administrators retain stale conflict and require reasoned review before a new command',
    () async {
      final remote = DraftTestRemote(),
          a = await draftController(remote),
          b = await draftController(remote);
      // Each fixture connection must bind its original device before a send.
      b.offline = true;
      await b.prepareFiscalDraft(draftInput());
      final old = cloneMap(b.fiscalDraftQueue.single);
      remote.bindDevice(a.deviceId);
      await a.prepareFiscalDraft(draftInput());
      remote.bindDevice(b.deviceId);
      b.offline = false;
      await b.synchronize();
      expect(b.fiscalDraftQueue.single['status'], 'conflict');
      expect(remote.receipts, hasLength(1));
      expect(
        fiscalDraftSame(old['payload'], b.fiscalDraftQueue.single['payload']),
        true,
      );
      await expectLater(
        b.prepareFiscalDraft(draftInput()),
        throwsA(isA<RuleException>()),
      );
      await expectLater(
        b.reviewFiscalDraft(old['id'], ''),
        throwsA(isA<RuleException>()),
      );
      await b.reviewFiscalDraft(
        old['id'],
        'Revisado frente al original vigente',
      );
      await b.prepareFiscalDraft(draftInput());
      expect(remote.receipts, hasLength(2));
      expect(fiscalDraftRows(remote.ledger['series']).single['last_number'], 2);
      expect(b.fiscalDraftQueue.first['previousStatus'], 'conflict');
      a.dispose();
      b.dispose();
    },
  );
  test(
    'A pending request cannot be archived or changed; independent installations remain available',
    () async {
      final remote = DraftTestRemote(), c = await draftController(remote);
      c.offline = true;
      await c.prepareFiscalDraft(draftInput());
      await expectLater(
        c.reviewFiscalDraft(c.fiscalDraftQueue.single['id'], 'Duplicar'),
        throwsA(isA<RuleException>()),
      );
      await expectLater(
        c.prepareFiscalDraft(draftInput()),
        throwsA(isA<RuleException>()),
      );
      await c.prepareFiscalDraft(draftInput(installation: 'prueba-b'));
      expect(c.fiscalDraftQueue, hasLength(2));
      c.dispose();
    },
  );
  test(
    'Malformed acknowledgement never confirms without a verified immutable original',
    () async {
      final remote = DraftTestRemote()..malformedReply = true,
          c = await draftController(remote);
      await expectLater(
        c.prepareFiscalDraft(draftInput()),
        throwsA(isA<RuleException>()),
      );
      expect(c.fiscalDraftQueue.single['status'], 'pending');
      remote.malformedReply = false;
      await c.synchronize();
      expect(c.fiscalDraftQueue.single['status'], 'confirmed');
      expect(remote.calls, hasLength(1));
      c.dispose();
    },
  );
  test(
    'Reasoned withdrawal preserves original and allocates no extra series number',
    () async {
      final remote = DraftTestRemote(), c = await draftController(remote);
      await c.prepareFiscalDraft(draftInput());
      final original = cloneMap(
        fiscalDraftRows(remote.ledger['records']).single,
      );
      await expectLater(
        c.withdrawFiscalDraft(original['id'], ''),
        throwsA(isA<RuleException>()),
      );
      c.offline = true;
      await c.withdrawFiscalDraft(
        original['id'],
        'Retirada de ensayo revisada',
      );
      expect(fiscalDraftRows(remote.ledger['records']), hasLength(1));
      c.offline = false;
      await c.synchronize();
      expect(
        fiscalDraftSame(
          fiscalDraftRows(remote.ledger['records']).first,
          original,
        ),
        true,
      );
      expect(
        fiscalDraftRows(remote.ledger['records']).last['kind'],
        'withdrawal',
      );
      expect(fiscalDraftRows(remote.ledger['series']).single['last_number'], 1);
      c.dispose();
    },
  );
  test(
    'Local backup restores pending bytes and actor/device identity; lease is not imported',
    () async {
      final remote = DraftTestRemote(), c = await draftController(remote);
      c.offline = true;
      await c.prepareFiscalDraft(draftInput());
      final archive = await c.exportBackup(),
          original = cloneMap(c.fiscalDraftQueue.single);
      final target = await draftController(DraftTestRemote());
      await target.restoreLocalBackup(archive);
      expect(target.accessRevoked, true);
      expect(
        fiscalDraftSame(target.localArchive()['fiscalDraftQueue'][0], original),
        true,
      );
      await expectLater(
        c.restoreLocalBackup(archive),
        throwsA(isA<RuleException>()),
      );
      c.dispose();
      target.dispose();
    },
  );
  test(
    'Corrupted confirmations or numbers reject recovery before replacing local data',
    () async {
      final c = await draftController(DraftTestRemote());
      await c.prepareFiscalDraft(draftInput());
      final archive = await c.exportBackup();
      final target = await draftController(DraftTestRemote()),
          before = await target.vault.read();
      final bad = cloneMap(archive);
      bad['local']['fiscalDraftLedger']['records'][0]['body']['calculation']['totalCents']++;
      await expectLater(
        target.restoreLocalBackup(bad),
        throwsA(isA<RuleException>()),
      );
      expect(fiscalDraftSame(await target.vault.read(), before), true);
      final fake = cloneMap(archive);
      fake['local']['fiscalDraftQueue'][0]['result']['number'] = 999;
      await expectLater(
        target.restoreLocalBackup(fake),
        throwsA(isA<RuleException>()),
      );
      c.dispose();
      target.dispose();
    },
  );
  test('Legacy caches without fiscal extension remain readable', () async {
    final c = await draftController(DraftTestRemote());
    final saved = c.localArchive()
      ..remove('fiscalDraftLedger')
      ..remove('fiscalDraftQueue')
      ..remove('fiscalDraftsLoaded');
    await c.vault.write(saved);
    final restart = WorkshopController(
      c.vault,
      remote: DraftTestRemote(),
      actor: admin,
    );
    await restart.load();
    expect(restart.fiscalDraftQueue, isEmpty);
    expect(restart.fiscalDraftsLoaded, false);
    c.dispose();
    restart.dispose();
  });
  test(
    'Frozen recovered installation cannot continue; fresh installation has separate chain',
    () async {
      final remote = DraftTestRemote(), c = await draftController(remote);
      await c.prepareFiscalDraft(draftInput());
      remote.ledger['heads'][0]['restored'] = true;
      await c.refreshFiscalDrafts();
      await expectLater(
        c.prepareFiscalDraft(draftInput()),
        throwsA(isA<RuleException>()),
      );
      await expectLater(
        c.withdrawFiscalDraft(c.fiscalDraftQueue.single['id'], 'No continuar'),
        throwsA(isA<RuleException>()),
      );
      await c.prepareFiscalDraft(draftInput(installation: 'recuperada-nueva'));
      expect(c.fiscalDraftQueue.last['result']['number'], 1);
      expect(fiscalDraftRows(remote.ledger['heads']), hasLength(2));
      c.dispose();
    },
  );
  test(
    'Preview uses one rounding identical to saved sandbox instead of generic invoice policy',
    () {
      final input = draftInput()['lines'] as List;
      final calculation = fiscalDraftCalculation(
        input.cast<Map<String, dynamic>>(),
      );
      expect(calculation['baseCents'], 4375);
      expect(calculation['taxCents'], 919);
      expect(calculation['totalCents'], 5294);
      final half = Map<String, dynamic>.from(input.single)
        ..['unitCents'] = 1
        ..['quantityMilli'] = 501
        ..['discountBps'] = 1
        ..['taxBps'] = 0;
      expect(fiscalDraftCalculation([half])['baseCents'], 1);
      expect(
        () => fiscalDraftCalculation([half, half]),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test('Queue and ledger getters cannot mutate the durable original', () async {
    final c = await draftController(DraftTestRemote());
    c.offline = true;
    await c.prepareFiscalDraft(draftInput());
    final queue = c.fiscalDraftQueue;
    queue.single['payload']['reason'] = 'Cambiar';
    expect(c.fiscalDraftQueue.single['payload']['reason'], 'Prueba ficticia');
    c.fiscalDraftLedger['heads'].add({'malformed': true});
    expect(fiscalDraftRows(c.fiscalDraftLedger['heads']), isEmpty);
    expect(jsonEncode(c.localArchive()), contains('Prueba ficticia'));
    c.dispose();
  });

  test(
    'XML generated from confirmed data is saved atomically and survives encrypted backup',
    () async {
      final remote = DraftTestRemote(), c = await draftController(remote);
      await c.prepareFiscalDraft(draftInput());
      final settings = <String, dynamic>{
        'issuerName': 'Emisor ficticio',
        'manufacturerName': 'Fabricante ficticio',
        'manufacturerNif': 'B12345678',
        'name': 'TallerFlow ensayo',
        'id': 'TF',
        'version': '0.3-ensayo',
        'installation': 'prueba-a',
        'onlyVerifactu': false,
        'canHaveMultipleTaxpayers': true,
        'hasMultipleTaxpayers': false,
      };
      final id = c.fiscalDraftQueue.single['id'];
      final artifact = await c.generateFiscalDraftXml(id, settings);
      expect(artifact['emissionEnabled'], false);
      expect(artifact['transmissionEnabled'], false);
      expect(artifact['ledgerHash'], isNot(artifact['aeatHash']));
      expect(artifact['xml'], contains('52.94'));
      final again = await c.generateFiscalDraftXml(id, {
        ...settings,
        'version': 'cambiada',
      });
      expect(fiscalDraftSame(artifact, again), true);
      final restart = WorkshopController(c.vault, remote: remote, actor: admin);
      await restart.load();
      expect(
        fiscalDraftSame(restart.fiscalDraftXmlArtifacts.single, artifact),
        true,
      );
      final archive = await c.exportBackup();
      final target = await draftController(DraftTestRemote());
      await target.restoreLocalBackup(archive);
      expect(
        fiscalDraftSame(
          target.localArchive()['fiscalDraftXmlArtifacts'][0],
          artifact,
        ),
        true,
      );
      final changed = cloneMap(archive);
      changed['local']['fiscalDraftXmlArtifacts'][0]['xml'] += 'tampered';
      final other = await draftController(DraftTestRemote());
      await expectLater(
        other.restoreLocalBackup(changed),
        throwsA(isA<RuleException>()),
      );
      c.dispose();
      restart.dispose();
      target.dispose();
      other.dispose();
    },
  );
  test(
    'Extending XML keeps issuer and technical snapshots and fails a changed chain setting',
    () async {
      final remote = DraftTestRemote(), c = await draftController(remote);
      final settings = <String, dynamic>{
        'issuerName': 'Emisor ficticio',
        'manufacturerName': 'Fabricante ficticio',
        'manufacturerNif': 'B12345678',
        'name': 'TallerFlow ensayo',
        'id': 'TF',
        'version': '0.3-ensayo',
        'installation': 'prueba-a',
        'onlyVerifactu': false,
        'canHaveMultipleTaxpayers': true,
        'hasMultipleTaxpayers': false,
      };
      await c.prepareFiscalDraft(draftInput());
      final first = await c.generateFiscalDraftXml(
        c.fiscalDraftQueue.single['id'],
        settings,
      );
      await c.prepareFiscalDraft(draftInput());
      final last = c.fiscalDraftQueue.last['id'];
      await expectLater(
        c.generateFiscalDraftXml(last, {...settings, 'version': 'changed'}),
        throwsA(isA<RuleException>()),
      );
      final second = await c.generateFiscalDraftXml(last, settings);
      expect(second['previousXmlRecordId'], first['recordId']);
      expect(c.fiscalDraftXmlArtifacts, hasLength(2));
      expect(fiscalDraftSame(c.fiscalDraftXmlArtifacts.first, first), true);
      final restart = WorkshopController(c.vault, remote: remote, actor: admin);
      await restart.load();
      expect(restart.fiscalDraftXmlArtifacts, hasLength(2));
      expect(
        fiscalDraftSame(restart.fiscalDraftXmlArtifacts.last, second),
        true,
      );
      final archive = await c.exportBackup();
      final target = await draftController(DraftTestRemote());
      await target.restoreLocalBackup(archive);
      expect(target.fiscalDraftXmlArtifacts, hasLength(2));
      expect(
        fiscalDraftSame(target.fiscalDraftXmlArtifacts.last, second),
        true,
      );
      final changed = cloneMap(archive);
      changed['local']['fiscalDraftXmlArtifacts'][1]['snapshot']['previousXml']['aeatHash'] =
          '0' * 64;
      await expectLater(
        target.restoreLocalBackup(changed),
        throwsA(isA<RuleException>()),
      );
      c.dispose();
      restart.dispose();
      target.dispose();
    },
  );
  test(
    'XML generation persistence failure never replaces an original or reports a saved artifact',
    () async {
      final remote = DraftTestRemote(),
          store = DraftTestStore(),
          c = await draftController(
            remote,
            vault: Vault(store, await AesGcm.with256bits().newSecretKey()),
          );
      await c.prepareFiscalDraft(draftInput());
      store.fail = true;
      final settings = <String, dynamic>{
        'issuerName': 'Emisor ficticio',
        'manufacturerName': 'Fabricante ficticio',
        'manufacturerNif': 'B12345678',
        'name': 'TallerFlow ensayo',
        'id': 'TF',
        'version': '0.3-ensayo',
        'installation': 'prueba-a',
        'onlyVerifactu': false,
        'canHaveMultipleTaxpayers': true,
        'hasMultipleTaxpayers': false,
      };
      await expectLater(
        c.generateFiscalDraftXml(c.fiscalDraftQueue.single['id'], settings),
        throwsStateError,
      );
      expect(c.fiscalDraftXmlArtifacts, isEmpty);
      expect(fiscalDraftRows(remote.ledger['records']), hasLength(1));
      c.dispose();
    },
  );
}
