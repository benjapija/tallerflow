import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/simulation.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/portal.dart';
import 'package:tallerflow/ui/portal_panel.dart';

class LostPortalReply extends SimulatedRemote {
  bool lose = true;
  final Map<String, Map<String, dynamic>> received = {};
  LostPortalReply(super.workshop, super.actor);
  @override
  Future<Map<String, dynamic>> command(
    String id,
    String action,
    Map<String, dynamic> p,
  ) async {
    received.putIfAbsent(id, () => {'action': action, 'payload': p});
    if (lose) {
      lose = false;
      throw StateError('Lost committed portal reply');
    }
    return {'saved': true};
  }
}

class BrokenStore extends MemoryStore {
  bool fail = false;
  @override
  Future<void> write(String value) async {
    if (fail) throw StateError('Local persistence unavailable');
    await super.write(value);
  }
}

void main() {
  test(
    'Independent secrets are strong, hashed and confined to fragment',
    () async {
      final a = PortalCredentials.generate();
      final b = PortalCredentials.generate();
      expect(a.token.length, 64);
      expect(a.code.length, 32);
      expect(a.token, isNot(b.token));
      expect(a.code, isNot(b.code));
      expect(a.id, isNot(b.id));
      final h = await a.hashes();
      expect(h['tokenHash']!.length, 64);
      expect(h['codeHash'], isNot(a.code));
      final uri = Uri.parse(a.link('https://portal.example.invalid'));
      expect(uri.query, isEmpty);
      expect(uri.fragment, 'access=${a.id}.${a.token}');
      expect(uri.toString().contains(a.code), false);
    },
  );
  test('Portal address rejects embedded credentials and insecure links', () {
    for (final v in [
      'http://portal.invalid',
      'https://user:secret@portal.invalid',
      'https://portal.invalid?key=secret',
      'https://portal.invalid#access=x',
    ]) {
      expect(() => validatePortalUrl(v), throwsA(isA<RuleException>()));
    }
    expect(validatePortalUrl(''), '');
    expect(
      validatePortalUrl('https://portal.invalid/customer/'),
      'https://portal.invalid/customer/',
    );
  });
  test(
    'Lost grant reply preserves hashes and retry identity without secrets',
    () async {
      final actor = demoActors.firstWhere((a) => a.isOffice);
      final remote = LostPortalReply(SimulatedWorkshop(), actor);
      final vault = Vault(
        MemoryStore(),
        await AesGcm.with256bits().newSecretKey(),
      );
      final c = WorkshopController(vault, actor: actor, remote: remote);
      await c.load();
      await expectLater(
        () => c.createPortal({'reason': 'Fictional access'}),
        throwsStateError,
      );
      final pending = c.pendingCommands.single;
      final payload = pending['payload'];
      expect(payload['token'], isNull);
      expect(payload['code'], isNull);
      expect(payload['tokenHash'].length, 64);
      expect(payload['codeHash'].length, 64);
      expect(jsonEncode(await vault.read()).contains('"token":'), false);
      c.dispose();
      final next = WorkshopController(vault, actor: actor, remote: remote);
      await next.load();
      await next.synchronize();
      expect(remote.received.length, 1);
      expect(remote.received.keys.single, pending['id']);
      expect(next.pendingCommands, isEmpty);
      next.dispose();
    },
  );
  test('Configuration rolls back if encrypted persistence fails', () async {
    final store = BrokenStore();
    final c = WorkshopController(
      Vault(store, await AesGcm.with256bits().newSecretKey()),
      actor: demoActors.firstWhere((a) => a.role.name == 'admin'),
    );
    await c.load();
    final before = {...c.state.settings};
    store.fail = true;
    await expectLater(
      () => c.portal('portal_configure', {
        'url': 'https://portal.invalid',
        'reason': 'Fictional setup',
      }),
      throwsStateError,
    );
    expect(c.state.settings, before);
    c.dispose();
  });
  testWidgets('Demo cannot issue live customer credentials', (tester) async {
    final c = WorkshopController(
      Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
    );
    await c.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PortalPanel(
            controller: c,
            order: c.state.orders.values.first,
            run: (f) => f(),
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Crear acceso temporal'),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('requiere un taller conectado'), findsOneWidget);
    c.dispose();
  });
}
