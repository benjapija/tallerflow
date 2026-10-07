import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:tallerflow/ui/document_export_button.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/document_pdf.dart';
import 'package:tallerflow/domain/document_export.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/models.dart';
import 'quotes_test.dart' as quotes;

WorkOrder noteFixture({int rows = 2}) {
  final o = demoState().orders.values.first;
  o.data['document'] = {
    'issuedAt': '2026-10-07T08:00:00Z',
    'revision': 7,
    'clientSnapshot': 'Cliente ficticio Álvarez',
    'plateSnapshot': '4321FIC',
    'netCents': 1502 * rows,
    'taxCents': 315 * rows,
    'totalCents': 1817 * rows,
    'lines': [
      for (var n = 0; n < rows; n++)
        {
          'description':
              'Comprobación ${n + 1}: aceite, frenos y revisión de síntomas',
          'quantity': '1,5 L',
          'netCents': 1502,
          'taxCents': 315,
          'discountCents': 150,
          'costCents': 999,
        },
    ],
    'closureException':
        'Excepción ficticia revisada por oficina; evidencia pendiente conservada',
  };
  return o;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Export asks for workshop identity and cancellation preserves the saved note',
    (tester) async {
      final o = noteFixture(), before = cloneMap(noteFixture().data);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentExportButton(
              source: () => DocumentExport.note(o, demoActors[2]),
              filename: 'fictional.pdf',
            ),
          ),
        ),
      );
      await tester.tap(find.text('Guardar PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Datos del taller para esta copia PDF'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Guardar PDF'), findsOneWidget);
      expect(o.data, before);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'Export uses original recipient and prices, excludes costs, and cannot mutate the note',
    () {
      final o = noteFixture(), before = cloneMap(o.data);
      final export = DocumentExport.note(o, demoActors[2]);
      o.data['client'] = 'A different new owner';
      o.data['plate'] = 'NEW';
      o.tasks.first['rateCents'] = 999999;
      expect(export.customer, 'Cliente ficticio Álvarez');
      expect(export.vehicle, '4321FIC');
      expect(export.totalCents, 3634);
      expect(export.rows.first.containsKey('costCents'), false);
      expect(o.data['document'], before['document']);
    },
  );
  test(
    'Quotes export exactly their saved version after the current catalog and task change',
    () {
      final s = demoState(), o = s.orders.values.first;
      s.apply(quotes.op(o, quotes.draft(o)), demoActors[2]);
      final q = (o.data['quoteLedger']['versions'] as List).first;
      final copy = cloneMap(q), export = DocumentExport.quote(q, demoActors[2]);
      o.tasks.first['rateCents'] = 999999;
      expect(export.totalCents, q['totalCents']);
      expect(export.reference, contains('versión 1'));
      expect(q, copy);
      expect(export.rows.any((r) => r.containsKey('costCents')), false);
    },
  );
  test(
    'Operators, drafts and incoherent saved totals cannot be exported as an issued note',
    () {
      expect(
        () => DocumentExport.note(noteFixture(), demoActors[0]),
        throwsA(isA<RuleException>()),
      );
      expect(
        () =>
            DocumentExport.note(demoState().orders.values.first, demoActors[2]),
        throwsA(isA<RuleException>()),
      );
      final o = noteFixture();
      o.data['document']['totalCents'] = 1;
      expect(
        () => DocumentExport.note(o, demoActors[2]),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'PDF generation embeds Spanish font and renders ordinary and multipage saved documents',
    () async {
      final font = await rootBundle.load('assets/fonts/Manrope.ttf');
      final s = demoState(), o = s.orders.values.first;
      s.apply(quotes.op(o, quotes.draft(o)), demoActors[2]);
      final samples = {
        'TallerFlow-nota-demo.pdf': DocumentExport.note(
          noteFixture(),
          demoActors[2],
        ),
        'TallerFlow-presupuesto-demo.pdf': DocumentExport.quote(
          o.data['quoteLedger']['versions'][0],
          demoActors[2],
        ),
        'TallerFlow-nota-extensa-demo.pdf': DocumentExport.note(
          noteFixture(rows: 80),
          demoActors[2],
        ),
      };
      for (final sample in samples.entries) {
        final bytes = await buildDocumentPdf(
          sample.value,
          font,
          workshop: 'Taller de demostración',
          contact: 'Calle Ficticia 12 · Madrid · 600 000 000',
        );
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        expect(bytes.length, greaterThan(5000));
        if (const bool.fromEnvironment('WRITE_PDF_EVIDENCE')) {
          await File('../${sample.key}').writeAsBytes(bytes);
        }
      }
    },
  );
}
