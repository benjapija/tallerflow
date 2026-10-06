import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Portable archive. No device encryption key or authentication token is copied.
class BackupCodec {
  static const maxBytes = 32 * 1024 * 1024;
  static const iterations = 600000;
  final AesGcm _cipher = AesGcm.with256bits();
  final Pbkdf2 _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  );
  static void _password(String value) {
    if (value.length < 12 || value.length > 1024) {
      throw const FormatException(
        'Usa una contraseña de entre 12 y 1024 caracteres',
      );
    }
  }

  Map<String, dynamic> _header(String salt) => {
    'format': 'tallerflow-backup',
    'version': 1,
    'kdf': 'PBKDF2-HMAC-SHA256',
    'iterations': iterations,
    'salt': salt,
  };
  Future<Uint8List> seal(Map<String, dynamic> archive, String password) async {
    _password(password);
    final bytes = utf8.encode(jsonEncode(archive));
    if (bytes.length > maxBytes * 3 ~/ 4 - 2048) {
      throw const FormatException(
        'Copia demasiado grande; exporta por servidor con el procedimiento documentado',
      );
    }
    final salt = (await _cipher.newSecretKey().then(
      (k) => k.extractBytes(),
    )).take(16).toList();
    final header = _header(base64Encode(salt));
    final key = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    final box = await _cipher.encrypt(
      bytes,
      secretKey: key,
      aad: utf8.encode(jsonEncode(header)),
    );
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          ...header,
          'nonce': base64Encode(box.nonce),
          'cipher': base64Encode(box.cipherText),
          'mac': base64Encode(box.mac.bytes),
        }),
      ),
    );
  }

  Future<Map<String, dynamic>> open(Uint8List bytes, String password) async {
    _password(password);
    if (bytes.length > maxBytes) {
      throw const FormatException('Archivo de copia demasiado grande');
    }
    try {
      final e = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (e['format'] != 'tallerflow-backup' ||
          e['version'] != 1 ||
          e['kdf'] != 'PBKDF2-HMAC-SHA256' ||
          e['iterations'] != iterations) {
        throw const FormatException('Formato de copia incompatible');
      }
      final salt = base64Decode(e['salt']);
      final nonce = base64Decode(e['nonce']);
      final mac = base64Decode(e['mac']);
      if (salt.length != 16 || nonce.length != 12 || mac.length != 16) {
        throw const FormatException('Copia dañada');
      }
      final key = await _kdf.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: salt,
      );
      final plain = await _cipher.decrypt(
        SecretBox(base64Decode(e['cipher']), nonce: nonce, mac: Mac(mac)),
        secretKey: key,
        aad: utf8.encode(jsonEncode(_header(e['salt']))),
      );
      final data = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
      if (data['kind'] != 'TallerFlow' ||
          data['version'] != 1 ||
          data['archiveId'] is! String ||
          data['local'] is! Map ||
          data['local']['state']?['workshopId'] != data['workshopId'] ||
          data['local']['actor']?['id'] != data['actorId']) {
        throw const FormatException('Contenido de copia incompatible');
      }
      return data;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'No se puede abrir: contraseña incorrecta o copia dañada',
      );
    }
  }
}
