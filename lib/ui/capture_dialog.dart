import 'dart:async';
import 'package:flutter/material.dart';
import '../data/text_capture.dart';
import '../domain/capture_draft.dart';
import 'qr_scanner.dart';

class CaptureTextButton extends StatelessWidget {
  final CaptureKind kind;
  final String initial;
  final void Function(String) onReviewed;
  final TextCaptureBackend? backend;
  const CaptureTextButton({
    super.key,
    required this.kind,
    required this.initial,
    required this.onReviewed,
    this.backend,
  });
  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: const Icon(Icons.mic_none),
    label: const Text('Capturar y revisar texto'),
    onPressed: () async {
      final value = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CaptureDialog(
          kind: kind,
          initial: initial,
          backend: backend ?? DeviceTextCapture.instance,
        ),
      );
      if (value != null && context.mounted) onReviewed(value);
    },
  );
}

class CaptureDialog extends StatefulWidget {
  final CaptureKind kind;
  final String initial;
  final TextCaptureBackend backend;
  const CaptureDialog({
    super.key,
    required this.kind,
    required this.initial,
    required this.backend,
  });
  @override
  State<CaptureDialog> createState() => _CaptureDialogState();
}

class _CaptureDialogState extends State<CaptureDialog>
    with WidgetsBindingObserver {
  late final draft = TextEditingController(text: widget.initial);
  bool listening = false, busy = false, closed = false;
  String raw = '', message = '';
  List<String> get proposals => captureCandidates(raw, widget.kind);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    closed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.backend.cancelVoice());
    draft.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s != AppLifecycleState.resumed) {
      unawaited(widget.backend.cancelVoice());
      if (mounted && !closed) setState(() => listening = false);
    }
  }

  void receive(String text) {
    if (!mounted || closed) return;
    setState(() {
      raw = text;
      final p = proposals;
      if (widget.kind == CaptureKind.technical || p.length == 1) {
        draft.text = p.firstOrNull ?? '';
      }
    });
  }

  Future<void> voice() async {
    if (listening) {
      await widget.backend.stopVoice();
      if (mounted && !closed) setState(() => listening = false);
      return;
    }
    setState(() {
      busy = true;
      message = '';
    });
    try {
      await widget.backend.startVoice(
        words: receive,
        listening: (v) {
          if (mounted && !closed) setState(() => listening = v);
        },
        error: (e) {
          if (mounted && !closed) {
            setState(() {
              message = e;
              listening = false;
            });
          }
        },
      );
    } catch (_) {
      if (mounted && !closed) {
        setState(
          () => message =
              'No se puede usar el dictado en español. Revisa los permisos y el servicio de voz del equipo, o escribe el texto.',
        );
      }
    } finally {
      if (mounted && !closed) setState(() => busy = false);
    }
  }

  Future<void> camera() async {
    setState(() {
      busy = true;
      message = '';
    });
    try {
      final text = await widget.backend.cameraText();
      if (text != null) receive(text);
      if (mounted && text?.trim().isEmpty == true) {
        setState(
          () => message =
              'No se ha reconocido texto. Puedes repetir la fotografía o escribirlo.',
        );
      }
    } catch (_) {
      if (mounted && !closed) {
        setState(
          () => message =
              'No se puede leer la fotografía. Revisa el permiso de cámara o escribe el texto.',
        );
      }
    } finally {
      if (mounted && !closed) setState(() => busy = false);
    }
  }

  Future<void> barcode() async {
    final value = await readPartReference(context);
    if (value != null) receive(value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Borrador para revisar'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Captura solo información técnica. El dictado depende del servicio de voz del equipo; la lectura de cámara se procesa en el dispositivo. Revisa el resultado antes de usarlo.',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : voice,
                  icon: Icon(listening ? Icons.stop : Icons.mic_none),
                  label: Text(
                    listening ? 'Detener dictado' : 'Dictar en español',
                  ),
                ),
                if (widget.backend.cameraAvailable)
                  OutlinedButton.icon(
                    onPressed: busy || listening ? null : camera,
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: const Text('Leer con cámara'),
                  ),
                if (widget.kind == CaptureKind.reference && hasMobileCamera)
                  OutlinedButton(
                    onPressed: busy || listening ? null : barcode,
                    child: const Text('Leer código de pieza'),
                  ),
              ],
            ),
            if (listening)
              const Padding(
                padding: EdgeInsets.all(10),
                child: Text('Escuchando · Detén el dictado para revisar'),
              ),
            if (busy) const LinearProgressIndicator(),
            if (raw.isNotEmpty)
              ExpansionTile(
                title: const Text('Texto reconocido original'),
                children: [SelectableText(raw)],
              ),
            if (widget.kind != CaptureKind.technical)
              for (final p in proposals)
                TextButton(
                  onPressed: listening
                      ? null
                      : () => setState(() => draft.text = p),
                  child: Text('Revisar: $p'),
                ),
            const SizedBox(height: 12),
            TextField(
              controller: draft,
              readOnly: listening || busy,
              maxLines: widget.kind == CaptureKind.technical ? 5 : 2,
              decoration: const InputDecoration(labelText: 'Texto revisado'),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Usar este texto rellena el campo. Todavía tendrás que confirmar el formulario; no registra tiempos ni consumos.',
              ),
            ),
            if (message.isNotEmpty)
              Text(message, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: busy || listening
            ? null
            : () {
                try {
                  Navigator.pop(
                    context,
                    reviewedCaptureValue(draft.text, widget.kind),
                  );
                } on FormatException catch (e) {
                  setState(() => message = e.message);
                }
              },
        child: const Text('He revisado: usar texto'),
      ),
    ],
  );
}
