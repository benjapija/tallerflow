import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'engine.dart';

/// PostgreSQL jsonb::text for the integer-only sandbox format. Keys use jsonb's
/// UTF-8 byte length then byte order; whitespace is part of the saved digest.
/// This is not RFC 8785, a signature or the AEAT fiscal fingerprint.
String fiscalDraftJsonbText(Object? value) {
  if (value == null || value is bool) return jsonEncode(value);
  if (value is int) {
    if (value.abs() > 9007199254740991) {
      throw const RuleException('Entero fuera del formato de ensayo');
    }
    return value.toString();
  }
  if (value is String) {
    _unicode(value);
    return jsonEncode(value);
  }
  if (value is List) {
    return '[${value.map(fiscalDraftJsonbText).join(', ')}]';
  }
  if (value is Map && value.keys.every((key) => key is String)) {
    final keys = value.keys.cast<String>().toList();
    for (final key in keys) {
      _unicode(key);
    }
    keys.sort((left, right) {
      final a = utf8.encode(left), b = utf8.encode(right);
      if (a.length != b.length) return a.length.compareTo(b.length);
      for (var index = 0; index < a.length; index++) {
        if (a[index] != b[index]) return a[index].compareTo(b[index]);
      }
      return 0;
    });
    return '{${keys.map((key) => '${jsonEncode(key)}: ${fiscalDraftJsonbText(value[key])}').join(', ')}}';
  }
  throw const RuleException('JSON del ensayo debe conservar tipos enteros');
}

/// Matches private.fiscal_draft_fingerprint without substituting an AEAT hash.
Future<String> fiscalDraftLedgerHash(
  Map<String, dynamic> body,
  String previousHash,
) {
  if (previousHash.isNotEmpty &&
      !RegExp(r'^[A-F0-9]{64}$').hasMatch(previousHash)) {
    throw const RuleException('Huella interna anterior inválida');
  }
  return fiscalDraftSha256(
    'TALLERFLOW-DRAFT-1|$previousHash|${fiscalDraftJsonbText(body)}',
  );
}

/// Snapshot identity includes explicit technical settings, source and generator.
Future<String> fiscalDraftTechnicalHash(Map<String, dynamic> snapshot) =>
    fiscalDraftSha256(
      'TALLERFLOW-XML-SNAPSHOT-1|${fiscalDraftJsonbText(snapshot)}',
    );

Future<String> fiscalDraftSha256(String value) async {
  final digest = await Sha256().hash(utf8.encode(value));
  return digest.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}

void _unicode(String text) {
  final units = text.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    if (unit == 0) {
      throw const RuleException('JSON de ensayo no permite carácter nulo');
    }
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
        throw const RuleException('Texto Unicode inválido');
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw const RuleException('Texto Unicode inválido');
    }
  }
}
