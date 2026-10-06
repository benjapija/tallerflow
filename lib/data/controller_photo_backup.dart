part of 'controller.dart';

extension PhotoBackup on WorkshopController {
  Map<String, dynamic> _portableLocal() {
    final local = cloneMap(localArchive());
    if (local['captureTicket'] is Map) {
      local['captureTicket'].remove('sourcePath');
    }
    return local;
  }

  Future<Map<String, dynamic>> _exportPhotoFiles(
    Map<String, dynamic>? server, {
    bool splitFiles = false,
  }) async {
    final files = <String, dynamic>{};
    final metadata = [
      ...photoManifest,
      ...photoQueue,
      ...WorkshopController._maps(server?['photoFiles']),
    ];
    final hashes = {
      ...cachedPhotoHashes,
      ...photoQueue.map((p) => p['sha256'] as String),
    };
    for (final photo in metadata) {
      if (photo['filePresent'] == true) hashes.add(photo['sha256']);
    }
    for (final hash in hashes) {
      var bytes = await vault.photos.read(hash);
      if (bytes == null) {
        final photo = metadata
            .where((p) => p['sha256'] == hash && p['filePresent'] == true)
            .firstOrNull;
        if (photo == null || demo || offline) {
          throw const RuleException(
            'Falta una fotografía local: descarga o recupera el archivo antes de crear la copia',
          );
        }
        bytes = await remote!.downloadPhoto(photo);
        if (bytes.length != photo['size'] ||
            await PhotoBlobs.digest(bytes) != hash) {
          throw const RuleException(
            'Una fotografía no coincide con su manifiesto',
          );
        }
        await vault.photos.write(hash, bytes);
      }
      files[hash] = splitFiles ? bytes.length : base64Encode(bytes);
    }
    return files;
  }

  Future<Map<String, int>> _validatePhotoFiles(
    Map<String, dynamic> archive, {
    Future<Uint8List?> Function(String)? readPhoto,
  }) async {
    final raw = archive['photoFiles'];
    if (raw != null && raw is! Map) {
      throw const RuleException('Archivos de copia incompatibles');
    }
    final files = <String, int>{};
    for (final entry in (raw as Map? ?? {}).entries) {
      if (entry.key is! String ||
          (entry.value is! String &&
              !(entry.value is int && readPhoto != null))) {
        throw const RuleException('Archivo de copia incompatible');
      }
      PhotoBlobs.validateHash(entry.key);
      if (entry.value is String && (entry.value as String).length > 5592408) {
        throw const RuleException('Fotografía demasiado grande');
      }
      final bytes = entry.value is String
          ? base64Decode(entry.value)
          : await readPhoto!(entry.key);
      if (bytes == null ||
          bytes.isEmpty ||
          bytes.length > 4194304 ||
          (entry.value is int && bytes.length != entry.value) ||
          await PhotoBlobs.digest(bytes) != entry.key) {
        throw const RuleException('Fotografía de copia dañada');
      }
      // Immutable encrypted files may be staged before validation finishes.
      // No live metadata is changed until every file and record is valid.
      await vault.photos.write(entry.key, bytes);
      files[entry.key] = bytes.length;
    }
    return files;
  }

  void _validatePhotoLocal(Map<String, dynamic> local, Map<String, int> files) {
    final ids = <String>{};
    for (final p in WorkshopController._maps(local['photoQueue'])) {
      if (p['actorId'] != actor.id ||
          p['id'] is! String ||
          !ids.add(p['id']) ||
          p['orderId'] is! String ||
          p['originalDeviceId'] is! String ||
          p['prepareId'] is! String ||
          p['prepareDeviceId'] is! String ||
          p['caption'] is! String ||
          p['capturedAt'] is! String ||
          p['mime'] != 'image/jpeg' ||
          p['size'] is! int ||
          files[p['sha256']] != p['size']) {
        throw const RuleException(
          'Captura pendiente incompatible o sin archivo original',
        );
      }
      DateTime.parse(p['capturedAt']);
    }
    final ticket = local['captureTicket'];
    if (ticket != null &&
        (ticket is! Map ||
            ticket['actorId'] != actor.id ||
            ticket['id'] is! String ||
            ticket['orderId'] is! String ||
            ticket['originalDeviceId'] is! String ||
            ticket['caption'] is! String ||
            ticket['capturedAt'] is! String)) {
      throw const RuleException('Captura interrumpida incompatible');
    }
    for (final hash in (local['cachedPhotoHashes'] as List? ?? [])) {
      if (!files.containsKey(hash)) {
        throw const RuleException(
          'Faltan fotografías guardadas en el equipo original',
        );
      }
    }
  }
}
