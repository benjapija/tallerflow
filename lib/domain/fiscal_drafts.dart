import 'engine.dart';
import 'models.dart';
import 'fiscal_draft_integrity.dart';

const fiscalDraftActions = {'fiscal_draft_append', 'fiscal_draft_withdraw'};
final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final _nif = RegExp(r'^[A-Z0-9]{9}$');
final _hash = RegExp(r'^[A-F0-9]{64}$');
final _prefix = RegExp(r'^ENSAYO-[A-Z0-9-]{1,16}$');

Map<String, dynamic> emptyFiscalDraftLedger() => {
  'scope': 'sandbox',
  'emissionEnabled': false,
  'transmissionEnabled': false,
  'heads': <Map<String, dynamic>>[],
  'series': <Map<String, dynamic>>[],
  'records': <Map<String, dynamic>>[],
};

String _text(dynamic value, String field, [int max = 2000]) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.trim().length > max ||
      value.contains('\u0000')) {
    throw RuleException('$field: revisa el texto');
  }
  return value.trim();
}

int _integer(dynamic value, String field, int min, int max) {
  if (value is! int || value < min || value > max) {
    throw RuleException('$field fuera de rango');
  }
  return value;
}

bool fiscalDraftSame(Object? a, Object? b) =>
    fiscalDraftJsonbText(a) == fiscalDraftJsonbText(b);

/// The sandbox server rounds the discounted base once. BigInt also keeps
/// intermediate products exact when compiled to JavaScript for the web demo.
Map<String, dynamic> fiscalDraftCalculation(List<Map<String, dynamic>> input) {
  if (input.isEmpty || input.length > 1000) {
    throw const RuleException('Añade entre una y mil partidas de ensayo');
  }
  final ids = <String>{}, lines = <Map<String, dynamic>>[];
  var baseSum = 0, taxSum = 0;
  int rounded(BigInt numerator, int denominator) =>
      ((numerator + BigInt.from(denominator ~/ 2)) ~/ BigInt.from(denominator))
          .toInt();
  for (final line in input) {
    if (line.keys.any(
          (k) => !{
            'id',
            'description',
            'unitCents',
            'quantityMilli',
            'discountBps',
            'taxBps',
            'tax',
            'treatment',
            'reason',
          }.contains(k),
        ) ||
        line['id'] is! String ||
        !_uuid.hasMatch(line['id']) ||
        !ids.add(line['id'])) {
      throw const RuleException('Identidad de partida inválida o repetida');
    }
    final description = _text(line['description'], 'Descripción', 500);
    final price = _integer(line['unitCents'], 'Precio', 0, 1000000000000);
    final qty = _integer(line['quantityMilli'], 'Cantidad', 1, 1000000000);
    final discount = _integer(line['discountBps'], 'Descuento', 0, 10000);
    final rate = _integer(line['taxBps'], 'Tipo', 0, 10000);
    if (!{'iva', 'igic', 'ipsi', 'other'}.contains(line['tax']) ||
        !{
          'taxable',
          'exempt',
          'reverse_charge',
          'outside_scope',
        }.contains(line['treatment']) ||
        (line.containsKey('reason') && line['reason'] is! String)) {
      throw const RuleException('Impuesto o tratamiento de ensayo inválido');
    }
    if (line['treatment'] != 'taxable') {
      _text(line['reason'], 'Motivo del tratamiento');
      if (rate != 0) {
        throw const RuleException('El tratamiento especial exige cuota cero');
      }
    }
    final base = rounded(
      BigInt.from(price) * BigInt.from(qty) * BigInt.from(10000 - discount),
      10000000,
    );
    if (base > 1000000000000) {
      throw const RuleException('Base de ensayo fuera de rango');
    }
    final tax = line['treatment'] == 'taxable'
        ? rounded(BigInt.from(base) * BigInt.from(rate), 10000)
        : 0;
    baseSum += base;
    taxSum += tax;
    if (baseSum + taxSum > 1000000000000) {
      throw const RuleException('Total de ensayo fuera de rango');
    }
    lines.add({
      ...line,
      'description': description,
      'baseCents': base,
      'taxCents': tax,
      'totalCents': base + tax,
    });
  }
  return {
    'lines': lines,
    'baseCents': baseSum,
    'taxCents': taxSum,
    'totalCents': baseSum + taxSum,
  };
}

Map<String, dynamic> normalizeFiscalDraftPayload(
  String action,
  Map<String, dynamic> input, {
  bool withExpectation = true,
}) {
  if (!fiscalDraftActions.contains(action) ||
      input.keys.any(
        (k) => !{
          'issuerNif',
          'installation',
          'prefix',
          'reason',
          'lines',
          'issueDate',
          'recipient',
          'targetId',
          if (withExpectation) 'expectedSequence',
          if (withExpectation) 'expectedHash',
        }.contains(k),
      )) {
    throw const RuleException('Comando de ensayo incompatible');
  }
  final p = cloneMap(input);
  p['issuerNif'] = _text(p['issuerNif'], 'NIF del emisor', 9);
  p['installation'] = _text(p['installation'], 'Instalación de ensayo', 80);
  p['reason'] = _text(p['reason'], 'Motivo del ensayo');
  if (!_nif.hasMatch(p['issuerNif']) ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(p['installation'])) {
    throw const RuleException('Identificación de ensayo inválida');
  }
  if (withExpectation) {
    _integer(p['expectedSequence'], 'Secuencia esperada', 0, 999999999);
    if (p['expectedHash'] is! String ||
        (p['expectedSequence'] == 0
            ? p['expectedHash'] != ''
            : !_hash.hasMatch(p['expectedHash']))) {
      throw const RuleException('Cabecera de ensayo incompatible');
    }
  }
  if (action == 'fiscal_draft_append') {
    if (p.containsKey('targetId') ||
        p['prefix'] is! String ||
        !_prefix.hasMatch(p['prefix'])) {
      throw const RuleException(
        'Utiliza una serie ENSAYO- y conserva el original',
      );
    }
    final date = p['issueDate'];
    final parsed = date is String ? DateTime.tryParse(date) : null;
    if (date is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        parsed == null ||
        parsed.toIso8601String().substring(0, 10) != date) {
      throw const RuleException('Fecha de ensayo inválida');
    }
    if (p['recipient'] is! Map ||
        (p['recipient'] as Map).keys.any((k) => !{'name', 'nif'}.contains(k))) {
      throw const RuleException('Destinatario de ensayo inválido');
    }
    final recipient = Map<String, dynamic>.from(p['recipient']);
    recipient['name'] = _text(
      recipient['name'],
      'Nombre del destinatario',
      120,
    );
    if (recipient['nif'] is! String || !_nif.hasMatch(recipient['nif'])) {
      throw const RuleException('NIF de destinatario inválido');
    }
    p['recipient'] = recipient;
    if (p['lines'] is! List || (p['lines'] as List).any((l) => l is! Map)) {
      throw const RuleException('Partidas de ensayo inválidas');
    }
    final calculation = fiscalDraftCalculation(
      (p['lines'] as List).map((l) => Map<String, dynamic>.from(l)).toList(),
    );
    p['lines'] = (calculation['lines'] as List)
        .map(
          (l) => Map<String, dynamic>.from(l)
            ..remove('baseCents')
            ..remove('taxCents')
            ..remove('totalCents'),
        )
        .toList();
  } else {
    if (p.keys.any({'lines', 'issueDate', 'recipient', 'prefix'}.contains) ||
        p['targetId'] is! String ||
        !_uuid.hasMatch(p['targetId'])) {
      throw const RuleException(
        'La retirada solo conserva referencia y motivo',
      );
    }
  }
  return p;
}

List<Map<String, dynamic>> fiscalDraftRows(dynamic values) {
  if (values is! List || values.any((v) => v is! Map)) {
    throw const RuleException('Registro de ensayo incompleto');
  }
  return values.map((v) => Map<String, dynamic>.from(v)).toList();
}

/// Validate every immutable original before using a cached or remote snapshot.
Future<Map<String, dynamic>> validateFiscalDraftLedger(
  dynamic value,
  String workshopId,
) async {
  if (value is! Map ||
      value['scope'] != 'sandbox' ||
      value['emissionEnabled'] != false ||
      value['transmissionEnabled'] != false) {
    throw const RuleException(
      'La respuesta no identifica un registro de ensayo',
    );
  }
  final ledger = cloneMap(Map<String, dynamic>.from(value));
  final heads = fiscalDraftRows(ledger['heads']),
      series = fiscalDraftRows(ledger['series']),
      records = fiscalDraftRows(ledger['records']);
  String chain(Map row) => '${row['issuer_nif']}|${row['installation']}';
  final headKeys = <String>{},
      recordIds = <String>{},
      seriesKeys = <String>{},
      withdrawals = <String>{};
  for (final h in heads) {
    if (h['workshop_id'] != workshopId ||
        h['issuer_nif'] is! String ||
        !_nif.hasMatch(h['issuer_nif']) ||
        h['installation'] is! String ||
        _text(h['installation'], 'Instalación', 80) != h['installation'] ||
        h['restored'] is! bool ||
        !headKeys.add(chain(h))) {
      throw const RuleException('Cabecera de ensayo inválida');
    }
    _integer(h['last_sequence'], 'Secuencia', 0, 999999999);
    if (h['last_hash'] is! String ||
        (h['last_sequence'] == 0
            ? h['last_hash'] != ''
            : !_hash.hasMatch(h['last_hash']))) {
      throw const RuleException('Huella de cabecera inválida');
    }
  }
  for (final s in series) {
    if (s['workshop_id'] != workshopId ||
        !headKeys.contains(chain(s)) ||
        s['prefix'] is! String ||
        !_prefix.hasMatch(s['prefix']) ||
        !seriesKeys.add('${chain(s)}|${s['prefix']}')) {
      throw const RuleException('Serie de ensayo inválida');
    }
    _integer(s['last_number'], 'Número de ensayo', 0, 999999999);
  }
  for (final r in records) {
    if (r['workshop_id'] != workshopId ||
        !headKeys.contains(chain(r)) ||
        r['id'] is! String ||
        !_uuid.hasMatch(r['id']) ||
        !recordIds.add(r['id']) ||
        !{'draft', 'withdrawal'}.contains(r['kind']) ||
        r['body'] is! Map ||
        !seriesKeys.contains('${chain(r)}|${r['prefix']}') ||
        r['ledger_hash'] is! String ||
        !_hash.hasMatch(r['ledger_hash'])) {
      throw const RuleException('Original de ensayo inválido');
    }
    _integer(r['sequence'], 'Secuencia', 1, 999999999);
    _integer(r['number'], 'Número de ensayo', 1, 999999999);
    for (final field in ['actor_id', 'device_id']) {
      if (r[field] is! String || !_uuid.hasMatch(r[field])) {
        throw const RuleException('Autor o dispositivo de ensayo inválido');
      }
    }
    final b = Map<String, dynamic>.from(r['body']);
    if (b['draftFormat'] != 1 ||
        b['scope'] != 'sandbox' ||
        b['emissionEnabled'] != false ||
        b['transmissionEnabled'] != false ||
        b['id'] != r['id'] ||
        b['issuerNif'] != r['issuer_nif'] ||
        b['installation'] != r['installation'] ||
        b['sequence'] != r['sequence'] ||
        b['kind'] != r['kind'] ||
        b['prefix'] != r['prefix'] ||
        b['number'] != r['number'] ||
        b['actorId'] != r['actor_id'] ||
        b['deviceId'] != r['device_id'] ||
        b['createdAt'] is! String ||
        DateTime.tryParse(b['createdAt']) == null ||
        _text(b['reason'], 'Motivo') != b['reason']) {
      throw const RuleException('Contenido original de ensayo incoherente');
    }
    if (r['kind'] == 'draft') {
      if (r['target_id'] != null || b['calculation'] is! Map) {
        throw const RuleException('Cálculo de ensayo ausente');
      }
      final saved = Map<String, dynamic>.from(b['calculation']);
      final lines = fiscalDraftRows(saved['lines'])
          .map(
            (l) => cloneMap(l)
              ..remove('baseCents')
              ..remove('taxCents')
              ..remove('totalCents'),
          )
          .toList();
      final payload = normalizeFiscalDraftPayload('fiscal_draft_append', {
        'issuerNif': b['issuerNif'],
        'installation': b['installation'],
        'prefix': b['prefix'],
        'reason': b['reason'],
        'issueDate': b['issueDate'],
        'recipient': b['recipient'],
        'lines': lines,
      }, withExpectation: false);
      if (!fiscalDraftSame(
        saved,
        fiscalDraftCalculation(fiscalDraftRows(payload['lines'])),
      )) {
        throw const RuleException('Los importes guardados no coinciden');
      }
    } else {
      final originals = records
          .where(
            (o) =>
                o['id'] == r['target_id'] &&
                o['kind'] == 'draft' &&
                chain(o) == chain(r) &&
                (o['sequence'] as int) < (r['sequence'] as int),
          )
          .toList();
      if (originals.length != 1 ||
          !withdrawals.add(r['target_id']) ||
          b['targetId'] != r['target_id'] ||
          b['originalLedgerHash'] != originals.single['ledger_hash'] ||
          r['prefix'] != originals.single['prefix'] ||
          r['number'] != originals.single['number']) {
        throw const RuleException('Retirada de ensayo incoherente');
      }
    }
  }
  for (final h in heads) {
    final ordered = records.where((r) => chain(r) == chain(h)).toList()
      ..sort((a, b) => (a['sequence'] as int).compareTo(b['sequence']));
    var sequence = 0;
    var previous = '';
    for (final r in ordered) {
      if (r['sequence'] != ++sequence ||
          r['previous_hash'] != previous ||
          r['ledger_hash'] !=
              await fiscalDraftLedgerHash(
                Map<String, dynamic>.from(r['body']),
                previous,
              )) {
        throw const RuleException('Cadena de ensayo incompleta o alterada');
      }
      previous = r['ledger_hash'];
    }
    if (h['last_sequence'] != sequence || h['last_hash'] != previous) {
      throw const RuleException('La cabecera no corresponde a sus originales');
    }
  }
  for (final s in series) {
    final numbers =
        records
            .where(
              (r) =>
                  chain(r) == chain(s) &&
                  r['prefix'] == s['prefix'] &&
                  r['kind'] == 'draft',
            )
            .map((r) => r['number'] as int)
            .toList()
          ..sort();
    if (s['last_number'] != numbers.length ||
        numbers.indexed.any((n) => n.$2 != n.$1 + 1)) {
      throw const RuleException('Numeración de ensayo incompleta');
    }
  }
  return ledger;
}

bool fiscalDraftRecordMatchesCommand(
  Map<String, dynamic> record,
  Map<String, dynamic> command,
) {
  final p = Map<String, dynamic>.from(command['payload']),
      b = Map<String, dynamic>.from(record['body']);
  if (record['id'] != command['id'] ||
      record['actor_id'] != command['actorId'] ||
      record['device_id'] != command['deviceId'] ||
      b['issuerNif'] != p['issuerNif'] ||
      b['installation'] != p['installation'] ||
      b['reason'] != p['reason'] ||
      record['sequence'] != p['expectedSequence'] + 1 ||
      record['previous_hash'] != p['expectedHash']) {
    return false;
  }
  if (command['action'] == 'fiscal_draft_withdraw') {
    return record['kind'] == 'withdrawal' && b['targetId'] == p['targetId'];
  }
  return record['kind'] == 'draft' &&
      b['prefix'] == p['prefix'] &&
      b['issueDate'] == p['issueDate'] &&
      fiscalDraftSame(b['recipient'], p['recipient']) &&
      fiscalDraftSame(
        b['calculation'],
        fiscalDraftCalculation(fiscalDraftRows(p['lines'])),
      );
}
