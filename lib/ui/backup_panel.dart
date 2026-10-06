import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../data/backup.dart';
import '../data/controller.dart';
import '../domain/models.dart';

Future<Uint8List> _seal(Map<String, dynamic> request) => BackupCodec().seal(
  Map<String, dynamic>.from(request['archive']),
  request['password'],
);
Future<Map<String, dynamic>> _open(Map<String, dynamic> request) =>
    BackupCodec().open(request['bytes'] as Uint8List, request['password']);

class BackupPanel extends StatefulWidget {
  final WorkshopController controller;
  const BackupPanel({super.key, required this.controller});
  @override
  State<BackupPanel> createState() => _BackupPanelState();
}

class _BackupPanelState extends State<BackupPanel> {
  bool busy = false;
  String? status;
  WorkshopController get c => widget.controller;
  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      status = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => status = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> password({required bool creating}) => showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BackupPassword(creating: creating),
  );
  Future<void> export({bool complete = false}) => run(() async {
    final secret = await password(creating: true);
    if (secret == null) return;
    final archive = await c.exportBackup(complete: complete);
    final bytes = await compute(_seal, {
      'archive': archive,
      'password': secret,
    });
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Guardar copia cifrada',
      fileName: 'TallerFlow-${archive['archiveId']}.tfbackup',
      type: FileType.custom,
      allowedExtensions: ['tfbackup'],
      bytes: bytes,
    );
    if (mounted && uri != null) {
      setState(
        () => status =
            'Copia cifrada guardada. Conserva la contraseña fuera de este dispositivo. '
            '${complete ? 'Incluye servidor y este equipo. Los otros equipos necesitan su propia copia.' : 'Incluye solo este equipo, sus documentos descargados y sus pendientes.'}',
      );
    }
  });
  Future<void> restore({bool server = false}) => run(() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['tfbackup'],
    );
    if (file == null) return;
    final length = await file.length();
    if (length == null || length > BackupCodec.maxBytes) {
      throw const FormatException(
        'No se puede leer esta copia o supera el tamaño admitido',
      );
    }
    final secret = await password(creating: false);
    if (secret == null) return;
    final archive = await compute(_open, {
      'bytes': await file.readAsBytes(),
      'password': secret,
    });
    if (!mounted) return;
    final local = archive['local'] as Map;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          server
              ? 'Revisar restauración del servidor'
              : 'Revisar recuperación de este equipo',
        ),
        content: SingleChildScrollView(
          child: Text(
            'Copia de ${archive['createdAt']}\nTaller: ${archive['workshopId']}\n'
            'Cuenta de origen: ${local['actor']['name']}\n'
            '${(local['outbox'] as List).length} registros locales pendientes\n'
            '${(local['pendingCommands'] as List? ?? []).length} comandos pendientes\n\n'
            '${server ? 'Solo se admite un taller de recuperación vacío, con las identidades Auth originales ya preparadas. Las identidades de dispositivo importadas quedan retiradas y los cierres pendientes se invalidan; no se restauran sesiones de acceso.' : 'Debes usar la misma cuenta. Los originales se conservan, la autorización local vence y tendrás que iniciar sesión de nuevo. La copia no acredita reconciliación ni reactiva un dispositivo retirado.'}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restaurar y conservar evidencia'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (server) {
      final result = await c.restoreServerBackup(archive);
      if (mounted) {
        setState(
          () => status =
              'Servidor restaurado. Revisa los equipos históricos y recupera sus pendientes con cada cuenta. Resultado: ${result['counts']}',
        );
      }
    } else {
      await c.restoreLocalBackup(archive);
      if (mounted) {
        setState(
          () => status =
              'Copia recuperada. Inicia sesión de nuevo para revalidar y reconciliar los registros.',
        );
      }
    }
  });
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Copias y recuperación',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          const Text(
            'Los pendientes de un móvil desconectado solo existen en ese equipo. Guarda una copia de cada dispositivo y una del servidor. La contraseña de la copia es distinta de la cuenta y no se guarda en TallerFlow.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : () => export(),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Guardar copia de este equipo'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => restore(),
                icon: const Icon(Icons.restore),
                label: const Text('Recuperar copia del equipo'),
              ),
              if (c.actor.role == Role.admin && !c.demo) ...[
                FilledButton.icon(
                  onPressed: busy ? null : () => export(complete: true),
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('Copiar servidor y este equipo'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => restore(server: true),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Restaurar servidor vacío'),
                ),
              ],
            ],
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(),
            ),
          if (status != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(status!),
            ),
        ],
      ),
    ),
  );
}

class _BackupPassword extends StatefulWidget {
  final bool creating;
  const _BackupPassword({required this.creating});
  @override
  State<_BackupPassword> createState() => _BackupPasswordState();
}

class _BackupPasswordState extends State<_BackupPassword> {
  final first = TextEditingController(), second = TextEditingController();
  String? error;
  @override
  void dispose() {
    first.dispose();
    second.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.creating ? 'Proteger la copia' : 'Abrir copia protegida',
    ),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Contraseña de al menos 12 caracteres. Necesitarás conservarla para recuperar la copia en otro equipo.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: first,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Contraseña de la copia',
            ),
          ),
          if (widget.creating) ...[
            const SizedBox(height: 12),
            TextField(
              controller: second,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Repetir contraseña',
              ),
            ),
          ],
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (first.text.length < 12 ||
              first.text.length > 1024 ||
              (widget.creating && first.text != second.text)) {
            setState(
              () =>
                  error = 'Revisa la longitud y que las contraseñas coincidan',
            );
            return;
          }
          Navigator.pop(context, first.text);
        },
        child: const Text('Continuar'),
      ),
    ],
  );
}
