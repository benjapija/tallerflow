import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'vault.dart';

class PhotoBlobs {
  final StringStore Function(String) store;
  final SecretKey key;
  final cipher = AesGcm.with256bits();
  PhotoBlobs(this.store, this.key);
  factory PhotoBlobs.memory(SecretKey key) {
    final files = <String, MemoryStore>{};
    return PhotoBlobs((hash) => files.putIfAbsent(hash, MemoryStore.new), key);
  }

  static void validateHash(String hash) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('Identificador de fotografía inválido');
    }
  }

  static Future<String> digest(List<int> bytes) async => (await Sha256().hash(
    bytes,
  )).bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();

  Future<Uint8List?> read(String hash) async {
    validateHash(hash);
    final raw = await store(hash).read();
    if (raw == null) return null;
    final e = jsonDecode(raw) as Map<String, dynamic>;
    if (e['format'] != 'tallerflow-photo-1') {
      throw const FormatException('Fotografía incompatible');
    }
    final bytes = await cipher.decrypt(
      SecretBox(
        base64Decode(e['cipher']),
        nonce: base64Decode(e['nonce']),
        mac: Mac(base64Decode(e['mac'])),
      ),
      secretKey: key,
      aad: utf8.encode(hash),
    );
    if (bytes.length > 4 * 1024 * 1024 || await digest(bytes) != hash) {
      throw const FormatException('Fotografía dañada');
    }
    return Uint8List.fromList(bytes);
  }

  Future<void> write(String hash, List<int> bytes) async {
    validateHash(hash);
    if (bytes.isEmpty ||
        bytes.length > 4 * 1024 * 1024 ||
        await digest(bytes) != hash) {
      throw const FormatException('Contenido de fotografía inválido');
    }
    final old = await read(hash);
    if (old != null) return;
    final box = await cipher.encrypt(
      bytes,
      secretKey: key,
      aad: utf8.encode(hash),
    );
    await store(hash).write(
      jsonEncode({
        'format': 'tallerflow-photo-1',
        'nonce': base64Encode(box.nonce),
        'cipher': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      }),
    );
  }
}
