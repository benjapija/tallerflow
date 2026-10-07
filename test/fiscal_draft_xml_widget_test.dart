import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/domain/models.dart';
import 'package:tallerflow/ui/fiscal_draft_xml_panel.dart';

const _admin = Actor('admin-test', 'Administradora ficticia', Role.admin);
const _id = '00000000-0000-4000-8000-000000000201';
const _xml =
    '<?xml version="1.0" encoding="UTF-8"?><Ensayo>Revisión ficticia &amp; óleo</Ensayo>';

Map<String, dynamic> _record() => {
  'id': _id,
  'kind': 'draft',
  'issuer_nif': 'B12345674',
  'installation': 'PRUEBAS-XML',
  'prefix': 'ENSAYO-XML',
  'number': 1,
  'sequence': 1,
  'body': {
    'id': _id,
    'kind': 'draft',
    'issuerNif': 'B12345674',
    'installation': 'PRUEBAS-XML',
  },
};

Map<String, dynamic> _artifact() => {
  'recordId': _id,
  'sequence': 1,
  'generatorVersion': 'generador-ficticio-1',
  'generatedAt': '2026-10-07T15:00:00+02:00',
  'ledgerHash': 'A' * 64,
  'aeatHash': 'B' * 64,
  'xmlSha256': 'C' * 64,
  'xml': _xml,
  'snapshot': {
    'sourceRecord': _record(),
    'issuer': {'name': 'Emisor ficticio conservado', 'nif': 'B12345674'},
    'system': {
      'manufacturer': {
        'name': 'Fabricante ficticio conservado',
        'nif': 'B12345674',
      },
      'name': 'Sistema conservado',
      'id': 'TF',
      'version': '0.3-ensayo-original',
      'installation': 'PRUEBAS-XML',
      'onlyVerifactu': true,
      'canHaveMultipleTaxpayers': true,
      'hasMultipleTaxpayers': false,
    },
  },
};

Widget _panel({
  Actor actor = _admin,
  bool accessAllowed = true,
  List<Map<String, dynamic>>? records,
  List<Map<String, dynamic>> artifacts = const [],
  Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)? generate,
  Future<void> Function(Uint8List, String)? save,
}) => FiscalDraftXmlPanel(
  actor: actor,
  accessAllowed: accessAllowed,
  confirmedRecords: records ?? [_record()],
  artifacts: artifacts,
  onGenerate: generate ?? (_, _) async => _artifact(),
  onSaveBytes: save,
);

Future<void> _show(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'XML interface only exposes confirmed originals to active admin with valid session',
    (tester) async {
      for (final actor in [
        const Actor('office', 'Oficina', Role.office),
        const Actor('operator', 'Operario', Role.technician),
        const Actor(
          'inactive',
          'Administrador retirado',
          Role.admin,
          active: false,
        ),
      ]) {
        await _show(tester, _panel(actor: actor, artifacts: [_artifact()]));
        expect(find.text('Preparar XML'), findsNothing);
        expect(find.textContaining('generador-ficticio-1'), findsNothing);
      }
      await _show(
        tester,
        _panel(accessAllowed: false, artifacts: [_artifact()]),
      );
      expect(
        find.text('Renueva tu sesión para consultar los XML de ensayo.'),
        findsOneWidget,
      );
      expect(find.textContaining('generador-ficticio-1'), findsNothing);
      await _show(tester, _panel(records: [], artifacts: [_artifact()]));
      expect(find.text('Preparar XML'), findsNothing);
      expect(
        find.textContaining(
          'Las solicitudes locales pendientes no generan XML',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('generador-ficticio-1'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Generation needs explicit fictitious review and preserves confirmed source identity',
    (tester) async {
      String? requested;
      Map<String, dynamic>? settings;
      await _show(
        tester,
        _panel(
          generate: (id, data) async {
            requested = id;
            settings = data;
            return _artifact();
          },
        ),
      );
      await _tap(tester, find.text('Preparar XML'));
      await _tap(tester, find.text('Generar y conservar XML de ensayo'));
      expect(requested, isNull);
      expect(
        find.text('Confirma la revisión del ensayo antes de generar el XML.'),
        findsOneWidget,
      );
      await _tap(tester, find.byKey(const ValueKey('fiscal-xml-review')));
      await _tap(tester, find.text('Generar y conservar XML de ensayo'));
      expect(requested, _id);
      expect(settings!['issuerName'], 'Taller ficticio de ensayo');
      expect(settings!['manufacturerName'], 'Fabricante ficticio de ensayo');
      expect(settings!['installation'], 'PRUEBAS-XML');
      expect(settings!['name'], 'TallerFlow ensayo');
      expect(settings!['id'], 'TF');
      expect(settings!['version'], '0.3-ensayo');
      expect(settings!['onlyVerifactu'], isTrue);
      expect(settings!.containsKey('emissionEnabled'), isFalse);
      expect(settings!.containsKey('transmissionEnabled'), isFalse);
      expect(find.textContaining('No se ha enviado'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Existing chain keeps technical fields locked and returns original settings',
    (tester) async {
      Map<String, dynamic>? requested;
      await _show(
        tester,
        _panel(
          artifacts: [_artifact()],
          generate: (_, data) async {
            requested = data;
            return _artifact();
          },
        ),
      );
      await _tap(tester, find.text('Preparar XML'));
      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(field.readOnly, isTrue);
      }
      expect(find.textContaining('Esta cadena ya tiene XML'), findsOneWidget);
      for (final checkbox
          in tester
              .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
              .where((c) => c.key != const ValueKey('fiscal-xml-review'))) {
        expect(checkbox.onChanged, isNull);
      }
      await _tap(tester, find.byKey(const ValueKey('fiscal-xml-review')));
      await _tap(tester, find.text('Generar y conservar XML de ensayo'));
      expect(requested!['issuerName'], 'Emisor ficticio conservado');
      expect(requested!['manufacturerName'], 'Fabricante ficticio conservado');
      expect(requested!['version'], '0.3-ensayo-original');
      expect(requested!['hasMultipleTaxpayers'], isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Preview distinguishes both hashes and saves exact UTF-8 XML bytes with revision filename',
    (tester) async {
      Uint8List? saved;
      String? filename;
      await _show(
        tester,
        _panel(
          artifacts: [_artifact()],
          save: (bytes, name) async {
            saved = bytes;
            filename = name;
          },
        ),
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('fiscal-xml-$_id-generador-ficticio-1')),
      );
      expect(
        find.text('Huella interna del registro: ${'A' * 64}'),
        findsOneWidget,
      );
      expect(
        find.text('Huella AEAT del XML de ensayo: ${'B' * 64}'),
        findsOneWidget,
      );
      expect(
        find.textContaining('No acredita envío, firma ni aceptación oficial'),
        findsOneWidget,
      );
      await _tap(tester, find.text('Vista previa del XML técnico'));
      expect(find.text(_xml), findsOneWidget);
      await _tap(tester, find.text('Guardar XML de ensayo'));
      expect(saved, utf8.encode(_xml));
      expect(filename, contains('ENSAYO-XML'));
      expect(filename, contains('generador-ficticio-1'));
      expect(filename, endsWith('.xml'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Contradictory multi-taxpayer declarations cannot generate', (
    tester,
  ) async {
    var calls = 0;
    await _show(
      tester,
      _panel(
        generate: (_, _) async {
          calls++;
          return _artifact();
        },
      ),
    );
    await _tap(tester, find.text('Preparar XML'));
    await _tap(
      tester,
      find.text('El sistema de ensayo admite varios obligados'),
    );
    await _tap(tester, find.byKey(const ValueKey('fiscal-xml-review')));
    await _tap(tester, find.text('Generar y conservar XML de ensayo'));
    expect(calls, 0);
    expect(
      find.text(
        'Revisa las opciones de varios obligados: la capacidad debe estar declarada.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Failure keeps original and has no success or transmission claim',
    (tester) async {
      final record = _record();
      await _show(
        tester,
        _panel(
          records: [record],
          generate: (_, _) async {
            throw const FormatException('Caso técnico no admitido');
          },
        ),
      );
      await _tap(tester, find.text('Preparar XML'));
      await _tap(tester, find.byKey(const ValueKey('fiscal-xml-review')));
      await _tap(tester, find.text('Generar y conservar XML de ensayo'));
      expect(find.textContaining('Caso técnico no admitido'), findsOneWidget);
      expect(find.textContaining('XML de ensayo conservado'), findsNothing);
      expect(record, _record());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Mobile view wraps immutable hash details and hides artifacts after source changes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _show(tester, _panel(artifacts: [_artifact()]));
      await _tap(
        tester,
        find.byKey(const ValueKey('fiscal-xml-$_id-generador-ficticio-1')),
      );
      expect(
        find.textContaining('Huella AEAT del XML de ensayo'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _show(tester, _panel(records: [], artifacts: [_artifact()]));
      expect(
        find.textContaining('Huella AEAT del XML de ensayo'),
        findsNothing,
      );
      expect(find.text('Guardar XML de ensayo'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
