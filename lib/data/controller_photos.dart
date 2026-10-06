part of 'controller.dart';

extension WorkshopPhotos on WorkshopController {
  Future<void> stagePhotoSource(String path) => _locked(() async {
    if (captureTicket == null || captureTicket!['actorId'] != actor.id) {
      throw const RuleException('No hay una captura pendiente de esta cuenta');
    }
    captureTicket!['sourcePath'] = path;
    await _persist();
  });

  List<Map<String, dynamic>> get photoManifest =>
      WorkshopController._maps(state.configuration['photoManifest']);
  bool get hasPendingPhotos => photoQueue.isNotEmpty || captureTicket != null;

  Future<void> beginPhotoCapture(String orderId, String caption) =>
      _locked(() async {
        _checkAccess();
        if (captureTicket != null) {
          throw const RuleException(
            'Revisa la captura pendiente antes de empezar otra',
          );
        }
        final order = visibleOrders.where((o) => o.id == orderId).firstOrNull;
        if (order == null || order.issued || frozen(orderId)) {
          throw const RuleException('Esta orden no admite nuevas fotografías');
        }
        if (caption.trim().isEmpty || caption.length > 2000) {
          throw const RuleException('Describe la fotografía');
        }
        captureTicket = {
          'id': const Uuid().v4(),
          'orderId': orderId,
          'actorId': actor.id,
          'originalDeviceId': deviceId,
          'caption': caption.trim(),
          'capturedAt': clock().toUtc().toIso8601String(),
        };
        try {
          await _persist();
        } catch (_) {
          captureTicket = null;
          rethrow;
        }
        notifyListeners();
      });

  Future<void> finishPhotoCapture(Uint8List bytes) => _locked(() async {
    final ticket = captureTicket;
    if (ticket == null || ticket['actorId'] != actor.id) {
      throw const RuleException('La captura no corresponde a esta cuenta');
    }
    if (bytes.length < 4 ||
        bytes[0] != 255 ||
        bytes[1] != 216 ||
        bytes[2] != 255 ||
        bytes[bytes.length - 2] != 255 ||
        bytes.last != 217) {
      throw const FormatException(
        'La captura debe prepararse como fotografía JPG',
      );
    }
    final hash = await PhotoBlobs.digest(bytes);
    await vault.photos.write(
      hash,
      bytes,
    ); // Bytes are durable before the queue.
    final entry = {
      ...Map<String, dynamic>.from(ticket)..remove('sourcePath'),
      'sha256': hash,
      'size': bytes.length,
      'mime': 'image/jpeg',
      'prepareId': const Uuid().v4(),
      'prepareDeviceId': deviceId,
      'status': 'queued',
    };
    final oldQueue = photoQueue.toList(),
        oldCache = cachedPhotoHashes.toSet(),
        oldState = state;
    if (photoQueue.any((p) => p['id'] == entry['id'])) {
      throw const RuleException('La captura ya está guardada');
    }
    photoQueue.add(entry);
    cachedPhotoHashes.add(hash);
    captureTicket = null;
    if (demo) {
      final next = state.copy();
      final order = next.orders[ticket['orderId']]!;
      order.data['photos'] = [
        ...(order.data['photos'] as List? ?? []),
        {...entry, 'status': 'attached'},
      ];
      order.data['revision'] = order.revision + 1;
      next.audit.add({
        'id': ticket['id'],
        'orderId': order.id,
        'actor': actor.name,
        'kind': 'photo_verified',
        'at': clock().toUtc().toIso8601String(),
      });
      next.configuration['photoManifest'] = [
        ...photoManifest,
        {...entry, 'status': 'attached', 'filePresent': true},
      ];
      state = next;
      photoHistory.add({...entry, 'status': 'attached'});
      photoQueue.remove(entry);
    }
    try {
      await _persist();
    } catch (_) {
      photoQueue = oldQueue;
      cachedPhotoHashes = oldCache;
      state = oldState;
      captureTicket = ticket;
      if (demo) photoHistory.removeLast();
      rethrow;
    }
    notifyListeners();
  });

  Future<void> cancelPhotoCapture() => _locked(() async {
    final old = captureTicket;
    if (old == null) return;
    captureTicket = null;
    photoHistory.add({
      ...old,
      'status': 'capture_cancelled',
      'reason': 'Captura cancelada antes de guardar una fotografía',
    });
    try {
      await _persist();
    } catch (_) {
      captureTicket = old;
      photoHistory.removeLast();
      rethrow;
    }
    notifyListeners();
  });

  Future<void> _uploadPhotos() async {
    for (final entry in photoQueue.toList()) {
      if (entry['actorId'] != actor.id) continue;
      if (entry['prepareDeviceId'] != deviceId) {
        entry['prepareId'] = const Uuid().v4();
        entry['prepareDeviceId'] = deviceId;
        await _persist(); // A recovery never reuses a command bound to a retired device.
      }
      try {
        final bytes = await vault.photos.read(entry['sha256']);
        if (bytes == null) {
          throw const RuleException(
            'Falta el archivo local; recupera la copia de este equipo',
          );
        }
        final info = await remote!.preparePhoto(
          entry['prepareId'],
          photoUploadPayload(entry),
        );
        if (['pending', 'review'].contains(info['status'])) {
          await remote!.uploadPhoto(info, bytes);
          await remote!.finalizePhoto(entry['id']);
        }
        entry.remove('error');
      } catch (e) {
        entry['error'] = '$e';
        await _persist();
        rethrow;
      }
    }
  }

  void _reconcilePhotos() {
    final confirmed = {for (final p in photoManifest) p['id']: p};
    for (final p in photoQueue.toList()) {
      final receipt = confirmed[p['id']];
      if (receipt == null ||
          receipt['sha256'] != p['sha256'] ||
          ![
            'attached',
            'review',
            'late',
            'archived',
          ].contains(receipt['status'])) {
        continue;
      }
      // The queue disappears only in the same durable write as this receipt.
      photoHistory.add({...p, 'status': receipt['status'], 'receipt': receipt});
      photoQueue.remove(p);
    }
  }

  Future<Uint8List> photoBytes(Map<String, dynamic> photo) => _locked(() async {
    _checkAccess();
    if (!visibleOrders.any((o) => o.id == photo['orderId'])) {
      throw const RuleException('Orden no disponible para esta cuenta');
    }
    final evidence = [...photoManifest, ...photoQueue]
        .where(
          (p) =>
              p['id'] == photo['id'] &&
              p['orderId'] == photo['orderId'] &&
              p['sha256'] == photo['sha256'],
        )
        .firstOrNull;
    if (evidence == null) throw const RuleException('Fotografía no disponible');
    final existing = await vault.photos.read(evidence['sha256']);
    if (existing != null) return existing;
    _checkOnline();
    final bytes = await remote!.downloadPhoto(evidence);
    await vault.photos.write(evidence['sha256'], bytes);
    cachedPhotoHashes.add(evidence['sha256']);
    try {
      await _persist();
    } catch (_) {
      cachedPhotoHashes.remove(evidence['sha256']);
      rethrow;
    }
    return bytes;
  });

  Future<void> reviewPhoto(
    Map<String, dynamic> photo, {
    required bool approve,
    required String reason,
  }) => _locked(() async {
    _checkOnline();
    if (!actor.isOffice) {
      throw const RuleException('La recuperación necesita revisión de oficina');
    }
    await _command(approve ? 'photo_approve' : 'photo_archive', {
      'id': photo['id'],
      'revision': state.orders[photo['orderId']]?.revision,
      'reason': reason,
    });
  });
}
