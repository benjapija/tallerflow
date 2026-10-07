import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../domain/document_export.dart';
import '../domain/management.dart';
import '../domain/models.dart';

Future<Uint8List> buildDocumentPdf(
  DocumentExport source,
  ByteData fontBytes, {
  required String workshop,
  String contact = '',
}) async {
  workshop = requiredText(workshop, 'Nombre del taller', max: 300);
  final font = pw.Font.ttf(fontBytes);
  final pdf = pw.Document(
    title: source.title,
    author: workshop,
    creator: 'TallerFlow',
  );
  final green = PdfColor.fromHex('#16856B'), ink = PdfColor.fromHex('#192D2A');
  String date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      maxPages: 200,
      theme: pw.ThemeData.withFont(base: font, bold: font),
      header: (c) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(workshop, style: pw.TextStyle(fontSize: 21, color: green)),
          if (contact.trim().isNotEmpty)
            pw.Text(contact.trim(), style: const pw.TextStyle(fontSize: 9)),
          if (c.pageNumber > 1)
            pw.Text(
              '${source.kind} · ${source.reference}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          pw.SizedBox(height: 10),
          pw.Divider(color: green),
        ],
      ),
      footer: (c) => pw.Column(
        children: [
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'TallerFlow · ${source.kind} · No es una factura fiscal',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                '${c.pageNumber} / ${c.pagesCount}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          ),
        ],
      ),
      build: (_) => [
        pw.SizedBox(height: 12),
        pw.Text(source.title, style: pw.TextStyle(fontSize: 19, color: ink)),
        pw.SizedBox(height: 6),
        pw.Text(source.reference, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 12),
        pw.Text('Destinatario: ${source.customer}'),
        if (source.vehicle.isNotEmpty)
          pw.Text('Matrícula al emitir: ${source.vehicle}'),
        pw.Text('Fecha: ${date(source.date)}'),
        if (source.validUntil != null)
          pw.Text('Válido hasta: ${date(source.validUntil!)}'),
        pw.SizedBox(height: 18),
        pw.TableHelper.fromTextArray(
          headers: ['Concepto', 'Cantidad', 'Base (€)', 'IVA (€)', 'Total (€)'],
          data: [
            for (final r in source.rows)
              [
                '${r['description']}${(r['discountCents'] as int) > 0 ? '\nDescuento: ${money(r['discountCents'])}' : ''}${r.containsKey('noChargeReason') ? '\nSin cobro: ${r['noChargeReason']}' : ''}',
                r['quantity'],
                money(r['netCents']),
                money(r['taxCents']),
                money(r['totalCents']),
              ],
          ],
          border: null,
          headerDecoration: pw.BoxDecoration(color: green),
          headerStyle: pw.TextStyle(color: PdfColors.white, fontSize: 9),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellPadding: const pw.EdgeInsets.all(7),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          columnWidths: {
            0: const pw.FlexColumnWidth(4),
            1: const pw.FlexColumnWidth(1.2),
            2: const pw.FlexColumnWidth(1.4),
            3: const pw.FlexColumnWidth(1.4),
            4: const pw.FlexColumnWidth(1.4),
          },
          cellAlignments: {
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
          },
        ),
        pw.Inseparable(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(height: 16),
              for (final pair in [
                ['Base imponible', source.netCents],
                ['Impuestos', source.taxCents],
                ['Total', source.totalCents],
              ])
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Text(
                      '${pair[0]}: ',
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                    pw.Text(
                      money(pair[1] as int),
                      style: pw.TextStyle(
                        fontSize: pair[0] == 'Total' ? 18 : 12,
                        color: ink,
                      ),
                    ),
                  ],
                ),
              if (source.exception?.isNotEmpty == true) ...[
                pw.SizedBox(height: 16),
                pw.Text(
                  'Excepción administrativa de cierre: ${source.exception}',
                ),
              ],
              pw.SizedBox(height: 16),
              pw.Text(
                source.kind == 'Presupuesto'
                    ? 'Esta copia conserva una versión del presupuesto. No acredita la aceptación del cliente ni autoriza trabajos por sí sola.'
                    : 'Esta copia conserva la nota emitida. El estado del cobro se registra por separado.',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Datos de contacto del taller indicados al exportar. Importes y destinatario tomados del documento guardado.',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  return pdf.save();
}
