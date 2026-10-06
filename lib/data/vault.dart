import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'photo_blobs.dart';

abstract interface class StringStore {
  Future<String?> read();
  Future<void> write(String value);
}

class MemoryStore implements StringStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async {
    value = v;
  }
}

class Vault {
  final StringStore store;
  final SecretKey key;
  final PhotoBlobs photos;
  final AesGcm cipher = AesGcm.with256bits();
  Vault(this.store, this.key, {PhotoBlobs? photos})
    : photos = photos ?? PhotoBlobs.memory(key);
  Future<Map<String, dynamic>?> read() async {
    final raw = await store.read();
    if (raw == null) return null;
    final e = jsonDecode(raw) as Map<String, dynamic>;
    if (e['format'] != 1) {
      throw const FormatException('Copia de versión no compatible');
    }
    final bytes = await cipher.decrypt(
      SecretBox(
        base64Decode(e['cipher']),
        nonce: base64Decode(e['nonce']),
        mac: Mac(base64Decode(e['mac'])),
      ),
      secretKey: key,
    );
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  Future<void> write(Map<String, dynamic> data) async {
    final box = await cipher.encrypt(
      utf8.encode(jsonEncode(data)),
      secretKey: key,
    );
    await store.write(
      jsonEncode({
        'format': 1,
        'cipher': base64Encode(box.cipherText),
        'nonce': base64Encode(box.nonce),
        'mac': base64Encode(box.mac.bytes),
      }),
    );
  }
}
