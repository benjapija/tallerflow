import 'dart:convert';
import 'engine.dart';
import 'fiscal_calculation.dart';
import 'fiscal_draft_integrity.dart';
import 'fiscal_profile.dart';
import 'planning_time.dart';
import 'verifactu_draft.dart';
import 'verifactu_hash.dart';
import 'package:timezone/timezone.dart' as tz;

/// Versioned, reproducible technical projection. Never an issued invoice or an
/// AEAT acknowledgement. Original records and internal fingerprints stay intact.
const fiscalDraftXmlGeneratorVersion = 'tallerflow-sandbox-f1-1';

class FiscalDraftXmlArtifact {
  final String recordId, ledgerHash, previousLedgerHash;
  final int sequence;
  final String xml, xmlSha256, aeatHash, inputHash, generatedAt;
  final String? previousXmlRecordId;
  final Map<String, dynamic> snapshot;
  String get generatorVersion => fiscalDraftXmlGeneratorVersion;
  bool get emissionEnabled => false;
  bool get transmissionEnabled => false;

  const FiscalDraftXmlArtifact._({
    required this.recordId,
    required this.sequence,
    required this.ledgerHash,
    required this.previousLedgerHash,
    required this.xml,
    required this.xmlSha256,
    required this.aeatHash,
    required this.inputHash,
    required this.generatedAt,
    required this.previousXmlRecordId,
    required this.snapshot,
  });

  Map<String, dynamic> toJson() => {
    'artifactFormat': 1,
    'scope': 'sandbox',
    'generatorVersion': generatorVersion,
    'recordId': recordId,
    'sequence': sequence,
    'ledgerHash': ledgerHash,
    'previousLedgerHash': previousLedgerHash,
    'aeatHash': aeatHash,
    'inputHash': inputHash,
    'xmlSha256': xmlSha256,
    'generatedAt': generatedAt,
    'previousXmlRecordId': previousXmlRecordId,
    'emissionEnabled': false,
    'transmissionEnabled': false,
    'snapshot': _copy(snapshot),
    'xml': xml,
  };
}

class FiscalDraftXmlChain {
  final List<FiscalDraftXmlArtifact> artifacts;

  /// A sandbox withdrawal is deliberately not an AEAT cancellation.
  final List<Map<String, dynamic>> withdrawals;
  final Set<String> withdrawnRecordIds;
  bool get emissionEnabled => false;
  bool get transmissionEnabled => false;
  const FiscalDraftXmlChain._(
    this.artifacts,
    this.withdrawals,
    this.withdrawnRecordIds,
  );

  /// Complete ordered records from the authenticated admin RPC, one workshop,
  /// issuer and installation. Missing predecessors or modified snapshots fail.
  /// Format 1 contains no tax regime/classification or rectification metadata;
  /// only the explicitly named F1 general-regime technical projection is built.
  static Future<FiscalDraftXmlChain> generateGeneralRegime({
    required List<Map<String, dynamic>> confirmedRecords,
    required Map<String, dynamic> preparation,
    required VerifactuParty issuer,
    required VerifactuSystem system,
    String dateValidationZone = 'Europe/Madrid',
  }) async {
    final profile = validateFiscalProfile(_copy(preparation));
    if (profile['sii'] != 'no' ||
        !{
          'common',
          'canary',
          'ceuta',
          'melilla',
        }.contains(profile['territory'])) {
      throw const RuleException(
        'El XML estatal de ensayo no cubre este perfil',
      );
    }
    if (confirmedRecords.isEmpty || confirmedRecords.length > 10000) {
      throw const RuleException('Indica la cadena de ensayo completa');
    }
    final records = confirmedRecords.map(_copy).toList();
    final first = records.first;
    final workshop = _uuid(first['workshop_id']);
    final installation = _text(first['installation'], 80);
    if (installation != system.installation ||
        issuer.nif != first['issuer_nif']) {
      throw const RuleException(
        'El emisor o sistema no coincide con el registro',
      );
    }
    final settings = _systemSnapshot(system);
    final dateLocation = PlanningTime.location(dateValidationZone);
    final artifacts = <FiscalDraftXmlArtifact>[];
    final withdrawals = <Map<String, dynamic>>[];
    final originals = <String, Map<String, dynamic>>{};
    final withdrawn = <String>{};
    final ids = <String>{};
    final counters = <String, int>{};
    var sequence = 0, previousLedger = '';
    DateTime? previousInstant;
    VerifactuAnchor? previousXml;
    String? previousXmlId;
    for (final record in records) {
      final body = _map(record['body']);
      final id = _uuid(record['id']);
      final prefix = _text(record['prefix'], 23);
      final number = _int(record['number'], 1, 999999999);
      final ledgerHash = _hash(record['ledger_hash']);
      final kind = record['kind'];
      sequence++;
      if (!ids.add(id) ||
          record['workshop_id'] != workshop ||
          record['issuer_nif'] != issuer.nif ||
          record['installation'] != installation ||
          _int(record['sequence'], 1, 999999999) != sequence ||
          record['previous_hash'] != previousLedger ||
          !RegExp(r'^ENSAYO-[A-Z0-9-]{1,16}$').hasMatch(prefix) ||
          !{'draft', 'withdrawal'}.contains(kind) ||
          body['draftFormat'] != 1 ||
          body['scope'] != 'sandbox' ||
          body['emissionEnabled'] != false ||
          body['transmissionEnabled'] != false ||
          body['id'] != id ||
          body['sequence'] != sequence ||
          body['kind'] != kind ||
          body['issuerNif'] != issuer.nif ||
          body['installation'] != installation ||
          body['prefix'] != prefix ||
          body['number'] != number ||
          body['actorId'] != _uuid(record['actor_id']) ||
          body['deviceId'] != _uuid(record['device_id'])) {
        throw const RuleException(
          'La cadena confirmada está incompleta o alterada',
        );
      }
      _text(body['reason'], 2000);
      if (await fiscalDraftLedgerHash(body, previousLedger) != ledgerHash) {
        throw const RuleException(
          'La huella interna no coincide con el original',
        );
      }
      final sourceTimestamp = _text(body['createdAt'], 40);
      final instant = _instant(sourceTimestamp);
      if (previousInstant != null && instant.isBefore(previousInstant)) {
        throw const RuleException('El orden temporal de ensayo es incoherente');
      }
      previousInstant = instant;
      if (kind == 'withdrawal') {
        final target = _uuid(record['target_id']);
        final original = originals[target];
        if (body.keys.any(
              (key) =>
                  !_commonBodyKeys.contains(key) &&
                  !{'targetId', 'originalLedgerHash'}.contains(key),
            ) ||
            original == null ||
            !withdrawn.add(target) ||
            body['targetId'] != target ||
            body['originalLedgerHash'] != original['ledger_hash'] ||
            prefix != original['prefix'] ||
            number != original['number']) {
          throw const RuleException('La retirada no corresponde al original');
        }
        withdrawals.add(_freeze(record));
      } else {
        if (record['target_id'] != null ||
            body.keys.any(
              (key) =>
                  !_commonBodyKeys.contains(key) &&
                  !{'calculation', 'issueDate', 'recipient'}.contains(key),
            ) ||
            number != (counters[prefix] ?? 0) + 1) {
          throw const RuleException(
            'Serie de ensayo incoherente o datos no soportados',
          );
        }
        counters[prefix] = number;
        final calculation = FiscalCalculation.fromConfirmedSandbox(
          _map(body['calculation']),
        );
        if (calculation.groups.length > 12 ||
            calculation.groups.any(
              (group) =>
                  group.treatment != FiscalTreatment.taxable ||
                  group.tax == FiscalTax.other,
            )) {
          throw const RuleException(
            'Este XML de ensayo requiere F1, régimen general y partidas sujetas',
          );
        }
        final date = _isoDate(body['issueDate']);
        final generatedAt = _secondTimestamp(instant);
        _generalRegimeRules(
          calculation,
          date,
          tz.TZDateTime.from(instant, dateLocation),
        );
        final recipientData = _map(body['recipient']);
        if (recipientData.length != 2 ||
            !recipientData.containsKey('name') ||
            !recipientData.containsKey('nif')) {
          throw const RuleException('Destinatario confirmado no soportado');
        }
        final recipient = VerifactuParty(
          name: _text(recipientData['name'], 120),
          nif: _text(recipientData['nif'], 9),
        );
        final identity = VerifactuIdentity(
          issuerNif: issuer.nif,
          number: '$prefix/$number',
          issueDate: date,
        );
        final description = calculation.lines
            .map((line) => line.source.description)
            .join('; ');
        final draft = await VerifactuOfflineDraft.high(
          preparation: profile,
          identity: identity,
          issuer: issuer,
          recipient: recipient,
          system: system,
          calculation: calculation,
          details: [
            for (final group in calculation.groups)
              VerifactuDetail(group: group, regime: '01', classification: 'S1'),
          ],
          description: description,
          generatedAt: generatedAt,
          previous: previousXml,
        );
        final snapshot = _freeze({
          'generatorVersion': fiscalDraftXmlGeneratorVersion,
          'sourceRecord': record,
          'preparation': profile,
          'issuer': {'name': issuer.name, 'nif': issuer.nif},
          'system': settings,
          'technicalScope': 'F1-general-regime-S1-domestic-sandbox',
          'dateValidationZone': dateValidationZone,
          'sourceTimestamp': sourceTimestamp,
          'generatedAt': generatedAt,
          'previousXml': previousXml == null
              ? null
              : {
                  'recordId': previousXmlId,
                  'issuerNif': previousXml.identity.issuerNif,
                  'number': previousXml.identity.number,
                  'issueDate': previousXml.identity.issueDate,
                  'aeatHash': previousXml.hash,
                  'generatedAt': previousXml.generatedAt,
                },
        });
        artifacts.add(
          FiscalDraftXmlArtifact._(
            recordId: id,
            sequence: sequence,
            ledgerHash: ledgerHash,
            previousLedgerHash: previousLedger,
            xml: draft.xml,
            xmlSha256: await fiscalDraftSha256(draft.xml),
            aeatHash: draft.hash.hex,
            inputHash: await fiscalDraftTechnicalHash(snapshot),
            generatedAt: generatedAt,
            previousXmlRecordId: previousXmlId,
            snapshot: snapshot,
          ),
        );
        originals[id] = record;
        previousXml = draft.anchor;
        previousXmlId = id;
      }
      previousLedger = ledgerHash;
    }
    return FiscalDraftXmlChain._(
      List.unmodifiable(artifacts),
      List.unmodifiable(withdrawals),
      Set.unmodifiable(withdrawn),
    );
  }
}

/// Checks the conserved bytes and their confirmed-source correspondence before
/// reading a saved artifact. Chain correctness is established during generation
/// from the complete authenticated RPC; hashes alone are not a signature.
Future<void> validateFiscalDraftXmlStoredArtifact(
  Map<String, dynamic> stored, {
  required Map<String, dynamic> confirmedRecord,
}) async {
  final value = _copy(stored), source = _copy(confirmedRecord);
  final snapshot = _map(value['snapshot']);
  final original = _map(snapshot['sourceRecord']);
  final rawPrevious = snapshot['previousXml'];
  final prior = rawPrevious == null ? null : _map(rawPrevious);
  if (value['artifactFormat'] != 1 ||
      value['scope'] != 'sandbox' ||
      value['generatorVersion'] != fiscalDraftXmlGeneratorVersion ||
      snapshot['generatorVersion'] != fiscalDraftXmlGeneratorVersion ||
      value['emissionEnabled'] != false ||
      value['transmissionEnabled'] != false ||
      value['recordId'] != source['id'] ||
      value['sequence'] != source['sequence'] ||
      value['ledgerHash'] != source['ledger_hash'] ||
      value['previousLedgerHash'] != source['previous_hash'] ||
      value['generatedAt'] != snapshot['generatedAt'] ||
      value['previousXmlRecordId'] != prior?['recordId'] ||
      source['kind'] != 'draft') {
    throw const RuleException(
      'XML conservado no corresponde al registro confirmado',
    );
  }
  // Recovery may rebind workshop_id; immutable body/id/chain fields stay exact.
  final rebound = {...source}..remove('workshop_id');
  final old = {...original}..remove('workshop_id');
  if (fiscalDraftJsonbText(rebound) != fiscalDraftJsonbText(old) ||
      await fiscalDraftLedgerHash(
            _map(source['body']),
            source['previous_hash'] as String,
          ) !=
          source['ledger_hash'] ||
      await fiscalDraftTechnicalHash(snapshot) != value['inputHash'] ||
      value['xml'] is! String ||
      await fiscalDraftSha256(value['xml'] as String) != value['xmlSha256']) {
    throw const RuleException('El XML o su snapshot conservado está alterado');
  }
  _hash(value['aeatHash']);
  final body = _map(source['body']);
  final issuer = _party(snapshot['issuer']);
  final technical = _map(snapshot['system']);
  final system = VerifactuSystem(
    manufacturer: _party(technical['manufacturer']),
    name: _text(technical['name'], 30),
    id: _text(technical['id'], 2),
    version: _text(technical['version'], 50),
    installation: _text(technical['installation'], 100),
    onlyVerifactu: _bool(technical['onlyVerifactu']),
    canHaveMultipleTaxpayers: _bool(technical['canHaveMultipleTaxpayers']),
    hasMultipleTaxpayers: _bool(technical['hasMultipleTaxpayers']),
  );
  final at = _instant(_text(body['createdAt'], 40));
  if (snapshot['technicalScope'] != 'F1-general-regime-S1-domestic-sandbox' ||
      snapshot['sourceTimestamp'] != body['createdAt'] ||
      snapshot['generatedAt'] != _secondTimestamp(at) ||
      issuer.nif != source['issuer_nif'] ||
      system.installation != source['installation'] ||
      (prior == null && source['sequence'] != 1)) {
    throw const RuleException('Contexto técnico conservado inválido');
  }
  final calculation = FiscalCalculation.fromConfirmedSandbox(
    _map(body['calculation']),
  );
  if (calculation.groups.any(
    (group) =>
        group.treatment != FiscalTreatment.taxable ||
        group.tax == FiscalTax.other,
  )) {
    throw const RuleException(
      'Desglose conservado fuera del circuito de ensayo',
    );
  }
  final previous = prior == null
      ? null
      : VerifactuAnchor(
          identity: VerifactuIdentity(
            issuerNif: _text(prior['issuerNif'], 9),
            number: _text(prior['number'], 60),
            issueDate: _text(prior['issueDate'], 10),
          ),
          hash: _hash(prior['aeatHash']),
          generatedAt: _text(prior['generatedAt'], 40),
        );
  final date = _isoDate(body['issueDate']);
  final zone = _text(snapshot['dateValidationZone'], 40);
  _generalRegimeRules(
    calculation,
    date,
    tz.TZDateTime.from(at, PlanningTime.location(zone)),
  );
  final regenerated = await VerifactuOfflineDraft.high(
    preparation: _map(snapshot['preparation']),
    identity: VerifactuIdentity(
      issuerNif: issuer.nif,
      number: '${source['prefix']}/${source['number']}',
      issueDate: date,
    ),
    issuer: issuer,
    recipient: _party(body['recipient']),
    system: system,
    calculation: calculation,
    details: [
      for (final group in calculation.groups)
        VerifactuDetail(group: group, regime: '01', classification: 'S1'),
    ],
    description: calculation.lines
        .map((line) => line.source.description)
        .join('; '),
    generatedAt: snapshot['generatedAt'] as String,
    previous: previous,
  );
  if (regenerated.xml != value['xml'] ||
      regenerated.hash.hex != value['aeatHash']) {
    throw const RuleException('El XML no reproduce el snapshot conservado');
  }
}

VerifactuParty _party(dynamic value) {
  final data = _map(value);
  if (data.length != 2 ||
      !data.containsKey('name') ||
      !data.containsKey('nif')) {
    throw const RuleException('Identificación técnica conservada inválida');
  }
  return VerifactuParty(
    name: _text(data['name'], 120),
    nif: _text(data['nif'], 9),
  );
}

bool _bool(dynamic value) {
  if (value is! bool) throw const RuleException('Indicador técnico inválido');
  return value;
}

const _commonBodyKeys = {
  'draftFormat',
  'scope',
  'emissionEnabled',
  'transmissionEnabled',
  'id',
  'issuerNif',
  'installation',
  'sequence',
  'kind',
  'prefix',
  'number',
  'reason',
  'actorId',
  'deviceId',
  'createdAt',
};

void _generalRegimeRules(
  FiscalCalculation calculation,
  String date,
  DateTime at,
) {
  final parts = date.split('-').map(int.parse).toList();
  final issue = DateTime.utc(parts[2], parts[1], parts[0]);
  // Local deterministic subset of published AEAT v1.2.2 business validations.
  // No census check, server-clock threshold or legal applicability is asserted.
  if (issue.isBefore(DateTime.utc(2024, 10, 28)) ||
      issue.isAfter(DateTime.utc(at.year, at.month, at.day))) {
    throw const RuleException(
      'Fecha fuera del intervalo del XML estatal de ensayo',
    );
  }
  if (calculation.totalCents >= 10000000000) {
    throw const RuleException(
      'Macrodato requiere un circuito todavía no soportado',
    );
  }
  for (final group in calculation.groups) {
    if (group.tax == FiscalTax.iva) {
      final temporary =
          issue.year == 2024 &&
          issue.month >= 10 &&
          {200, 750}.contains(group.rateBps);
      if (!{0, 400, 1000, 2100}.contains(group.rateBps) && !temporary) {
        throw const RuleException(
          'Tipo IVA no admitido para esta fecha en ensayo general',
        );
      }
    }
    // AEAT validates the group amount with +/- 10 EUR tolerance. The source
    // rounds each saved line; never force a second rounding of the group total.
    final difference =
        (BigInt.from(group.taxCents) * BigInt.from(10000) -
                BigInt.from(group.baseCents) * BigInt.from(group.rateBps))
            .abs();
    if (difference > BigInt.from(10000000)) {
      throw const RuleException(
        'Cuota agrupada fuera de la validación técnica',
      );
    }
  }
}

Map<String, dynamic> _systemSnapshot(VerifactuSystem system) => {
  'manufacturer': {
    'name': system.manufacturer.name,
    'nif': system.manufacturer.nif,
  },
  'name': system.name,
  'id': system.id,
  'version': system.version,
  'installation': system.installation,
  'onlyVerifactu': system.onlyVerifactu,
  'canHaveMultipleTaxpayers': system.canHaveMultipleTaxpayers,
  'hasMultipleTaxpayers': system.hasMultipleTaxpayers,
};
Map<String, dynamic> _map(dynamic value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const RuleException('Objeto confirmado inválido');
  }
  return Map<String, dynamic>.from(value);
}

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    _map(jsonDecode(jsonEncode(value)));
Map<String, dynamic> _freeze(Map<String, dynamic> value) {
  dynamic freeze(dynamic v) => v is Map
      ? Map<String, dynamic>.unmodifiable(
          v.map((k, v) => MapEntry(k as String, freeze(v))),
        )
      : v is List
      ? List<dynamic>.unmodifiable(v.map(freeze))
      : v;
  return freeze(_copy(value)) as Map<String, dynamic>;
}

String _text(dynamic value, int max) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.runes.length > max ||
      value.codeUnits.any(
        (code) =>
            (code < 32 && !{9, 10, 13}.contains(code)) ||
            code == 0xfffe ||
            code == 0xffff,
      )) {
    throw const RuleException('Texto confirmado inválido');
  }
  return value;
}

String _uuid(dynamic value) {
  final text = _text(value, 36);
  if (!RegExp(
    r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
  ).hasMatch(text)) {
    throw const RuleException('Identidad confirmada inválida');
  }
  return text;
}

int _int(dynamic value, int low, int high) {
  if (value is! int || value < low || value > high) {
    throw const RuleException('Número confirmado inválido');
  }
  return value;
}

String _hash(dynamic value) {
  final text = _text(value, 64);
  if (!RegExp(r'^[A-F0-9]{64}$').hasMatch(text)) {
    throw const RuleException('Huella interna confirmada inválida');
  }
  return text;
}

String _isoDate(dynamic value) {
  final text = _text(value, 10);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
    throw const RuleException('Fecha confirmada inválida');
  }
  final parts = text.split('-');
  final result = '${parts[2]}-${parts[1]}-${parts[0]}';
  validateFiscalDate(result);
  return result;
}

DateTime _instant(String text) {
  if (!RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?([+-]\d{2}:\d{2}|Z)$',
  ).hasMatch(text)) {
    throw const RuleException('Hora confirmada inválida');
  }
  final withoutFraction = text
      .replaceFirst(RegExp(r'\.\d{1,6}'), '')
      .replaceFirst(RegExp(r'Z$'), '+00:00');
  validateFiscalTimestamp(withoutFraction);
  return DateTime.parse(text).toUtc();
}

String _secondTimestamp(DateTime value) =>
    '${value.toIso8601String().split('.').first}+00:00';
