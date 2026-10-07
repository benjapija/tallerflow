import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/document_pdf.dart';
import '../domain/document_export.dart';
import 'dialogs.dart';

class DocumentExportButton extends StatefulWidget {
  final DocumentExport Function() source;
  final String filename;
  const DocumentExportButton({
    super.key,
    required this.source,
    required this.filename,
  });
  @override
  State<DocumentExportButton> createState() => _DocumentExportButtonState();
}

class _DocumentExportButtonState extends State<DocumentExportButton> {
  bool busy = false;
  Future<void> export() async {
    setState(() => busy = true);
    try {
      final source = widget.source();
      final identity = await formDialog(
        context,
        'Datos del taller para esta copia PDF',
        [
          const FieldSpec('name', 'Nombre del taller'),
          const FieldSpec(
            'contact',
            'Dirección y contacto (opcional)',
            required: false,
          ),
        ],
        (values) => Map<String, dynamic>.from(values),
      );
      if (identity == null) return;
      final bytes = await buildDocumentPdf(
        source,
        await rootBundle.load('assets/fonts/Manrope.ttf'),
        workshop: identity['name']!,
        contact: identity['contact'] ?? '',
      );
      await FilePicker.saveFile(
        dialogTitle: 'Guardar documento PDF',
        fileName: widget.filename,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: bytes,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: busy ? null : export,
    icon: const Icon(Icons.picture_as_pdf_outlined),
    label: Text(busy ? 'Preparando PDF…' : 'Guardar PDF'),
  );
}
