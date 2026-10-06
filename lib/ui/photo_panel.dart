import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../data/controller.dart';
import '../domain/models.dart';
import '../domain/photos.dart';
import '../data/photo_temp.dart';
import 'dialogs.dart';
import 'qr_scanner.dart';

class PhotoPanel extends StatefulWidget {
  final WorkshopController controller;
  final WorkOrder order;
  const PhotoPanel({super.key, required this.controller, required this.order});
  @override
  State<PhotoPanel> createState() => _PhotoPanelState();
}

class _PhotoPanelState extends State<PhotoPanel> {
  bool busy = false;
  String? message;
  WorkshopController get c => widget.controller;
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

  Future<void> capture(ImageSource source) => run(() async {
    final caption = await textDialog(
      context,
      'Fotografía de la reparación',
      'Descripción',
      initial: '',
      help:
          'Describe el daño, la pieza o la comprobación. Evita incluir documentos o datos personales.',
    );
    if (caption == null) return;
    await c.beginPhotoCapture(widget.order.id, caption);
    final photo = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    if (photo == null) {
      await c.cancelPhotoCapture();
      return;
    }
    final sourcePath = await privatePhotoSource(photo.path);
    if (sourcePath != null) await c.stagePhotoSource(sourcePath);
    final prepared = await compute(
      prepareTechnicalPhoto,
      await photo.readAsBytes(),
    );
    await c.finishPhotoCapture(prepared);
    await removeTemporaryPhoto(photo.path);
    if (!c.demo && !c.offline) unawaited(c.synchronize());
    if (mounted) {
      setState(() => message = 'Fotografía guardada en este equipo.');
    }
  });

  @override
  Widget build(BuildContext context) {
    final all = {
      for (final p in [...c.photoManifest, ...c.photoQueue])
        if (p['orderId'] == widget.order.id) p['id']: p,
    };
    final editable = !widget.order.issued && !c.frozen(widget.order.id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Fotografías',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'Archivos privados del taller. Se guardan cifrados en este equipo antes de sincronizarse.',
            ),
            if (editable)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (hasMobileCamera)
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => capture(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Hacer foto'),
                    ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => capture(ImageSource.gallery),
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Elegir foto'),
                  ),
                ],
              ),
            if (c.captureTicket?['orderId'] == widget.order.id) ...[
              const Text(
                'Hay una captura sin terminar. Recupera la imagen o cancela la captura para continuar.',
              ),
              TextButton(
                onPressed: busy ? null : () => run(c.cancelPhotoCapture),
                child: const Text('Cancelar captura pendiente'),
              ),
            ],
            if (message != null) Text(message!),
            if (busy) const LinearProgressIndicator(),
            for (final p in all.values) ...[
              const SizedBox(height: 14),
              _PhotoCard(
                key: ValueKey('${c.actor.id}-${p['id']}'),
                controller: c,
                photo: p,
              ),
              if (p['status'] == 'queued')
                Text(p['error'] ?? 'Pendiente de sincronizar'),
              if (['review', 'late', 'pending'].contains(p['status']))
                Text(
                  p['status'] == 'pending'
                      ? 'Carga pendiente'
                      : p['status'] == 'late'
                      ? 'Evidencia tardía: el documento emitido se conserva'
                      : 'Recuperada: pendiente de revisión de oficina',
                ),
              if (c.actor.isOffice &&
                  !c.demo &&
                  ['review', 'late', 'pending'].contains(p['status']))
                Wrap(
                  spacing: 8,
                  children: [
                    if (p['status'] != 'pending' && !widget.order.issued)
                      TextButton(
                        onPressed: busy ? null : () => review(p, true),
                        child: const Text('Incorporar tras revisión'),
                      ),
                    TextButton(
                      onPressed: busy ? null : () => review(p, false),
                      child: const Text('Archivar con motivo'),
                    ),
                  ],
                ),
            ],
            if (all.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Todavía no hay fotografías.'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> review(Map<String, dynamic> p, bool approve) => run(() async {
    final reason = await textDialog(
      context,
      approve
          ? 'Revisar fotografía recuperada'
          : 'Archivar fotografía pendiente',
      'Motivo',
      initial: '',
    );
    if (reason != null) {
      await c.reviewPhoto(p, approve: approve, reason: reason);
    }
  });
}

class HistoricalPhotoGallery extends StatefulWidget {
  final WorkshopController controller;
  final String orderId;
  const HistoricalPhotoGallery({
    super.key,
    required this.controller,
    required this.orderId,
  });
  @override
  State<HistoricalPhotoGallery> createState() => _HistoricalPhotoGalleryState();
}

class _HistoricalPhotoGalleryState extends State<HistoricalPhotoGallery> {
  bool opened = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final photos = c.photoManifest
        .where(
          (p) =>
              p['orderId'] == widget.orderId &&
              (c.actor.isOffice || p['status'] == 'attached'),
        )
        .toList();
    if (photos.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => opened = !opened),
          icon: const Icon(Icons.photo_library_outlined),
          label: Text(
            opened
                ? 'Ocultar fotografías técnicas'
                : 'Ver ${photos.length} fotografías técnicas',
          ),
        ),
        if (opened)
          for (final photo in photos)
            _PhotoCard(
              key: ValueKey('${c.actor.id}-${photo['id']}'),
              controller: c,
              photo: photo,
            ),
      ],
    );
  }
}

class _PhotoCard extends StatefulWidget {
  final WorkshopController controller;
  final Map<String, dynamic> photo;
  const _PhotoCard({super.key, required this.controller, required this.photo});
  @override
  State<_PhotoCard> createState() => _PhotoCardState();
}

class _PhotoCardState extends State<_PhotoCard> {
  late Future<Uint8List> bytes;
  @override
  void initState() {
    super.initState();
    bytes = widget.controller.photoBytes(widget.photo);
  }

  @override
  void didUpdateWidget(covariant _PhotoCard old) {
    super.didUpdateWidget(old);
    if (old.photo['status'] != widget.photo['status']) {
      bytes = widget.controller.photoBytes(widget.photo);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FutureBuilder<Uint8List>(
        future: bytes,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(
                snapshot.data!,
                height: 220,
                fit: BoxFit.contain,
              ),
            );
          }
          if (snapshot.hasError) {
            return Column(
              children: [
                const Text('Fotografía no descargada o sin acceso.'),
                TextButton(
                  onPressed: () => setState(
                    () => bytes = widget.controller.photoBytes(widget.photo),
                  ),
                  child: const Text('Reintentar descarga'),
                ),
              ],
            );
          }
          return const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator()),
          );
        },
      ),
      Text(
        widget.photo['caption'] ?? '',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ],
  );
}

Future<void> recoverInterruptedPhotoCapture(WorkshopController c) async {
  if (!hasMobileCamera || c.captureTicket == null) return;
  XFile? source;
  final staged = c.captureTicket!['sourcePath'];
  if (staged is String) {
    final path = await privatePhotoSource(staged);
    if (path != null) source = XFile(path);
  }
  if (source == null && defaultTargetPlatform == TargetPlatform.android) {
    final lost = await ImagePicker().retrieveLostData();
    if (lost.files?.isNotEmpty == true) source = lost.files!.first;
  }
  if (source == null) return;
  final path = await privatePhotoSource(source.path);
  if (path != null) await c.stagePhotoSource(path);
  final prepared = await compute(
    prepareTechnicalPhoto,
    await source.readAsBytes(),
  );
  await c.finishPhotoCapture(prepared);
  await removeTemporaryPhoto(source.path);
  if (!c.offline) unawaited(c.synchronize());
}
