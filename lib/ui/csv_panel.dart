import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../data/controller.dart';
import '../domain/csv_import.dart';
import '../domain/models.dart';
import 'dialogs.dart';

class CsvPanel extends StatefulWidget {
  final WorkshopController controller;
  const CsvPanel({super.key, required this.controller});
  @override
  State<CsvPanel> createState() => _CsvPanelState();
}

class _CsvPanelState extends State<CsvPanel> {
  String? previewActor;
  ImportKind kind = ImportKind.clients;
  ImportPreview? preview;
  Map<String, dynamic>? checked;
  bool busy = false, committed = false;
  String? message;
  WorkshopController get c => widget.controller;
  String label(ImportKind k) => switch (k) {
    ImportKind.clients => 'Clientes',
    ImportKind.vehicles => 'Vehículos',
    ImportKind.catalog => 'Catálogo',
  };
  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> template() => run(() async {
    await FilePicker.saveFile(
      dialogTitle: 'Guardar plantilla CSV',
      fileName: 'TallerFlow-${kind.name}.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
      bytes: Uint8List.fromList(utf8.encode(importTemplate(kind))),
    );
  });
  Future<void> select() => run(() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (file == null) return;
    final size = await file.length();
    if (size == null || size > 1048576) {
      throw const FormatException('Selecciona un CSV de hasta 1 MB');
    }
    final next = previewCsv(await file.readAsBytes(), kind, c.state, c.actor);
    final result = await c.previewImport(next);
    if (mounted) {
      setState(() {
        previewActor = c.actor.id;
        preview = next;
        checked = result;
        committed = false;
        message =
            'Vista previa preparada. Revisa todas las filas antes de importar.';
      });
    }
  });
  Future<void> commit() => run(() async {
    final reason = await textDialog(
      context,
      'Confirmar importación de ${label(kind).toLowerCase()}',
      'Motivo',
      initial: '',
      help:
          'Las filas válidas se incorporan. Los duplicados conservan sus datos y los errores se muestran por fila.',
    );
    if (reason == null) return;
    final result = await c.commitImport(preview!, reason);
    if (mounted) {
      setState(() {
        checked = result;
        committed = true;
        message =
            'Importación registrada: ${result['created']} filas incorporadas.';
      });
    }
  });
  Widget results(Map<String, dynamic> result) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final row in (result['rows'] as List? ?? []))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(
            'Fila ${row['line']} · ${row['message']}',
            style: TextStyle(
              color: row['status'] == 'error' ? Colors.red.shade700 : null,
            ),
          ),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    if (previewActor != null && previewActor != c.actor.id) {
      preview = null;
      checked = null;
      committed = false;
      previewActor = null;
      message = null;
    }
    if (kind == ImportKind.catalog && c.actor.role != Role.admin) {
      kind = ImportKind.clients;
    }
    if (!c.actor.isOffice) return const SizedBox.shrink();
    final valid = ((checked?['rows'] as List? ?? []).where(
      (r) => r['status'] == 'ready',
    )).length;
    final history = c.commandHistory
        .where(
          (h) => h['action'] == 'import_commit' && h['status'] == 'accepted',
        )
        .toList()
        .reversed
        .take(3);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Importar datos del taller',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'CSV UTF-8 de hasta 500 filas y 1 MB. Clientes primero, después sus vehículos. Usa la plantilla para conservar códigos y unidades.',
            ),
            const SizedBox(height: 12),
            DropdownButton<ImportKind>(
              value: kind,
              isExpanded: true,
              onChanged: busy
                  ? null
                  : (value) => setState(() {
                      kind = value!;
                      preview = null;
                      checked = null;
                      committed = false;
                    }),
              items: [
                for (final k in ImportKind.values)
                  if (k != ImportKind.catalog || c.actor.role == Role.admin)
                    DropdownMenuItem(value: k, child: Text(label(k))),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : template,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Guardar plantilla'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : select,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Seleccionar CSV y revisar'),
                ),
              ],
            ),
            if (preview != null) ...[
              const SizedBox(height: 12),
              Text(
                '${preview!.rows.length} filas revisadas · $valid listas para importar',
              ),
              for (final r in preview!.rows.where((r) => r.status == 'error'))
                Text(
                  'Fila ${r.line} · ${r.message}',
                  style: TextStyle(color: Colors.red.shade700),
                ),
              if (checked != null) results(checked!),
              FilledButton(
                onPressed: busy || committed || valid == 0 ? null : commit,
                child: const Text('Confirmar filas válidas'),
              ),
            ],
            if (busy) const LinearProgressIndicator(),
            if (message != null) Text(message!),
            if (history.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Últimas importaciones de este equipo',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              for (final h in history)
                ExpansionTile(
                  title: Text(
                    '${label(ImportKind.values.byName(h['result']['kind']))} · ${h['result']['created']} incorporadas',
                  ),
                  children: [results(Map<String, dynamic>.from(h['result']))],
                ),
            ],
          ],
        ),
      ),
    );
  }
}
