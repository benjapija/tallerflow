import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tallerflow/data/cloud.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/fiscal_draft_integrity.dart';
import 'package:tallerflow/domain/fiscal_drafts.dart';
import 'package:tallerflow/domain/fiscal_profile.dart';
import 'package:tallerflow/domain/models.dart';

const _admin = Actor(
  '00000000-0000-4000-8000-000000000010',
  'Administrador ficticio',
  Role.admin,
  seePrices: true,
);
final _now = DateTime.utc(2026, 10, 7, 12);

Map<String, dynamic> _payload() => {
  'issuerNif': 'A12345678',
  'installation': 'fictional-installation',
  'prefix': 'ENSAYO-2026',
  'reason': 'Comprobación ficticia de recuperación',
  'issueDate': '2026-10-07',
  'recipient': {'name': 'Cliente ficticio', 'nif': '12345678Z'},
  'lines': [
    {
      'id': '00000000-0000-4000-8000-000000000001',
      'description': 'Trabajo ficticio',
      'unitCents': 100,
      'quantityMilli': 1000,
      'discountBps': 0,
      'taxBps': 2100,
      'tax': 'iva',
      'treatment': 'taxable',
      'reason': '',
    },
  ],
};

/// Fictional server used only to isolate client recovery and authorization.
/// This does not claim PostgreSQL transaction or hosted integration coverage.
class _SecurityRemote extends Remote {
  final state = WorkshopState.fromJson(
    demoState().toJson()
      ..['workshopId'] = '00000000-0000-4000-8000-000000000011',
  );
  Actor actor = _admin;
  String device = '';
  Map<String, dynamic> ledger = emptyFiscalDraftLedger();
  final fiscalCommands = <Map<String, dynamic>>[];
  String? readError;
  String? nextCommandError;
  bool incompleteAcknowledgement = false;

  _SecurityRemote() {
    state.configuration['settings'] = {
      ...state.settings,
      'fiscalProfile': {
        ...initialFiscalProfile(),
        'sii': 'no',
        'territory': 'common',
      },
    };
    state.members.add(_admin);
  }

  @override
  bool get requiresLease => true;
  @override
  void bindDevice(String id) => device = id;
  @override
  Future<Map<String, dynamic>> snapshot() async => {
    ...state.toJson(),
    'actor': actor.toJson(),
    'serverTime': _now.toIso8601String(),
  };
  @override
  Future<Map<String, dynamic>> fiscalDrafts() async {
    if (readError != null) {
      throw PostgrestException(
        message: 'Fictional ledger access denied',
        code: readError,
      );
    }
    return cloneMap(ledger);
  }

  @override
  Future<Map<String, dynamic>> push(
    Operation operation,
    String deviceId,
  ) async => {'status': 'accepted'};
  @override
  Future<void> reauthenticateReplacement(
    String email,
    String password,
    String expectedActor,
  ) async {}
  @override
  Future<Map<String, dynamic>> command(
    String id,
    String action,
    Map<String, dynamic> payload,
  ) async {
    if (action == 'replace_device') {
      return {'previousCommands': <Map<String, dynamic>>[]};
    }
    if (action != 'fiscal_draft_append') {
      throw StateError('Unexpected fictional command $action');
    }
    fiscalCommands.add({
      'id': id,
      'deviceId': device,
      'payload': cloneMap(payload),
    });
    if (nextCommandError != null) {
      final code = nextCommandError!;
      nextCommandError = null;
      throw PostgrestException(
        message: 'Fictional backend interruption',
        code: code,
      );
    }
    final body = {
      'draftFormat': 1,
      'scope': 'sandbox',
      'emissionEnabled': false,
      'transmissionEnabled': false,
      'id': id,
      'issuerNif': payload['issuerNif'],
      'installation': payload['installation'],
      'sequence': payload['expectedSequence'] + 1,
      'kind': 'draft',
      'prefix': payload['prefix'],
      'number': 1,
      'reason': payload['reason'],
      'actorId': actor.id,
      'deviceId': device,
      'createdAt': _now.toIso8601String(),
      'issueDate': payload['issueDate'],
      'recipient': payload['recipient'],
      'calculation': fiscalDraftCalculation(fiscalDraftRows(payload['lines'])),
    };
    final hash = await fiscalDraftLedgerHash(body, payload['expectedHash']);
    ledger = {
      ...emptyFiscalDraftLedger(),
      'heads': [
        {
          'workshop_id': state.workshopId,
          'issuer_nif': payload['issuerNif'],
          'installation': payload['installation'],
          'last_sequence': body['sequence'],
          'last_hash': hash,
          'restored': false,
        },
      ],
      'series': [
        {
          'workshop_id': state.workshopId,
          'issuer_nif': payload['issuerNif'],
          'installation': payload['installation'],
          'prefix': payload['prefix'],
          'last_number': 1,
        },
      ],
      'records': [
        {
          'workshop_id': state.workshopId,
          'id': id,
          'issuer_nif': payload['issuerNif'],
          'installation': payload['installation'],
          'sequence': body['sequence'],
          'kind': 'draft',
          'prefix': payload['prefix'],
          'number': 1,
          'target_id': null,
          'actor_id': actor.id,
          'device_id': device,
          'body': body,
          'previous_hash': payload['expectedHash'],
          'ledger_hash': hash,
        },
      ],
    };
    if (incompleteAcknowledgement) return {'saved': true, 'id': id};
    return {
      'saved': true,
      'id': id,
      'sequence': body['sequence'],
      'prefix': payload['prefix'],
      'number': 1,
      'ledgerHash': hash,
      'emissionEnabled': false,
      'transmissionEnabled': false,
    };
  }
}

Future<WorkshopController> _controller(
  _SecurityRemote remote,
  Vault vault,
) async {
  final c = WorkshopController(
    vault,
    remote: remote,
    actor: _admin,
    clock: () => _now,
  );
  addTearDown(c.dispose);
  await c.load();
  return c;
}

void main() {
  test(
    'Legacy recovery evidence cannot export private XML after role downgrade',
    () async {
      final remote = _SecurityRemote();
      final vault = Vault(
        MemoryStore(),
        await AesGcm.with256bits().newSecretKey(),
      );
      final c = await _controller(remote, vault);
      final legacy = await c.exportBackup();
      for (final key in [
        'fiscalDraftLedger',
        'fiscalDraftQueue',
        'fiscalDraftXmlArtifacts',
        'fiscalDraftsLoaded',
      ]) {
        legacy['local'].remove(key);
      }
      await c.refreshFiscalDrafts();
      await c.prepareFiscalDraft(_payload());
      final original = c.fiscalDraftQueue.single;
      final artifact = await c.generateFiscalDraftXml(original['id'], {
        'issuerName': 'Emisor ficticio',
        'manufacturerName': 'Fabricante ficticio',
        'manufacturerNif': 'B12345674',
        'name': 'TallerFlow ensayo',
        'id': 'TF',
        'version': '0.3-ensayo',
        'installation': 'fictional-installation',
        'onlyVerifactu': true,
        'canHaveMultipleTaxpayers': true,
        'hasMultipleTaxpayers': false,
      });
      await c.restoreLocalBackup(legacy);
      expect(c.localArchive()['fiscalDraftQueue'], isEmpty);
      expect(c.localArchive()['fiscalDraftLedger']['records'], isEmpty);
      expect(c.localArchive()['fiscalDraftXmlArtifacts'], isEmpty);
      final previous = c.localArchive()['restoredArchive']['previousLocal'];
      expect(previous['fiscalDraftQueue'].single['id'], original['id']);
      expect(
        previous['fiscalDraftXmlArtifacts'].single['xml'],
        artifact['xml'],
      );
      remote.actor = Actor(
        _admin.id,
        _admin.name,
        Role.office,
        seePrices: true,
      );
      await c.synchronize();
      expect(c.actor.role, Role.office);
      expect(c.accessAllowed, isTrue);
      await expectLater(c.exportBackup(), throwsA(isA<RuleException>()));
      final saved = await vault.read();
      expect(
        saved!['restoredArchive']['previousLocal']['fiscalDraftXmlArtifacts']
            .single['xml'],
        artifact['xml'],
      );
      expect(remote.fiscalCommands, hasLength(1));
    },
  );
  test(
    'A restored installation is visible but cannot enqueue a new identity',
    () async {
      final remote = _SecurityRemote();
      remote.ledger = {
        ...emptyFiscalDraftLedger(),
        'heads': [
          {
            'workshop_id': remote.state.workshopId,
            'issuer_nif': 'A12345678',
            'installation': 'fictional-installation',
            'last_sequence': 0,
            'last_hash': '',
            'restored': true,
          },
        ],
      };
      final c = await _controller(
        remote,
        Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
      );
      await c.refreshFiscalDrafts();
      expect(c.fiscalDraftLedger['heads'].single['restored'], true);
      c.offline = true;
      await expectLater(
        c.prepareFiscalDraft(_payload()),
        throwsA(isA<RuleException>()),
      );
      expect(c.fiscalDraftQueue, isEmpty);
      expect(remote.fiscalCommands, isEmpty);
    },
  );

  test(
    'Confirmed originals survive device replacement and encrypted restart',
    () async {
      final remote = _SecurityRemote();
      final vault = Vault(
        MemoryStore(),
        await AesGcm.with256bits().newSecretKey(),
      );
      final c = await _controller(remote, vault);
      await c.refreshFiscalDrafts();
      await c.prepareFiscalDraft(_payload());
      final original = c.fiscalDraftQueue.single;
      expect(original['status'], 'confirmed');
      final oldDevice = c.deviceId;
      await c.replaceRetiredDevice(
        email: 'fictional@example.invalid',
        password: 'fictional-password',
      );
      expect(c.deviceId, isNot(oldDevice));
      final restarted = await _controller(remote, vault);
      expect(restarted.fiscalDraftQueue.single['id'], original['id']);
      expect(restarted.fiscalDraftQueue.single['deviceId'], oldDevice);
      expect(restarted.fiscalDraftQueue.single['status'], 'confirmed');
      expect(
        restarted.fiscalDraftLedger['records'],
        c.fiscalDraftLedger['records'],
      );
      expect(remote.fiscalCommands, hasLength(1));
    },
  );

  test(
    'An old-device pending identity is preserved but never replayed by its replacement',
    () async {
      final remote = _SecurityRemote();
      final vault = Vault(
        MemoryStore(),
        await AesGcm.with256bits().newSecretKey(),
      );
      final c = await _controller(remote, vault);
      await c.refreshFiscalDrafts();
      c.offline = true;
      await c.prepareFiscalDraft(_payload());
      final original = c.fiscalDraftQueue.single;
      c.offline = false;
      await c.replaceRetiredDevice(
        email: 'fictional@example.invalid',
        password: 'fictional-password',
      );
      final restarted = await _controller(remote, vault);
      await restarted.synchronize();
      expect(remote.fiscalCommands, isEmpty);
      expect(restarted.fiscalDraftQueue.single['id'], original['id']);
      expect(restarted.fiscalDraftQueue.single['payload'], original['payload']);
      expect(
        restarted.fiscalDraftQueue.single['deviceId'],
        original['deviceId'],
      );
      expect(restarted.fiscalDraftQueue.single['status'], 'conflict');
    },
  );

  test(
    'A denied initial reconciliation read revokes the lease and retains the request',
    () async {
      final remote = _SecurityRemote();
      final vault = Vault(
        MemoryStore(),
        await AesGcm.with256bits().newSecretKey(),
      );
      final c = await _controller(remote, vault);
      await c.refreshFiscalDrafts();
      c.offline = true;
      await c.prepareFiscalDraft(_payload());
      final original = c.fiscalDraftQueue.single;
      c.offline = false;
      remote.readError = '42501';
      await expectLater(
        c.retryFiscalDraft(original['id']),
        throwsA(isA<PostgrestException>()),
      );
      expect(c.accessAllowed, false);
      expect(c.accessRevoked, true);
      expect(c.localArchive()['fiscalDraftQueue'].single['id'], original['id']);
      expect(c.localArchive()['fiscalDraftQueue'].single['status'], 'pending');
      expect(remote.fiscalCommands, isEmpty);
      final restarted = await _controller(remote, vault);
      expect(restarted.accessAllowed, false);
    },
  );

  test(
    'Role downgrade hides cached originals and forbids administrative actions',
    () async {
      final remote = _SecurityRemote();
      final c = await _controller(
        remote,
        Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
      );
      await c.refreshFiscalDrafts();
      await c.prepareFiscalDraft(_payload());
      remote.actor = Actor(
        _admin.id,
        _admin.name,
        Role.office,
        seePrices: true,
      );
      await c.synchronize();
      expect(c.actor.role, Role.office);
      expect(c.fiscalDraftsLoaded, false);
      expect(c.fiscalDraftQueue, isEmpty);
      expect(c.fiscalDraftLedger['records'], isEmpty);
      await expectLater(
        c.prepareFiscalDraft(_payload()),
        throwsA(isA<RuleException>()),
      );
      await expectLater(c.refreshFiscalDrafts(), throwsA(isA<RuleException>()));
      await expectLater(c.exportBackup(), throwsA(isA<RuleException>()));
      expect(remote.fiscalCommands, hasLength(1));
    },
  );

  test(
    'Encrypted cache rejects a confirmed request without its immutable original',
    () async {
      final remote = _SecurityRemote();
      final vault = Vault(
        MemoryStore(),
        await AesGcm.with256bits().newSecretKey(),
      );
      final c = await _controller(remote, vault);
      await c.refreshFiscalDrafts();
      c.offline = true;
      await c.prepareFiscalDraft(_payload());
      final changed = cloneMap(c.localArchive());
      changed['fiscalDraftQueue'].single['status'] = 'confirmed';
      changed['fiscalDraftQueue'].single['result'] = {'saved': true};
      await vault.write(changed);
      final restarted = WorkshopController(
        vault,
        remote: remote,
        actor: _admin,
        clock: () => _now,
      );
      addTearDown(restarted.dispose);
      await expectLater(restarted.load(), throwsA(isA<RuleException>()));
      expect(remote.fiscalCommands, isEmpty);
    },
  );

  test(
    'Backend connection errors keep the exact pending identity across restart',
    () async {
      final remote = _SecurityRemote()..nextCommandError = '08P01';
      final vault = Vault(
        MemoryStore(),
        await AesGcm.with256bits().newSecretKey(),
      );
      final c = await _controller(remote, vault);
      await c.refreshFiscalDrafts();
      await expectLater(
        c.prepareFiscalDraft(_payload()),
        throwsA(isA<PostgrestException>()),
      );
      final original = c.fiscalDraftQueue.single;
      expect(original['status'], 'pending');
      final restarted = await _controller(remote, vault);
      await restarted.retryFiscalDraft(original['id']);
      expect(restarted.fiscalDraftQueue.single['status'], 'confirmed');
      expect(remote.fiscalCommands.map((r) => r['id']).toSet(), {
        original['id'],
      });
      expect(remote.fiscalCommands.map((r) => r['payload']).toList(), [
        original['payload'],
        original['payload'],
      ]);
    },
  );

  test(
    'A committed but incomplete acknowledgement is recovered without resubmitting',
    () async {
      final remote = _SecurityRemote()..incompleteAcknowledgement = true;
      final vault = Vault(
        MemoryStore(),
        await AesGcm.with256bits().newSecretKey(),
      );
      final c = await _controller(remote, vault);
      await c.refreshFiscalDrafts();
      await expectLater(
        c.prepareFiscalDraft(_payload()),
        throwsA(isA<RuleException>()),
      );
      final original = c.fiscalDraftQueue.single;
      expect(original['status'], 'pending');
      final restarted = await _controller(remote, vault);
      await restarted.retryFiscalDraft(original['id']);
      expect(restarted.fiscalDraftQueue.single['status'], 'confirmed');
      expect(remote.fiscalCommands, hasLength(1));
    },
  );
}
