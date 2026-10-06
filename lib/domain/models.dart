import 'dart:convert';

enum Role { technician, office, admin }

enum OrderStatus {
  pending,
  diagnosis,
  authorization,
  parts,
  repair,
  finished,
  verified,
  delivered,
}

const statusLabels = [
  'Pendiente',
  'En diagnóstico',
  'Esperando autorización',
  'Esperando piezas',
  'En reparación',
  'Terminada',
  'Verificada',
  'Entregada',
];
const roleLabels = ['Operario', 'Oficina', 'Administrador'];
String normalizePlate(String input) =>
    input.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
int roundRatio(int numerator, int denominator) {
  if (denominator <= 0) throw ArgumentError('Divisor inválido');
  return numerator < 0
      ? -roundRatio(-numerator, denominator)
      : (numerator + denominator ~/ 2) ~/ denominator;
}

int roundProduct(int left, int right, int denominator) {
  if (denominator <= 0) throw ArgumentError('Divisor inválido');
  final numerator = BigInt.from(left) * BigInt.from(right);
  final divisor = BigInt.from(denominator);
  final value = (numerator.abs() + divisor ~/ BigInt.two) ~/ divisor;
  final signed = numerator.isNegative ? -value : value;
  if (signed.abs() > BigInt.from(9007199254740991)) {
    throw const FormatException('Importe fuera del intervalo admitido');
  }
  return signed.toInt();
}

int parseQuantity(String value) {
  final s = value.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(s)) {
    throw const FormatException('Usa una cantidad con hasta 3 decimales');
  }
  final p = s.split('.');
  final n =
      int.parse(p[0]) * 1000 +
      int.parse((p.length == 2 ? p[1] : '').padRight(3, '0'));
  if (n <= 0 || n > 100000000) {
    throw const FormatException(
      'La cantidad debe estar entre 0,001 y 100.000 unidades',
    );
  }
  return n;
}

String quantity(int milli) => (milli / 1000)
    .toStringAsFixed(3)
    .replaceFirst(RegExp(r'\.?0+$'), '')
    .replaceAll('.', ',');
String money(int cents) =>
    '${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')} €';
String hours(int seconds) =>
    '${(seconds / 3600).toStringAsFixed(2).replaceAll('.', ',')} h';
Map<String, dynamic> cloneMap(Map<String, dynamic> map) =>
    jsonDecode(jsonEncode(map)) as Map<String, dynamic>;

class Actor {
  final String id, name;
  final Role role;
  final bool seePrices, seeCosts, active;
  const Actor(
    this.id,
    this.name,
    this.role, {
    this.seePrices = false,
    this.seeCosts = false,
    this.active = true,
  });
  bool get isOffice => role != Role.technician;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'role': role.name,
    'seePrices': seePrices,
    'seeCosts': seeCosts,
    'active': active,
  };
  factory Actor.fromJson(Map<String, dynamic> j) => Actor(
    j['id'],
    j['name'],
    Role.values.byName(j['role']),
    seePrices: j['seePrices'] ?? false,
    seeCosts: j['seeCosts'] ?? false,
    active: j['active'] ?? true,
  );
}

class CatalogItem {
  final String id, reference, description, unit;
  final int priceCents, costCents, stockMilli, minMilli;
  final int? taxBps;
  final bool active, costKnown;
  final String supplier;
  const CatalogItem({
    required this.id,
    required this.reference,
    required this.description,
    required this.unit,
    required this.priceCents,
    required this.costCents,
    required this.stockMilli,
    this.minMilli = 2000,
    this.taxBps,
    this.active = true,
    this.costKnown = true,
    this.supplier = '',
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'reference': reference,
    'description': description,
    'unit': unit,
    'priceCents': priceCents,
    'costCents': costCents,
    'stockMilli': stockMilli,
    'minMilli': minMilli,
    'taxBps': taxBps,
    'active': active,
    'costKnown': costKnown,
    'supplier': supplier,
  };
  factory CatalogItem.fromJson(Map<String, dynamic> j) => CatalogItem(
    id: j['id'],
    reference: j['reference'],
    description: j['description'],
    unit: j['unit'],
    priceCents: j['priceCents'] ?? 0,
    costCents: j['costCents'] ?? 0,
    stockMilli: j['stockMilli'],
    minMilli: j['minMilli'],
    taxBps: j['taxBps'],
    active: j['active'] ?? true,
    costKnown: j['costKnown'] ?? false,
    supplier: j['supplier'] ?? '',
  );
}

class WorkOrder {
  final Map<String, dynamic> data;
  WorkOrder(this.data);
  String get id => data['id'];
  String get number => data['number'];
  String get plate => data['plate'];
  String get vehicle => data['vehicle'];
  String get client => data['client'];
  String get symptom => data['symptom'];
  int get revision => data['revision'] ?? 0;
  OrderStatus get status => OrderStatus.values.byName(data['status']);
  List<Map<String, dynamic>> get tasks =>
      (data['tasks'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get times =>
      (data['times'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get parts =>
      (data['parts'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get notes =>
      (data['notes'] as List).cast<Map<String, dynamic>>();
  bool get issued => data['document'] != null;
  bool get verified => data['quality'] != null;
  bool assigned(String actor) =>
      tasks.any((t) => (t['assignees'] as List).contains(actor));
  int workedSeconds(DateTime now) => times.fold(
    0,
    (total, t) =>
        total +
        ((t['end'] == null ? now : DateTime.parse(t['end']))
            .difference(DateTime.parse(t['start']))
            .inSeconds),
  );
  int get billableMinutes =>
      tasks.fold(0, (total, t) => total + (t['billableMinutes'] as int));
  int get estimatedMinutes =>
      tasks.fold(0, (total, t) => total + (t['estimateMinutes'] as int));
}

class NoteTotal {
  final int netCents, taxCents;
  final List<Map<String, dynamic>> lines;
  const NoteTotal(this.netCents, this.taxCents, this.lines);
  int get totalCents => netCents + taxCents;
  Map<String, dynamic> toJson() => {
    'netCents': netCents,
    'taxCents': taxCents,
    'totalCents': totalCents,
    'lines': lines,
    'type': 'Nota de trabajo · no es una factura',
  };
}

NoteTotal calculateNote(WorkOrder order) {
  final lines = <Map<String, dynamic>>[];
  for (final t in order.tasks.where(
    (t) => t['authorized'] == true && t['billableMinutes'] > 0,
  )) {
    final gross = roundProduct(
      t['billableMinutes'] as int,
      (t['rateCents'] ?? 0) as int,
      60,
    );
    final discount = roundProduct(gross, (t['discountBps'] ?? 0) as int, 10000);
    final net = gross - discount;
    lines.add({
      'description': t['title'],
      'quantity': '${t['billableMinutes']} min',
      'netCents': net,
      'unitPriceCents': t['rateCents'],
      'taxBps': t['taxBps'],
      'grossCents': gross,
      'discountBps': t['discountBps'] ?? 0,
      'discountCents': discount,
      'taxCents': roundProduct(net, t['taxBps'] as int, 10000),
      'taskId': t['id'],
    });
  }
  for (final p in order.parts.where((p) => p['kind'] == 'consume')) {
    final q = remainingConsumption(order, p);
    if (q <= 0) continue;
    final gross = roundProduct(q, p['priceCents'] as int, 1000);
    final discount = p['charge'] == true
        ? roundProduct(gross, (p['discountBps'] ?? 0) as int, 10000)
        : gross;
    final net = gross - discount;
    lines.add({
      'description': p['description'],
      'quantity': '${quantity(q)} ${p['unit']}',
      'netCents': net,
      'unitPriceCents': p['priceCents'],
      'taxBps': p['taxBps'],
      'grossCents': gross,
      'discountBps': p['charge'] == true ? p['discountBps'] ?? 0 : 10000,
      'discountCents': discount,
      'charge': p['charge'] == true,
      'noChargeReason': p['noChargeReason'],
      'partId': p['id'],
      'taxCents': roundProduct(net, p['taxBps'] as int, 10000),
      'taskId': p['taskId'],
    });
  }
  return NoteTotal(
    lines.fold(0, (s, l) => s + (l['netCents'] as int)),
    lines.fold(0, (s, l) => s + (l['taxCents'] as int)),
    lines,
  );
}

int remainingConsumption(WorkOrder order, Map<String, dynamic> part) =>
    (part['quantityMilli'] as int) -
    order.parts
        .where((r) => r['kind'] == 'return' && r['sourceId'] == part['id'])
        .fold<int>(0, (sum, r) => sum + (r['quantityMilli'] as int));

List<String> closeIssues(
  WorkOrder order, {
  required int pending,
  required bool connected,
  required bool conflict,
}) {
  final issues = <String>[];
  if (order.data['block'] != null ||
      order.tasks.any((t) => t['block'] != null && t['cancelled'] != true)) {
    issues.add('Resuelve los bloqueos del trabajo');
  }
  if (!connected) {
    issues.add('Conecta y reconcilia los dispositivos antes del cierre');
  }
  if (pending > 0) {
    issues.add('$pending registros pendientes de sincronización');
  }
  if (conflict) issues.add('Hay conflictos que requieren revisión');
  if (order.times.any((t) => t['end'] == null)) {
    issues.add('Hay un cronómetro activo');
  }
  if (order.tasks.any((t) => t['authorized'] == true && t['done'] != true)) {
    issues.add('Hay tareas autorizadas incompletas');
  }
  if (order.tasks.any(
    (t) => t['authorized'] != true && (t['billableMinutes'] as int) > 0,
  )) {
    issues.add('Hay mano de obra sin autorización');
  }
  if (order.parts.any((p) => p['kind'] == 'consume' && p['reviewed'] != true)) {
    issues.add('Hay consumos pendientes de revisión');
  }
  if (order.parts.any(
    (p) =>
        p['kind'] == 'consume' &&
        p['charge'] != true &&
        (p['noChargeReason'] as String? ?? '').trim().isEmpty,
  )) {
    issues.add('Justifica los consumos sin cobro');
  }
  if (order.tasks.any(
    (t) =>
        t['authorized'] == true &&
        (t['billableMinutes'] as int) > 0 &&
        ((t['rateCents'] ?? 0) as int) <= 0,
  )) {
    issues.add('Hay líneas sin precio');
  }
  for (final t in order.tasks.where((t) => t['authorized'] == true)) {
    final subtotal = calculateNote(order).lines
        .where((l) => l['taskId'] == t['id'])
        .fold<int>(
          0,
          (s, l) => s + (l['netCents'] as int) + (l['taxCents'] as int),
        );
    if (subtotal > ((t['approvedCents'] ?? 0) as int)) {
      issues.add('El importe de «${t['title']}» supera lo autorizado');
    }
  }
  if (!order.verified) issues.add('Falta la comprobación final del técnico');
  return issues;
}
