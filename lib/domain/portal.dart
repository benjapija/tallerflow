import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';
import 'engine.dart';

String validatePortalUrl(dynamic value) {
  if (value is! String ||
      value.length > 500 ||
      (value.isNotEmpty &&
          !RegExp(
            r'^https://[a-zA-Z0-9.-]+(:[0-9]+)?(/[a-zA-Z0-9_./-]*)?$',
          ).hasMatch(value))) {
    throw const RuleException(
      'Usa una dirección HTTPS sin credenciales, parámetros ni fragmento',
    );
  }
  return value;
}

class PortalCredentials {
  final String id, token, code;
  const PortalCredentials(this.id, this.token, this.code);
  factory PortalCredentials.generate() {
    final random = Random.secure();
    String secret(int size) => List.generate(
      size,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return PortalCredentials(const Uuid().v4(), secret(32), secret(16));
  }
  Future<Map<String, String>> hashes() async {
    Future<String> hash(String v) async => (await Sha256().hash(
      utf8.encode(v),
    )).bytes.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return {'tokenHash': await hash(token), 'codeHash': await hash(code)};
  }

  String link(String base) {
    if (validatePortalUrl(base).isEmpty) {
      throw const RuleException('Configura la dirección del portal');
    }
    return '$base#access=$id.$token';
  }
}
