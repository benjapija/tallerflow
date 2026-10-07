import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/simulation.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/diagnosis_notebook.dart';
import 'package:tallerflow/ui/diagnosis_panel.dart';

class LostDiagnosisReply extends SimulatedRemote {
  bool lose = true;
  LostDiagnosisReply(super.workshop, super.actor);
  @override
  Future<Map<String, dynamic>> push(Operation op, String deviceId) async {
    final r = await super.push(op, deviceId);
    if (lose) {
      lose = false;
      throw StateError('Lost committed diagnosis reply');
    }
    return r;
  }
}

void main() {
  test(
    'Offline diagnosis survives restart and lost reply without duplicate evidence',
    () async {
      final tech = demoActors[0], server = SimulatedWorkshop();
      server.state.orders['o-1048']!.tasks.first['assignees'] = [tech.id];
      final remote = LostDiagnosisReply(server, tech),
          vault = Vault(
            MemoryStore(),
            await AesGcm.with256bits().newSecretKey(),
          );
      final c = WorkshopController(vault, remote: remote, actor: tech);
      await c.load();
      c.offline = true;
      remote.disconnected = true;
      await c.execute('o-1048', 'diagnosis_add', {
        'stage': 'result',
        'text': 'Fictional measured 12.2 V',
        'confirmed': false,
        'context': 'Ignition off',
        'dtcs': 'P0000',
        'source': 'Fictional authorized document',
      });
      final id = c.outbox.single.id;
      final reopened = WorkshopController(vault, remote: remote, actor: tech);
      await reopened.load();
      expect(reopened.outbox.single.id, id);
      remote.disconnected = false;
      reopened.offline = false;
      await reopened.synchronize();
      expect(reopened.outbox.single.id, id);
      await reopened.synchronize();
      expect(reopened.outbox, isEmpty);
      final rows = diagnosisEntries(server.state.orders['o-1048']!);
      expect(rows.length, 1);
      expect(rows.single['id'], id);
      expect(diagnosisEntries(reopened.state.orders['o-1048']!), rows);
    },
  );
  testWidgets(
    'A conclusion cannot be saved through the form without personal confirmation',
    (tester) async {
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiagnosisPanel(
              order: demoState().orders['o-1048']!,
              actor: demoActors[0],
              onSave: (_, p, _) async => saved = p,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Añadir entrada'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Síntoma'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Conclusión confirmada').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          'Observación, comprobación o resultado',
        ),
        'Fictional diagnosis',
      );
      await tester.tap(find.text('Confirmar y guardar'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(
        find.text('Confirma personalmente la conclusión o verificación'),
        findsOneWidget,
      );
    },
  );
}
