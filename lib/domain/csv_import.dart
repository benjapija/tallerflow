import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import 'engine.dart';
import 'models.dart';
import 'vehicles.dart';

enum ImportKind { clients, vehicles, catalog }

const importHeaders = {
  ImportKind.clients: [
    'codigo',
    'nombre',
    'telefono',
    'email',
    'nif',
    'direccion',
  ],
  ImportKind.vehicles: [
    'matricula',
    'pais',
    'vin',
    'vehiculo',
    'motor',
    'km',
    'codigo_cliente',
  ],
  ImportKind.catalog: [
    'referencia',
    'descripcion',
    'unidad',
    'precio',
    'coste',
    'iva_porcentaje',
    'existencias',
    'stock_minimo',
    'proveedor',
  ],
};
String importTemplate(ImportKind kind) =>
    '${importHeaders[kind]!.join(';')}\r\n';

class CsvRecord {
  final int line;
  final List<String> cells;
  CsvRecord(this.line, this.cells);
}

List<CsvRecord> readCsv(Uint8List bytes) {
  if (bytes.length > 1048576) {
    throw const FormatException('El CSV admite hasta 1 MB');
  }
  var input = utf8.decode(bytes);
  if (input.startsWith('\uFEFF')) input = input.substring(1);
  var quoted = false;
  int commas = 0, semicolons = 0;
  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (c == '"') {
      if (quoted && i + 1 < input.length && input[i + 1] == '"') {
        i++;
        continue;
      }
      quoted = !quoted;
    }
    if (!quoted) {
      if (c == '\n' || c == '\r') break;
      if (c == ',') commas++;
      if (c == ';') semicolons++;
    }
  }
  final delimiter = semicolons > commas ? ';' : ',';
  final records = <CsvRecord>[], cells = <String>[];
  var cell = StringBuffer();
  quoted = false;
  var closed = false;
  int line = 1, start = 1;
  void field() {
    if (cell.length > 2000) {
      throw FormatException('Campo demasiado largo en la fila $start');
    }
    cells.add(cell.toString());
    cell = StringBuffer();
    closed = false;
    if (cells.length > 30) throw const FormatException('Demasiadas columnas');
  }

  void record() {
    field();
    if (cells.any((v) => v.trim().isNotEmpty)) {
      records.add(CsvRecord(start, List.of(cells)));
    }
    cells.clear();
    if (records.length > 501) {
      throw const FormatException('Importa hasta 500 filas por archivo');
    }
  }

  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < input.length && input[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
          closed = true;
        }
      } else {
        cell.write(c);
        if (c == '\n') line++;
      }
      continue;
    }
    if (c == delimiter) {
      field();
      continue;
    }
    if (c == '\r' || c == '\n') {
      record();
      if (c == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
      line++;
      start = line;
      continue;
    }
    if (c == '"') {
      if (cell.isNotEmpty || closed) {
        throw FormatException('Comillas incorrectas en la fila $start');
      }
      quoted = true;
      continue;
    }
    if (closed) {
      throw FormatException(
        'Contenido después de las comillas en la fila $start',
      );
    }
    cell.write(c);
  }
  if (quoted) {
    throw FormatException('Faltan comillas de cierre en la fila $start');
  }
  if (cell.isNotEmpty || cells.isNotEmpty || closed) record();
  if (records.isEmpty) throw const FormatException('El archivo está vacío');
  return records;
}

int decimalValue(
  String raw,
  int digits,
  int maximum,
  String label, {
  bool blank = false,
}) {
  final value = raw.trim().replaceAll(',', '.');
  if (value.isEmpty && blank) return 0;
  if (!(digits == 0
          ? RegExp(r'^[0-9]+$')
          : RegExp('^[0-9]+(?:\\.[0-9]{1,$digits})?\$'))
      .hasMatch(value)) {
    throw FormatException(
      'Revisa $label: usa hasta $digits decimales, sin separadores de miles',
    );
  }
  final parts = value.split('.');
  final n =
      BigInt.parse(parts[0]) * BigInt.from(10).pow(digits) +
      BigInt.parse(
        digits == 0
            ? '0'
            : (parts.length == 2 ? parts[1] : '').padRight(digits, '0'),
      );
  if (n > BigInt.from(maximum)) {
    throw FormatException('$label supera el máximo admitido');
  }
  return n.toInt();
}

class ImportRow {
  final String id;
  final int line;
  final Map<String, dynamic>? data;
  final String status, message;
  ImportRow(this.id, this.line, this.data, this.status, this.message);
  Map<String, dynamic> toJson() => {'id': id, 'line': line, 'data': data};
}

class ImportPreview {
  final String id;
  final ImportKind kind;
  final List<ImportRow> rows;
  ImportPreview(this.id, this.kind, this.rows);
  int get ready => rows.where((r) => r.status == 'ready').length;
  Map<String, dynamic> payload(String reason) => {
    'kind': kind.name,
    'reason': reason,
    'rows': rows.where((r) => r.data != null).map((r) => r.toJson()).toList(),
  };
}

ImportPreview previewCsv(
  Uint8List bytes,
  ImportKind kind,
  WorkshopState state,
  Actor actor,
) {
  if (!actor.isOffice ||
      (kind == ImportKind.catalog && actor.role != Role.admin)) {
    throw const RuleException('Tu perfil no permite esta importación');
  }
  final records = readCsv(bytes),
      headers = records.first.cells.map((s) => s.trim().toLowerCase()).toList();
  final expected = importHeaders[kind]!;
  if (headers.toSet().length != headers.length ||
      headers.any((h) => !expected.contains(h)) ||
      expected.any((h) => !headers.contains(h))) {
    throw FormatException(
      'Usa las columnas de la plantilla: ${expected.join(', ')}',
    );
  }
  final result = <ImportRow>[], seen = <String>{};
  final clients = (state.configuration['clients'] as List? ?? [])
      .cast<Map<String, dynamic>>();
  for (final record in records.skip(1)) {
    final id = const Uuid().v4();
    Map<String, dynamic>? data;
    try {
      if (record.cells.length != headers.length) {
        throw const FormatException('El número de columnas no coincide');
      }
      final row = {
        for (var i = 0; i < headers.length; i++)
          headers[i]: record.cells[i].trim(),
      };
      String text(String key, int maximum, {bool optional = false}) {
        final v = row[key]!;
        if ((!optional && v.isEmpty) || v.length > maximum) {
          throw FormatException('Revisa $key');
        }
        return v;
      }

      String key;
      bool duplicate = false;
      switch (kind) {
        case ImportKind.clients:
          key = text('codigo', 120).toUpperCase();
          final email = text('email', 254, optional: true).toLowerCase();
          if (email.isNotEmpty &&
              !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
            throw const FormatException('Revisa email');
          }
          data = {
            'code': key,
            'name': text('nombre', 120),
            'phone': text('telefono', 100, optional: true),
            'email': email,
            'taxId': text('nif', 30, optional: true).toUpperCase(),
            'address': text('direccion', 1000, optional: true),
          };
          duplicate = clients.any(
            (c) =>
                c['code'] == key ||
                (data!['taxId'] != '' && c['taxId'] == data['taxId']),
          );
        case ImportKind.vehicles:
          final plate = normalizePlate(text('matricula', 20)),
              country = text('pais', 2).toUpperCase(),
              vin = text('vin', 50, optional: true).toUpperCase();
          if (!RegExp(r'^[A-Z]{2}$').hasMatch(country) ||
              !RegExp(r'^[A-Z0-9]{2,20}$').hasMatch(plate)) {
            throw const FormatException('Revisa matrícula y país');
          }
          key = '$country/$plate';
          data = {
            'plate': plate,
            'country': country,
            'vin': vin,
            'vehicle': text('vehiculo', 200),
            'engine': text('motor', 200, optional: true),
            'km': decimalValue(text('km', 12), 0, 10000000, 'kilometraje'),
            'clientCode': text('codigo_cliente', 120).toUpperCase(),
          };
          if (!clients.any((c) => c['code'] == data!['clientCode'])) {
            throw const FormatException('Importa primero el código de cliente');
          }
          duplicate = vehicleProfiles(state).any(
            (v) => (v['identifiers'] as List).any(
              (i) =>
                  (i['kind'] == 'plate' &&
                      i['country'] == country &&
                      i['value'] == plate) ||
                  (i['kind'] == 'vin' && vin.isNotEmpty && i['value'] == vin),
            ),
          );
        case ImportKind.catalog:
          key = text('referencia', 120).toUpperCase();
          data = {
            'reference': key,
            'description': text('descripcion', 300),
            'unit': text('unidad', 20),
            'priceCents': decimalValue(row['precio']!, 2, 10000000, 'precio'),
            'costCents': decimalValue(
              row['coste']!,
              2,
              10000000,
              'coste',
              blank: true,
            ),
            'costKnown': row['coste']!.isNotEmpty,
            'taxBps': decimalValue(row['iva_porcentaje']!, 2, 10000, 'IVA'),
            'stockMilli': decimalValue(
              row['existencias']!,
              3,
              100000000,
              'existencias',
            ),
            'minMilli': decimalValue(
              row['stock_minimo']!,
              3,
              100000000,
              'stock mínimo',
            ),
            'supplier': text('proveedor', 200, optional: true),
          };
          duplicate = state.catalog.any(
            (c) => c.reference.toUpperCase() == key,
          );
      }
      final keys = <String>[
        key,
        if (kind == ImportKind.clients && data['taxId'] != '')
          'tax/${data['taxId']}',
        if (kind == ImportKind.vehicles && data['vin'] != '')
          'vin/${data['vin']}',
      ];
      if (keys.any(seen.contains)) duplicate = true;
      if (!duplicate) seen.addAll(keys);
      result.add(
        ImportRow(
          id,
          record.line,
          data,
          duplicate ? 'duplicate' : 'ready',
          duplicate
              ? 'Duplicado: se conserva el registro existente'
              : 'Listo para importar',
        ),
      );
    } on FormatException catch (e) {
      result.add(ImportRow(id, record.line, null, 'error', e.message));
    }
  }
  if (result.isEmpty) {
    throw const FormatException('Añade filas debajo de la cabecera');
  }
  return ImportPreview(const Uuid().v4(), kind, result);
}

/// Fictional local demonstration. The hosted implementation validates again in SQL.
Map<String, dynamic> applyDemoImport(
  WorkshopState state,
  String batch,
  Map<String, dynamic> p,
  Actor actor,
  DateTime at, {
  bool writing = true,
}) {
  final kind = ImportKind.values.byName(p['kind']);
  if (!actor.isOffice ||
      (kind == ImportKind.catalog && actor.role != Role.admin)) {
    throw const RuleException('Tu perfil no permite esta importación');
  }
  final results = <Map<String, dynamic>>[], seenKeys = <String>{};
  var created = 0;
  final clients = (state.configuration['clients'] as List? ?? [])
      .map((v) => Map<String, dynamic>.from(v))
      .toList();
  for (final r in p['rows']) {
    final d = Map<String, dynamic>.from(r['data']);
    final id = r['id'];
    var duplicate = false;
    try {
      switch (kind) {
        case ImportKind.clients:
          duplicate = clients.any(
            (c) =>
                c['code'] == d['code'] ||
                (d['taxId'] != '' && c['taxId'] == d['taxId']),
          );
          if (!duplicate) {
            clients.add({...d, 'id': id, 'active': true});
            if (writing) state.configuration['clients'] = clients;
          }
        case ImportKind.vehicles:
          final owner = clients
              .where((c) => c['code'] == d['clientCode'])
              .firstOrNull;
          if (owner == null) {
            throw const RuleException('Importa primero el código de cliente');
          }
          final profiles = vehicleProfiles(state);
          duplicate = profiles.any(
            (v) => (v['identifiers'] as List).any(
              (i) =>
                  (i['kind'] == 'plate' &&
                      i['country'] == d['country'] &&
                      i['value'] == d['plate']) ||
                  (i['kind'] == 'vin' &&
                      d['vin'] != '' &&
                      i['value'] == d['vin']),
            ),
          );
          if (writing && !duplicate) {
            profiles.add({
              ...d,
              'id': id,
              'revision': 0,
              'ownerId': owner['id'],
              'owner': {'name': owner['name'], 'phone': owner['phone']},
              'identifiers': [
                {'kind': 'plate', 'country': d['country'], 'value': d['plate']},
                if (d['vin'] != '')
                  {'kind': 'vin', 'country': '', 'value': d['vin']},
              ],
            });
            state.configuration['vehicleProfiles'] = profiles;
          }
        case ImportKind.catalog:
          duplicate = state.catalog.any(
            (c) => c.reference.toUpperCase() == d['reference'],
          );
          if (writing && !duplicate) {
            state.catalog.add(
              CatalogItem.fromJson({...d, 'id': id, 'active': true}),
            );
          }
      }
      if (!writing) {
        final keys = switch (kind) {
          ImportKind.clients => [
            'code/${d['code']}',
            if (d['taxId'] != '') 'tax/${d['taxId']}',
          ],
          ImportKind.vehicles => [
            'plate/${d['country']}/${d['plate']}',
            if (d['vin'] != '') 'vin/${d['vin']}',
          ],
          ImportKind.catalog => ['reference/${d['reference']}'],
        };
        if (keys.any(seenKeys.contains)) duplicate = true;
        if (!duplicate) seenKeys.addAll(keys);
      }
      final status = duplicate
          ? 'duplicate'
          : writing
          ? 'created'
          : 'ready';
      results.add({
        'id': id,
        'line': r['line'],
        'status': status,
        'message': duplicate
            ? 'Duplicado: se conserva el registro existente'
            : writing
            ? 'Importado'
            : 'Listo para importar',
      });
      if (writing && !duplicate) {
        created++;
        state.audit.add({
          'id': id,
          'actor': actor.name,
          'kind': 'csv_row_imported',
          'at': at.toUtc().toIso8601String(),
          'after': d,
          'reason': p['reason'],
          'batchId': batch,
        });
      }
    } on RuleException catch (e) {
      results.add({
        'id': id,
        'line': r['line'],
        'status': 'error',
        'message': e.message,
      });
    }
  }
  if (writing) {
    if (kind == ImportKind.catalog && created > 0) {
      state.configuration['managementRevision'] = state.managementRevision + 1;
    }
    state.audit.add({
      'id': batch,
      'actor': actor.name,
      'kind': 'csv_import',
      'at': at.toUtc().toIso8601String(),
      'reason': p['reason'],
      'created': created,
    });
  }
  return {
    'batchId': batch,
    'kind': kind.name,
    'rows': results,
    'created': created,
  };
}
