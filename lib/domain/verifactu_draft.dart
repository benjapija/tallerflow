import 'engine.dart';
import 'fiscal_calculation.dart';
import 'fiscal_profile.dart';
import 'verifactu_hash.dart';

class VerifactuParty {
  final String name, nif;
  VerifactuParty({required String name, required String nif})
    : name = _text(name, 120),
      nif = _text(nif, 9) {
    if (!RegExp(r'^[A-Z0-9]{9}$').hasMatch(this.nif)) {
      throw const RuleException('NIF: estructura inválida');
    }
  }
  String get xml => '${_tag('NombreRazon', name)}${_tag('NIF', nif)}';
}

class VerifactuSystem {
  final VerifactuParty manufacturer;
  final String name, id, version, installation;
  final bool onlyVerifactu, canHaveMultipleTaxpayers, hasMultipleTaxpayers;
  VerifactuSystem({
    required this.manufacturer,
    required String name,
    required String id,
    required String version,
    required String installation,
    required this.onlyVerifactu,
    required this.canHaveMultipleTaxpayers,
    required this.hasMultipleTaxpayers,
  }) : name = _text(name, 30),
       id = _text(id, 2),
       version = _text(version, 50),
       installation = _text(installation, 100) {
    if (hasMultipleTaxpayers && !canHaveMultipleTaxpayers) {
      throw const RuleException('Indicadores de instalación incompatibles');
    }
  }
  String get xml =>
      '<sf:SistemaInformatico>${manufacturer.xml}'
      '${_tag('NombreSistemaInformatico', name)}'
      '${_tag('IdSistemaInformatico', id)}'
      '${_tag('Version', version)}'
      '${_tag('NumeroInstalacion', installation)}'
      '${_tag('TipoUsoPosibleSoloVerifactu', onlyVerifactu ? 'S' : 'N')}'
      '${_tag('TipoUsoPosibleMultiOT', canHaveMultipleTaxpayers ? 'S' : 'N')}'
      '${_tag('IndicadorMultiplesOT', hasMultipleTaxpayers ? 'S' : 'N')}'
      '</sf:SistemaInformatico>';
}

class VerifactuAnchor {
  final VerifactuIdentity identity;
  final String hash, generatedAt;
  VerifactuAnchor({
    required this.identity,
    required this.hash,
    required this.generatedAt,
  }) {
    validateFiscalTimestamp(generatedAt);
    if (!RegExp(r'^[A-F0-9]{64}$').hasMatch(hash)) {
      throw const RuleException('Registro anterior inválido');
    }
  }
  String get xml =>
      '<sf:RegistroAnterior>${_identity(identity)}${_tag('Huella', hash)}'
      '</sf:RegistroAnterior>';
}

class VerifactuDetail {
  final FiscalTaxGroup group;
  final String regime, classification;
  VerifactuDetail({
    required this.group,
    required this.regime,
    required this.classification,
  }) {
    if (!{
      '01',
      '02',
      '03',
      '04',
      '05',
      '06',
      '07',
      '08',
      '09',
      '10',
      '11',
      '14',
      '15',
      '17',
      '18',
      '19',
      '20',
      '21',
    }.contains(regime)) {
      throw const RuleException(
        'Clave de régimen no contemplada por el esquema',
      );
    }
    final valid = switch (group.treatment) {
      FiscalTreatment.taxable => classification == 'S1',
      FiscalTreatment.reverseCharge => classification == 'S2',
      FiscalTreatment.outsideScope => {'N1', 'N2'}.contains(classification),
      FiscalTreatment.exempt => RegExp(r'^E[1-8]$').hasMatch(classification),
    };
    if (!valid) {
      throw const RuleException('Calificación incompatible con la partida');
    }
  }
  String get xml {
    final taxCode = switch (group.tax) {
      FiscalTax.iva => '01',
      FiscalTax.ipsi => '02',
      FiscalTax.igic => '03',
      FiscalTax.other => '05',
    };
    return '<sf:DetalleDesglose>${_tag('Impuesto', taxCode)}'
        '${_tag('ClaveRegimen', regime)}'
        '${_tag(group.treatment == FiscalTreatment.exempt ? 'OperacionExenta' : 'CalificacionOperacion', classification)}'
        '${group.treatment == FiscalTreatment.taxable ? _tag('TipoImpositivo', fiscalDecimal(group.rateBps)) : ''}'
        '${_tag('BaseImponibleOimporteNoSujeto', fiscalDecimal(group.baseCents))}'
        '${group.treatment == FiscalTreatment.taxable ? _tag('CuotaRepercutida', fiscalDecimal(group.taxCents)) : ''}'
        '</sf:DetalleDesglose>';
  }
}

/// A local technical fixture, never an issued invoice or a submission receipt.
/// F1 domestic draft and cancellation only. Other circuits stay unsupported.
class VerifactuOfflineDraft {
  final String xml;
  final VerifactuHash hash;
  final VerifactuAnchor anchor;
  bool get emissionEnabled => false;
  bool get transmissionEnabled => false;
  const VerifactuOfflineDraft._(this.xml, this.hash, this.anchor);

  static Future<VerifactuOfflineDraft> high({
    required Map<String, dynamic> preparation,
    required VerifactuIdentity identity,
    required VerifactuParty issuer,
    required VerifactuParty recipient,
    required VerifactuSystem system,
    required FiscalCalculation calculation,
    required List<VerifactuDetail> details,
    required String description,
    required String generatedAt,
    VerifactuAnchor? previous,
  }) async {
    _preparation(preparation);
    if (issuer.nif != identity.issuerNif) {
      throw const RuleException('El emisor no coincide con el identificador');
    }
    if (calculation.adjustmentReason.isNotEmpty ||
        calculation.lines.any((l) => l.baseCents < 0)) {
      throw const RuleException('Las rectificaciones necesitan otro circuito');
    }
    if (details.isEmpty ||
        details.length > 12 ||
        details.length != calculation.groups.length ||
        details.map((d) => d.group).toSet().length != details.length ||
        details.any((d) => !calculation.groups.contains(d.group))) {
      throw const RuleException(
        'Revisa el desglose completo; máximo doce grupos',
      );
    }
    _chain(identity, generatedAt, previous);
    final operation = _text(description, 500);
    final hash = await VerifactuHash.high(
      identity: identity,
      invoiceType: 'F1',
      taxTotal: fiscalDecimal(calculation.taxCents),
      total: fiscalDecimal(calculation.totalCents),
      generatedAt: generatedAt,
      previousHash: previous?.hash ?? '',
    );
    final record =
        '<sf:RegistroAlta>${_tag('IDVersion', '1.0')}'
        '<sf:IDFactura>${_identity(identity)}</sf:IDFactura>'
        '${_tag('NombreRazonEmisor', issuer.name)}${_tag('TipoFactura', 'F1')}'
        '${_tag('DescripcionOperacion', operation)}'
        '<sf:Destinatarios><sf:IDDestinatario>${recipient.xml}'
        '</sf:IDDestinatario></sf:Destinatarios>'
        '<sf:Desglose>${details.map((d) => d.xml).join()}</sf:Desglose>'
        '${_tag('CuotaTotal', fiscalDecimal(calculation.taxCents))}'
        '${_tag('ImporteTotal', fiscalDecimal(calculation.totalCents))}'
        '${_chaining(previous)}${system.xml}'
        '${_tag('FechaHoraHusoGenRegistro', generatedAt)}'
        '${_tag('TipoHuella', '01')}${_tag('Huella', hash.hex)}</sf:RegistroAlta>';
    return VerifactuOfflineDraft._(
      _envelope(issuer, record),
      hash,
      VerifactuAnchor(
        identity: identity,
        hash: hash.hex,
        generatedAt: generatedAt,
      ),
    );
  }

  static Future<VerifactuOfflineDraft> cancellation({
    required Map<String, dynamic> preparation,
    required VerifactuIdentity identity,
    required VerifactuParty issuer,
    required VerifactuSystem system,
    required String generatedAt,
    required VerifactuAnchor previous,
  }) async {
    _preparation(preparation);
    if (identity.issuerNif != issuer.nif) {
      throw const RuleException('El emisor no coincide con el identificador');
    }
    _chain(identity, generatedAt, previous);
    final hash = await VerifactuHash.cancellation(
      identity: identity,
      generatedAt: generatedAt,
      previousHash: previous.hash,
    );
    final record =
        '<sf:RegistroAnulacion>${_tag('IDVersion', '1.0')}'
        '<sf:IDFactura>${identity.cancellationFields.entries.map((e) => _tag(e.key, e.value)).join()}</sf:IDFactura>'
        '${_chaining(previous)}${system.xml}'
        '${_tag('FechaHoraHusoGenRegistro', generatedAt)}'
        '${_tag('TipoHuella', '01')}${_tag('Huella', hash.hex)}'
        '</sf:RegistroAnulacion>';
    return VerifactuOfflineDraft._(
      _envelope(issuer, record),
      hash,
      VerifactuAnchor(
        identity: identity,
        hash: hash.hex,
        generatedAt: generatedAt,
      ),
    );
  }
}

void _preparation(Map<String, dynamic> input) {
  final p = validateFiscalProfile(input);
  if (p['sii'] != 'no' ||
      !{'common', 'canary', 'ceuta', 'melilla'}.contains(p['territory'])) {
    throw const RuleException(
      'El borrador estatal no cubre SII, territorio pendiente o régimen foral',
    );
  }
}

void _chain(VerifactuIdentity identity, String at, VerifactuAnchor? previous) {
  if (previous == null) return;
  if (identity.issuerNif != previous.identity.issuerNif ||
      DateTime.tryParse(at) == null ||
      !DateTime.parse(at).isAfter(DateTime.parse(previous.generatedAt))) {
    throw const RuleException('Cadena de otro emisor o fecha no posterior');
  }
}

String _identity(VerifactuIdentity identity) =>
    identity.highFields.entries.map((e) => _tag(e.key, e.value)).join();

String _chaining(VerifactuAnchor? p) =>
    '<sf:Encadenamiento>${p?.xml ?? _tag('PrimerRegistro', 'S')}'
    '</sf:Encadenamiento>';

String _envelope(VerifactuParty issuer, String record) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<sfLR:RegFactuSistemaFacturacion '
    'xmlns:sfLR="https://www2.agenciatributaria.gob.es/static_files/common/internet/dep/aplicaciones/es/aeat/tike/cont/ws/SuministroLR.xsd" '
    'xmlns:sf="https://www2.agenciatributaria.gob.es/static_files/common/internet/dep/aplicaciones/es/aeat/tike/cont/ws/SuministroInformacion.xsd">'
    '<sfLR:Cabecera><sf:ObligadoEmision>${issuer.xml}</sf:ObligadoEmision>'
    '</sfLR:Cabecera><sfLR:RegistroFactura>$record</sfLR:RegistroFactura>'
    '</sfLR:RegFactuSistemaFacturacion>';

String _tag(String name, String value) =>
    '<sf:$name>${_escape(value)}</sf:$name>';

String _escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _text(String value, int max) {
  final text = value.trim();
  if (text.isEmpty ||
      text.runes.length > max ||
      text.codeUnits.any((c) => c < 32 || c == 0xfffe || c == 0xffff)) {
    throw const RuleException('Texto del registro inválido');
  }
  return text;
}
