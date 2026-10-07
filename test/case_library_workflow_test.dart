import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/simulation.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/domain/case_library.dart';
import 'package:tallerflow/ui/case_library_panel.dart';
import 'case_library_test.dart' as fixtures;

class LostCaseReply extends SimulatedRemote {
  bool lose = true;
  LostCaseReply(super.workshop, super.actor);
  @override
  Future<Map<String, dynamic>> command(
    String id,
    String action,
    Map<String, dynamic> p,
  ) async {
    final r = await super.command(id, action, p);
    if (lose) {
      lose = false;
      throw StateError('Lost committed case reply');
    }
    return r;
  }
}

void main() {
  test(
    'Offline draft survives encrypted backup and restart; lost reply publishes one version',
    () async {
      final server = SimulatedWorkshop()..state = fixtures.fixture();
      final remote = LostCaseReply(server, fixtures.tech);
      final vault = Vault(
        MemoryStore(),
        await AesGcm.with256bits().newSecretKey(),
      );
      final c = WorkshopController(vault, actor: fixtures.tech, remote: remote);
      await c.load();
      c.offline = true;
      await c.library('case_draft', fixtures.draft());
      final pending = c.pendingCommands.single;
      expect(
        (await c.exportBackup(
          splitFiles: true,
        ))['local']['pendingCommands'].single['id'],
        pending['id'],
      );
      c.dispose();
      final reopened = WorkshopController(
        vault,
        actor: fixtures.tech,
        remote: remote,
      );
      await reopened.load();
      expect(reopened.pendingCommands.single, pending);
      reopened.offline = false;
      await reopened.synchronize();
      expect(reopened.pendingCommands.length, 1);
      await reopened.synchronize();
      expect(reopened.pendingCommands, isEmpty);
      expect(libraryCases(server.state).single['versions'].length, 1);
      await reopened.library('case_validate', fixtures.validation(1, 1));
      expect(libraryCases(server.state).single['activeVersion'], 1);
      final other = server.snapshot(fixtures.office, 'office-device');
      expect(other['caseLibrary'].length, 1);
      reopened.dispose();
    },
  );
  test(
    'A stale dialog cannot validate a withdrawn or changed version',
    () async {
      final server = SimulatedWorkshop()..state = fixtures.fixture();
      fixtures.apply(server.state, 'case_draft', fixtures.draft());
      fixtures.apply(server.state, 'case_validate', fixtures.validation(1, 1));
      final vault = Vault(
        MemoryStore(),
        await AesGcm.with256bits().newSecretKey(),
      );
      final c = WorkshopController(
        vault,
        actor: fixtures.tech,
        remote: SimulatedRemote(server, fixtures.tech),
      );
      await c.load();
      fixtures.apply(server.state, 'case_withdraw', {
        'id': 'case-1',
        'revision': 2,
        'reason': 'Fault returned',
      });
      await c.synchronize();
      await expectLater(
        () => c.library('case_validate', fixtures.validation(2, 1)),
        throwsA(isA<Exception>()),
      );
      expect(libraryCases(server.state).single['withdrawn'], true);
      c.dispose();
    },
  );
  testWidgets(
    'Publication form defaults to pending and refuses absent privacy review',
    (tester) async {
      final vault = Vault(
        MemoryStore(),
        await AesGcm.with256bits().newSecretKey(),
      );
      final c = WorkshopController(vault, actor: fixtures.tech);
      await c.load();
      c.state = fixtures.fixture();
      fixtures.apply(c.state, 'case_draft', fixtures.draft());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CaseLibraryPanel(controller: c, run: (f) => f()),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Validar último borrador'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Evidencia y motivo de validación'),
        'Fictional review',
      );
      await tester.tap(find.text('Confirmar y guardar'));
      await tester.pumpAndSettle();
      expect(
        find.text('Confirma ambas revisiones antes de publicar'),
        findsOneWidget,
      );
      expect(libraryCases(c.state).single['activeVersion'], isNull);
      c.dispose();
    },
  );
}
