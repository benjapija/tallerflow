import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'engine.dart';
import 'fiscal_calculation.dart';

/// Offline AEAT primitives. No transport, credentials or fiscal emission.
class VerifactuIdentity {
  final String issuerNif, number, issueDate;
  VerifactuIdentity({
    required String issuerNif,
    required String number,
    required String issueDate,
  }) : issuerNif = issuerNif.trim(),
       number = number.trim(),
       issueDate = issueDate.trim() {
    // Structural validation only; no assertion that this taxpayer exists.
    if (!RegExp(r'^[A-Z0-9]{9}$').hasMatch(this.issuerNif)) {
      throw const RuleException('NIF: estructura inválida');
    }
    if (this.number.isEmpty ||
        this.number.length > 60 ||
        this.number.codeUnits.any((c) => c < 32 || c > 126)) {
      throw const RuleException('Serie y número inválidos');
    }
    validateFiscalDate(this.issueDate);
  }

  Map<String, String> get highFields => {
    'IDEmisorFactura': issuerNif,
    'NumSerieFactura': number,
    'FechaExpedicionFactura': issueDate,
  };
  Map<String, String> get cancellationFields => {
    'IDEmisorFacturaAnulada': issuerNif,
    'NumSerieFacturaAnulada': number,
    'FechaExpedicionFacturaAnulada': issueDate,
  };
}

class VerifactuHash {
  final String canonical, hex;
  const VerifactuHash._(this.canonical, this.hex);

  static Future<VerifactuHash> high({
    required VerifactuIdentity identity,
    required String invoiceType,
    required String taxTotal,
    required String total,
    required String generatedAt,
    String previousHash = '',
  }) async {
    if (!{
      'F1',
      'F2',
      'F3',
      'R1',
      'R2',
      'R3',
      'R4',
      'R5',
    }.contains(invoiceType)) {
      throw const RuleException('Tipo de registro inválido');
    }
    _decimal(taxTotal);
    _decimal(total);
    validateFiscalTimestamp(generatedAt);
    _previous(previousHash);
    return _digest({
      ...identity.highFields,
      'TipoFactura': invoiceType,
      'CuotaTotal': taxTotal.trim(),
      'ImporteTotal': total.trim(),
      'Huella': previousHash,
      'FechaHoraHusoGenRegistro': generatedAt,
    });
  }

  static Future<VerifactuHash> cancellation({
    required VerifactuIdentity identity,
    required String generatedAt,
    String previousHash = '',
  }) async {
    validateFiscalTimestamp(generatedAt);
    _previous(previousHash);
    return _digest({
      ...identity.cancellationFields,
      'Huella': previousHash,
      'FechaHoraHusoGenRegistro': generatedAt,
    });
  }

  static Future<VerifactuHash> _digest(Map<String, String> fields) async {
    final canonical = fields.entries
        .map((e) => '${e.key}=${e.value}')
        .join('&');
    final hash = await Sha256().hash(utf8.encode(canonical));
    final hex = hash.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    return VerifactuHash._(canonical, hex);
  }
}

/// Builds only the documented test URL. Production is deliberately unavailable.
Uri verifactuTestQr(VerifactuIdentity identity, int totalCents) =>
    Uri.https('prewww2.aeat.es', '/wlpl/TIKE-CONT/ValidarQR', {
      'nif': identity.issuerNif,
      'numserie': identity.number,
      'fecha': identity.issueDate,
      'importe': fiscalDecimal(totalCents),
    });

void validateFiscalDate(String value) {
  if (!RegExp(r'^\d{2}-\d{2}-\d{4}$').hasMatch(value)) {
    throw const RuleException('Fecha: utiliza DD-MM-AAAA');
  }
  final p = value.split('-').map(int.parse).toList();
  final d = DateTime.utc(p[2], p[1], p[0]);
  if (p[2] < 1900 || d.year != p[2] || d.month != p[1] || d.day != p[0]) {
    throw const RuleException('Fecha fiscal inexistente');
  }
}

void _decimal(String value) {
  if (!RegExp(r'^-?\d{1,12}\.\d{1,2}$').hasMatch(value.trim())) {
    throw const RuleException('Importe: utiliza punto y uno o dos decimales');
  }
}

void _previous(String value) {
  if (value.isNotEmpty && !RegExp(r'^[0-9A-F]{64}$').hasMatch(value)) {
    throw const RuleException('Huella anterior inválida');
  }
}

void validateFiscalTimestamp(String value) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})([+-])(\d{2}):(\d{2})$',
  ).firstMatch(value);
  if (match == null) {
    throw const RuleException('Fecha de registro: indica el huso horario');
  }
  validateFiscalDate('${match[3]}-${match[2]}-${match[1]}');
  if (int.parse(match[4]!) > 23 ||
      int.parse(match[5]!) > 59 ||
      int.parse(match[6]!) > 59 ||
      int.parse(match[8]!) > 14 ||
      int.parse(match[9]!) > 59 ||
      (match[8] == '14' && match[9] != '00')) {
    throw const RuleException('Hora o huso horario inválidos');
  }
}
