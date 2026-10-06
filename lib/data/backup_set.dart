import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'backup.dart';
import 'photo_blobs.dart';

typedef BackupKeyDeriver = Future<List<int>> Function(String, List<int>);
typedef BackupPhotoReader = Future<Uint8List?> Function(String);

Future<List<int>> deriveBackupSetKey(String password, List<int> salt) async =>
    (await Pbkdf2(
          macAlgorithm: Hmac.sha256(),
          iterations: BackupCodec.iterations,
          bits: 256,
        ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt))
        .extractBytes();

class BackupPart {
  final String setId;
  final int index;
  final bool last;
  final Uint8List bytes;
  BackupPart(this.setId, this.index, this.last, this.bytes);
  String get fileName =>
      'TallerFlow-$setId-parte-${index.toString().padLeft(4, '0')}.tfpart';
}

class BackupPartInput {
  final Future<int?> Function() length;
  final Future<Uint8List> Function() read;
  BackupPartInput({required this.length, required this.read});
}

/// A bounded encrypted set. Photos are fetched and checked one at a time.
/// The authenticated sequence, previous-part digest and final flag make a
/// missing, substituted or truncated part an error before state restoration.
class BackupSetCodec {
  static const maxPartBytes = 20 * 1024 * 1024;
  static const maxPayloadBytes = 12 * 1024 * 1024;
  static const maxMetadataBytes = 256 * 1024 * 1024;
  static const maxParts = 4096;
  static const metadataChunkBytes = 512 * 1024;
  final BackupKeyDeriver deriveKey;
  final AesGcm cipher = AesGcm.with256bits();
  BackupSetCodec({BackupKeyDeriver? deriveKey})
    : deriveKey = deriveKey ?? deriveBackupSetKey;

  void _password(String password) {
    if (password.length < 12 || password.length > 1024) {
      throw const FormatException(
        'Usa una contraseña de entre 12 y 1024 caracteres',
      );
    }
  }

  void _archive(Map<String, dynamic> archive) {
    if (archive['kind'] != 'TallerFlow' ||
        archive['version'] != 1 ||
        archive['archiveId'] is! String ||
        archive['local'] is! Map ||
        archive['local']['state']?['workshopId'] != archive['workshopId'] ||
        archive['local']['actor']?['id'] != archive['actorId'] ||
        archive['photoFiles'] is! Map) {
      throw const FormatException('Contenido de copia incompatible');
    }
    for (final entry in (archive['photoFiles'] as Map).entries) {
      if (entry.key is! String ||
          entry.value is! int ||
          entry.value < 1 ||
          entry.value > 4194304) {
        throw const FormatException('Manifiesto de archivos incompatible');
      }
      PhotoBlobs.validateHash(entry.key);
    }
  }

  Map<String, dynamic> _header(Map<String, dynamic> e) => {
    for (final key in [
      'format',
      'version',
      'kdf',
      'iterations',
      'salt',
      'setId',
      'index',
      'last',
      'previous',
    ])
      key: e[key],
  };

  Map<String, dynamic> _envelope(Uint8List bytes) {
    if (bytes.length > maxPartBytes) {
      throw const FormatException('Una parte supera el tamaño admitido');
    }
    final e = Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)));
    if (e['format'] != 'tallerflow-backup-set' ||
        e['version'] != 2 ||
        e['kdf'] != 'PBKDF2-HMAC-SHA256' ||
        e['iterations'] != BackupCodec.iterations ||
        e['setId'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(e['setId']) ||
        e['index'] is! int ||
        e['index'] < 1 ||
        e['index'] > maxParts ||
        e['last'] is! bool ||
        e['previous'] is! String ||
        (e['previous'] != '' &&
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(e['previous'])) ||
        base64Decode(e['salt']).length != 16 ||
        base64Decode(e['nonce']).length != 12 ||
        base64Decode(e['mac']).length != 16 ||
        e['cipher'] is! String) {
      throw const FormatException('Parte de copia incompatible');
    }
    return e;
  }

  Stream<Map<String, dynamic>> _records(
    Map<String, dynamic> archive,
    BackupPhotoReader readPhoto,
  ) async* {
    final metadata = utf8.encode(jsonEncode(archive));
    if (metadata.length > maxMetadataBytes) {
      throw const FormatException(
        'Los registros superan el límite de esta copia',
      );
    }
    var seq = 0;
    for (var start = 0; start < metadata.length; start += metadataChunkBytes) {
      final end = start + metadataChunkBytes < metadata.length
          ? start + metadataChunkBytes
          : metadata.length;
      yield {
        'kind': 'metadata',
        'seq': seq++,
        'bytes': base64Encode(metadata.sublist(start, end)),
      };
    }
    yield {
      'kind': 'metadataEnd',
      'size': metadata.length,
      'sha256': await PhotoBlobs.digest(metadata),
    };
    for (final entry in (archive['photoFiles'] as Map).entries) {
      final bytes = await readPhoto(entry.key);
      if (bytes == null ||
          bytes.length != entry.value ||
          await PhotoBlobs.digest(bytes) != entry.key) {
        throw const FormatException(
          'Falta una fotografía original o está dañada',
        );
      }
      yield {'kind': 'photo', 'hash': entry.key, 'bytes': base64Encode(bytes)};
    }
  }

  Stream<BackupPart> sealParts(
    Map<String, dynamic> archive,
    String password, {
    required BackupPhotoReader readPhoto,
  }) async* {
    _password(password);
    _archive(archive);
    final salt = (await cipher.newSecretKey()).extractBytes();
    final saltBytes = (await salt).take(16).toList();
    final setId = (await cipher.newSecretKey()).extractBytes();
    final id = (await setId)
        .take(16)
        .map((v) => v.toRadixString(16).padLeft(2, '0'))
        .join();
    final key = SecretKey(await deriveKey(password, saltBytes));
    var index = 1, previous = '', payloadSize = 32;
    var records = <Map<String, dynamic>>[];
    Future<BackupPart> seal(bool last) async {
      if (index > maxParts) {
        throw const FormatException('Demasiadas partes de copia');
      }
      final header = {
        'format': 'tallerflow-backup-set',
        'version': 2,
        'kdf': 'PBKDF2-HMAC-SHA256',
        'iterations': BackupCodec.iterations,
        'salt': base64Encode(saltBytes),
        'setId': id,
        'index': index,
        'last': last,
        'previous': previous,
      };
      final plain = utf8.encode(jsonEncode({'records': records}));
      if (plain.length > maxPayloadBytes) {
        throw const FormatException('Parte demasiado grande');
      }
      final box = await cipher.encrypt(
        plain,
        secretKey: key,
        aad: utf8.encode(jsonEncode(header)),
      );
      final bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            ...header,
            'nonce': base64Encode(box.nonce),
            'mac': base64Encode(box.mac.bytes),
            'cipher': base64Encode(box.cipherText),
          }),
        ),
      );
      if (bytes.length > maxPartBytes) {
        throw const FormatException('Parte demasiado grande');
      }
      final part = BackupPart(id, index++, last, bytes);
      previous = await PhotoBlobs.digest(bytes);
      records = [];
      payloadSize = 32;
      return part;
    }

    await for (final record in _records(archive, readPhoto)) {
      final size = utf8.encode(jsonEncode(record)).length + 1;
      if (records.isNotEmpty && payloadSize + size > maxPayloadBytes) {
        yield await seal(false);
      }
      records.add(record);
      payloadSize += size;
    }
    yield await seal(true);
  }

  Future<Map<String, dynamic>> openParts(
    List<BackupPartInput> inputs,
    String password, {
    required Future<void> Function(String, Uint8List) writePhoto,
  }) async {
    _password(password);
    if (inputs.isEmpty || inputs.length > maxParts) {
      throw const FormatException('Selecciona todas las partes de una copia');
    }
    try {
      final sources = <int, BackupPartInput>{},
          headers = <int, Map<String, dynamic>>{};
      Map<String, dynamic>? first;
      for (final input in inputs) {
        final length = await input.length();
        if (length == null || length > maxPartBytes) {
          throw const FormatException('Parte demasiado grande');
        }
        final e = _envelope(await input.read()), h = _header(e);
        first ??= h;
        if (h['setId'] != first['setId'] ||
            h['salt'] != first['salt'] ||
            sources.containsKey(h['index'])) {
          throw const FormatException('Partes mezcladas o repetidas');
        }
        sources[h['index']] = input;
        headers[h['index']] = h;
      }
      for (var i = 1; i <= inputs.length; i++) {
        if (headers[i] == null || headers[i]!['last'] != (i == inputs.length)) {
          throw const FormatException('Faltan partes de la copia');
        }
      }
      final key = SecretKey(
        await deriveKey(password, base64Decode(first!['salt'])),
      );
      final metadata = BytesBuilder(copy: false), seenPhotos = <String>{};
      Map<String, dynamic>? archive;
      var previous = '', seq = 0;
      for (var i = 1; i <= inputs.length; i++) {
        final bytes = await sources[i]!.read(),
            e = _envelope(bytes),
            h = _header(e);
        if (jsonEncode(h) != jsonEncode(headers[i]) ||
            h['previous'] != previous) {
          throw const FormatException('La secuencia de partes ha cambiado');
        }
        final plain = await cipher.decrypt(
          SecretBox(
            base64Decode(e['cipher']),
            nonce: base64Decode(e['nonce']),
            mac: Mac(base64Decode(e['mac'])),
          ),
          secretKey: key,
          aad: utf8.encode(jsonEncode(h)),
        );
        if (plain.length > maxPayloadBytes) {
          throw const FormatException('Parte demasiado grande');
        }
        final records = jsonDecode(utf8.decode(plain))['records'];
        if (records is! List || records.isEmpty) {
          throw const FormatException('Parte sin contenido');
        }
        for (final record in records) {
          switch (record['kind']) {
            case 'metadata':
              if (archive != null || record['seq'] != seq++) {
                throw const FormatException('Registros fuera de secuencia');
              }
              final chunk = base64Decode(record['bytes']);
              if (chunk.length > metadataChunkBytes ||
                  metadata.length + chunk.length > maxMetadataBytes) {
                throw const FormatException('Registros demasiado grandes');
              }
              metadata.add(chunk);
            case 'metadataEnd':
              if (archive != null || metadata.length != record['size']) {
                throw const FormatException('Registros incompletos');
              }
              final raw = metadata.takeBytes();
              if (await PhotoBlobs.digest(raw) != record['sha256']) {
                throw const FormatException('Registros dañados');
              }
              archive = Map<String, dynamic>.from(jsonDecode(utf8.decode(raw)));
              _archive(archive);
            case 'photo':
              final hash = record['hash'];
              if (archive == null ||
                  hash is! String ||
                  !seenPhotos.add(hash) ||
                  !archive['photoFiles'].containsKey(hash) ||
                  record['bytes'] is! String ||
                  (record['bytes'] as String).length > 5592408) {
                throw const FormatException(
                  'Fotografía sin manifiesto o repetida',
                );
              }
              final raw = base64Decode(record['bytes']);
              if (raw.length != archive['photoFiles'][hash] ||
                  await PhotoBlobs.digest(raw) != hash) {
                throw const FormatException('Fotografía dañada');
              }
              // Only immutable encrypted blobs are staged. The live state is untouched.
              await writePhoto(hash, raw);
            default:
              throw const FormatException('Contenido de parte incompatible');
          }
        }
        previous = await PhotoBlobs.digest(bytes);
      }
      if (archive == null ||
          seenPhotos.length != (archive['photoFiles'] as Map).length) {
        throw const FormatException(
          'Copia incompleta: faltan registros o fotografías',
        );
      }
      return archive;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'No se puede abrir: contraseña incorrecta o copia dañada',
      );
    }
  }
}
