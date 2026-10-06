import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/simulation.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/domain/csv_import.dart';
import 'package:tallerflow/domain/engine.dart';

Uint8List csv(String text) => Uint8List.fromList(utf8.encode(text));

class InterruptedImportRemote extends SimulatedRemote {
  bool lose = true;
  final calls = <String>[];
  InterruptedImportRemote() : super(SimulatedWorkshop(), demoActors[3]);
  @override
  Future<Map<String, dynamic>> command(
    String id,
    String action,
    Map<String, dynamic> p,
  ) async {
    final result = await super.command(id, action, p);
    if (action == 'import_commit') {
      calls.add(id);
      if (lose) {
        lose = false;
        throw StateError('Fictional lost import response');
      }
    }
    return result;
  }
}

void main() {
  test(
    'CSV handles BOM, escaped quotes, quoted delimiters and physical line numbers',
    () {
      final r = readCsv(
        csv(
          '\uFEFFcodigo;nombre;telefono;email;nif;direccion\r\nC1;"Cliente; prueba";;;;"Línea 1\nLínea ""2"""\r\nC2;Otro;;;;\r\n',
        ),
      );
      expect(r[1].cells[1], 'Cliente; prueba');
      expect(r[1].cells.last, 'Línea 1\nLínea "2"');
      expect(r[2].line, 4);
    },
  );
  test(
    'Malformed quotes, incorrect UTF-8, oversized fields and excessive rows are rejected',
    () {
      for (final value in [
        'a;b\n"unfinished;b',
        'a;b\n"closed"suffix;b',
        'a;b\nplain"quote;b',
      ]) {
        expect(() => readCsv(csv(value)), throwsFormatException);
      }
      expect(
        () => readCsv(Uint8List.fromList([255, 255])),
        throwsFormatException,
      );
      expect(() => readCsv(csv('a\n${'x' * 2001}')), throwsFormatException);
      expect(() => readCsv(csv('a\n${'x\n' * 501}')), throwsFormatException);
    },
  );
  test(
    'Decimal quantities and money remain exact; integer odometer rejects decimal or exponent',
    () {
      expect(decimalValue('12,35', 2, 100000, 'precio'), 1235);
      expect(decimalValue('1.125', 3, 100000, 'litros'), 1125);
      expect(decimalValue('128450', 0, 10000000, 'km'), 128450);
      for (final value in ['1e3', '1,000.50', '2.001', '-1']) {
        expect(
          () => decimalValue(value, 2, 100000, 'precio'),
          throwsFormatException,
        );
      }
      expect(() => decimalValue('1.5', 0, 1000, 'km'), throwsFormatException);
    },
  );
  test(
    'Preview detects in-file and current duplicates and keeps invalid rows without writing',
    () {
      final s = demoState();
      final input =
          '${importTemplate(ImportKind.clients)}C1;Cliente ficticio;600000000;fictional@example.invalid;X0000000T;Calle de prueba\nC1;Otro;;;;\nC2;Mal correo;;invalid;;\n';
      final p = previewCsv(csv(input), ImportKind.clients, s, demoActors[3]);
      expect(p.rows.map((r) => r.status), ['ready', 'duplicate', 'error']);
      expect(s.configuration['clients'], isNull);
      expect(p.payload('Prueba')['rows'].length, 2);
      expect(
        () => previewCsv(csv(input), ImportKind.clients, s, demoActors[0]),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Catalog keeps unknown cost distinct from known zero and preserves existing references',
    () {
      final s = demoState();
      final p = previewCsv(
        csv(
          '${importTemplate(ImportKind.catalog)}NEW;Pieza ficticia;ud;12,35;;21;1,125;0;Proveedor ficticio\n',
        ),
        ImportKind.catalog,
        s,
        demoActors[3],
      );
      expect(p.rows.single.data!['costKnown'], false);
      expect(p.rows.single.data!['stockMilli'], 1125);
      final result = applyDemoImport(
        s,
        p.id,
        p.payload('Ficticio'),
        demoActors[3],
        DateTime.now(),
      );
      expect(result['created'], 1);
      final second = previewCsv(
        csv(
          '${importTemplate(ImportKind.catalog)}NEW;Otro;ud;99;0;21;10;0;Proveedor\n',
        ),
        ImportKind.catalog,
        s,
        demoActors[3],
      );
      expect(second.rows.single.status, 'duplicate');
      applyDemoImport(
        s,
        second.id,
        second.payload('Ficticio'),
        demoActors[3],
        DateTime.now(),
      );
      expect(s.catalog.last.priceCents, 1235);
      expect(
        () => previewCsv(
          csv(importTemplate(ImportKind.catalog)),
          ImportKind.catalog,
          s,
          demoActors[2],
        ),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Preview consistently detects repeated tax IDs, VINs and references without committing',
    () {
      final s = demoState();
      s.configuration['clients'] = [
        {
          'id': 'fictional-client',
          'code': 'C1',
          'name': 'Ficticio',
          'phone': '',
        },
      ];
      final clients = previewCsv(
        csv(
          '${importTemplate(ImportKind.clients)}C2;Uno;;;X0000000T;\nC3;Dos;;;X0000000T;\n',
        ),
        ImportKind.clients,
        s,
        demoActors[3],
      );
      expect(clients.rows.map((r) => r.status), ['ready', 'duplicate']);
      for (final item in [
        (
          ImportKind.vehicles,
          '0001ZZZ;ES;FAKEVIN;Ficticio;;10;C1\n0002ZZZ;ES;FAKEVIN;Ficticio;;10;C1\n',
        ),
        (
          ImportKind.catalog,
          'TEST;Uno;ud;1;;21;0;0;\nTEST;Dos;ud;1;;21;0;0;\n',
        ),
      ]) {
        final p = previewCsv(
          csv('${importTemplate(item.$1)}${item.$2}'),
          item.$1,
          s,
          demoActors[3],
        );
        expect(p.rows.map((r) => r.status), ['ready', 'duplicate']);
        final result = applyDemoImport(
          s,
          p.id,
          p.payload('Ficticio'),
          demoActors[3],
          DateTime.now(),
          writing: false,
        );
        expect((result['rows'] as List).map((r) => r['status']), [
          'ready',
          'duplicate',
        ]);
        expect(result['created'], 0);
      }
      expect(s.audit.where((a) => a['kind'] == 'csv_import'), isEmpty);
    },
  );
  test(
    'Lost import response survives restart and retries one batch without duplicating customers or audit',
    () async {
      final remote = InterruptedImportRemote(),
          store = MemoryStore(),
          key = await AesGcm.with256bits().newSecretKey();
      final c = WorkshopController(
        Vault(store, key),
        remote: remote,
        actor: demoActors[3],
      );
      await c.load();
      final p = previewCsv(
        csv('${importTemplate(ImportKind.clients)}C1;Ficticio;;;;\n'),
        ImportKind.clients,
        c.state,
        c.actor,
      );
      await expectLater(c.commitImport(p, 'Carga ficticia'), throwsStateError);
      expect(c.pendingCommands.single['id'], p.id);
      c.dispose();
      final target = WorkshopController(
        Vault(store, key),
        remote: remote,
        actor: demoActors[3],
      );
      await target.load();
      await target.synchronize();
      expect(target.pendingCommands, isEmpty);
      expect(remote.calls, [p.id, p.id]);
      expect(target.state.configuration['clients'].length, 1);
      expect(
        target.state.audit.where((a) => a['kind'] == 'csv_row_imported').length,
        1,
      );
      target.dispose();
    },
  );
}
