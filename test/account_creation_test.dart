import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/simulation.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/domain/engine.dart';

const secret = 'fictional-test-password';
final preferences = {
  'email': 'MECHANIC@example.invalid',
  'name': 'Fictional mechanic',
  'role': 'technician',
  'seePrices': false,
  'seeCosts': false,
  'reason': 'Fictional test',
  'password': 'Must not be persisted',
};

class AccountRemote extends SimulatedRemote {
  bool lose = true;
  final requests = <String>{};
  AccountRemote() : super(SimulatedWorkshop(), demoActors[3]);
  @override
  Future<Map<String, dynamic>> createMember(
    String id,
    Map<String, dynamic> p,
    String password,
  ) async {
    expect(password, secret);
    expect(p.containsKey('password'), false);
    requests.add(id);
    if (lose) {
      lose = false;
      throw StateError('Fictional interrupted response');
    }
    return {'created': true, 'userId': 'fictional-account'};
  }
}

class AccountStore extends MemoryStore {
  bool fail = false;
  @override
  Future<void> write(String value) async {
    if (fail) throw StateError('Fictional disk error');
    await super.write(value);
  }
}

void main() {
  test(
    'Interrupted account creation survives restart and backup with a stable ID and no credentials',
    () async {
      final remote = AccountRemote(),
          store = MemoryStore(),
          key = await AesGcm.with256bits().newSecretKey();
      final c = WorkshopController(
        Vault(store, key),
        remote: remote,
        actor: demoActors[3],
      );
      await c.load();
      await expectLater(c.createMember(preferences, secret), throwsStateError);
      final id = c.pendingAccountCreation!['id'];
      final archive = await c.exportBackup();
      final encoded = jsonEncode(archive);
      expect(encoded.contains(secret), false);
      expect(encoded.contains('Must not be persisted'), false);
      expect(c.pendingCommands, isEmpty);
      c.dispose();
      final restored = WorkshopController(
        Vault(store, key),
        remote: remote,
        actor: demoActors[3],
      );
      await restored.load();
      expect(restored.pendingAccountCreation!['id'], id);
      await restored.createMember(preferences, secret);
      expect(remote.requests, {id});
      expect(restored.pendingAccountCreation, isNull);
      expect(restored.accountCreationHistory.single['status'], 'created');
      restored.dispose();
    },
  );
  test('Failed durable save prevents any remote account creation', () async {
    final remote = AccountRemote(), store = AccountStore();
    final c = WorkshopController(
      Vault(store, await AesGcm.with256bits().newSecretKey()),
      remote: remote,
      actor: demoActors[3],
    );
    await c.load();
    store.fail = true;
    await expectLater(c.createMember(preferences, secret), throwsStateError);
    expect(remote.requests, isEmpty);
    expect(c.pendingAccountCreation, isNull);
    c.dispose();
  });
  test(
    'Different pending payload is rejected and archival preserves uncertain identity for retry',
    () async {
      final remote = AccountRemote();
      final c = WorkshopController(
        Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
        remote: remote,
        actor: demoActors[3],
      );
      await c.load();
      await expectLater(c.createMember(preferences, secret), throwsStateError);
      final id = c.pendingAccountCreation!['id'];
      await expectLater(
        c.createMember({
          ...preferences,
          'email': 'other@example.invalid',
        }, secret),
        throwsA(isA<RuleException>()),
      );
      await c.archiveAccountCreation('Review uncertain result');
      expect(c.accountCreationHistory.single['id'], id);
      await c.createMember(preferences, secret);
      expect(remote.requests, {id});
      c.dispose();
    },
  );
  test(
    'Revoked access, short passwords and unsupported cost permissions prevent network effects',
    () async {
      final remote = AccountRemote();
      final c = WorkshopController(
        Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
        remote: remote,
        actor: demoActors[3],
      );
      await c.load();
      await expectLater(
        c.createMember(preferences, 'short'),
        throwsA(isA<RuleException>()),
      );
      await expectLater(
        c.createMember({...preferences, 'seeCosts': true}, secret),
        throwsA(isA<RuleException>()),
      );
      c.offline = true;
      await expectLater(
        c.createMember(preferences, secret),
        throwsA(isA<RuleException>()),
      );
      expect(remote.requests, isEmpty);
      c.dispose();
    },
  );
}
