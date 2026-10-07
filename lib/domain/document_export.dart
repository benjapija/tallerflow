import 'engine.dart';
import 'management.dart';
import 'models.dart';

/// A copy of customer-visible values. Internal costs and payment evidence are
/// deliberately absent; exporting never recalculates or changes a document.
class DocumentExport {
  final String kind, title, reference, customer, vehicle;
  final DateTime date;
  final DateTime? validUntil;
  final List<Map<String, dynamic>> rows;
  final int netCents, taxCents, totalCents;
  final String? exception;
  DocumentExport._({
    required this.kind,
    required this.title,
    required this.reference,
    required this.customer,
    required this.vehicle,
    required this.date,
    this.validUntil,
    required this.rows,
    required this.netCents,
    required this.taxCents,
    required this.totalCents,
    this.exception,
  });

  factory DocumentExport.note(WorkOrder order, Actor actor) {
    _office(actor);
    if (!order.issued) {
      throw const RuleException('Emite la nota antes de exportar');
    }
    final d = cloneMap(order.data['document']);
    final rows = [
      for (final l in (d['lines'] as List)) _row(Map<String, dynamic>.from(l)),
    ];
    final net = rows.fold<int>(0, (s, r) => s + (r['netCents'] as int));
    final tax = rows.fold<int>(0, (s, r) => s + (r['taxCents'] as int));
    if (net != d['netCents'] ||
        tax != d['taxCents'] ||
        net + tax != d['totalCents']) {
      throw const RuleException(
        'La nota guardada contiene importes incoherentes',
      );
    }
    return DocumentExport._(
      kind: 'Nota de trabajo',
      title: 'Nota de trabajo',
      reference: '${order.number} · revisión ${d['revision']}',
      customer: requiredText(
        d['clientSnapshot'],
        'Destinatario original',
        max: 300,
      ),
      vehicle: d['plateSnapshot'] ?? '',
      date: DateTime.parse(d['issuedAt']),
      rows: rows,
      netCents: _cents(d['netCents']),
      taxCents: _cents(d['taxCents']),
      totalCents: _cents(d['totalCents']),
      exception: d['closureException'],
    );
  }

  factory DocumentExport.quote(Map<String, dynamic> version, Actor actor) {
    _office(actor);
    final q = cloneMap(version), rows = <Map<String, dynamic>>[];
    for (final line in q['lines'] as List) {
      for (final raw in line['components'] as List) {
        final c = Map<String, dynamic>.from(raw);
        rows.add(
          _row({
            ...c,
            'description': '${line['description']} / ${c['description']}',
            'quantity': c['kind'] == 'labor'
                ? '${c['minutes']} min'
                : '${quantity(c['quantityMilli'])} ${c['unit']}',
          }),
        );
      }
    }
    final net = rows.fold<int>(0, (s, r) => s + (r['netCents'] as int)),
        tax = rows.fold<int>(0, (s, r) => s + (r['taxCents'] as int));
    if (net + tax != _cents(q['totalCents'])) {
      throw const RuleException(
        'El presupuesto guardado tiene importes incompatibles',
      );
    }
    return DocumentExport._(
      kind: 'Presupuesto',
      title: requiredText(q['title'], 'Título', max: 300),
      reference:
          '${q['orderId']} · presupuesto ${q['id']} · versión ${q['version']}',
      customer: requiredText(q['customer'], 'Destinatario original', max: 300),
      vehicle: q['plateSnapshot'] ?? '',
      date: DateTime.parse(q['at']),
      validUntil: DateTime.parse(q['validUntil']),
      rows: rows,
      netCents: net,
      taxCents: tax,
      totalCents: net + tax,
    );
  }
  static void _office(Actor a) {
    if (!a.active || !a.isOffice) {
      throw const RuleException('Se requiere una cuenta activa de oficina');
    }
  }

  static int _cents(dynamic v) => boundedInt(v, 1000000000000, 'Importe');
  static Map<String, dynamic> _row(Map<String, dynamic> r) {
    final net = _cents(r['netCents']), tax = _cents(r['taxCents']);
    final total = _cents(r['totalCents'] ?? net + tax);
    if (total != net + tax) {
      throw const RuleException(
        'La partida guardada contiene importes incoherentes',
      );
    }
    return {
      'description': requiredText(r['description'], 'Descripción', max: 4000),
      'quantity': '${r['quantity'] ?? ''}',
      'netCents': net,
      'taxCents': tax,
      'totalCents': total,
      if (r['charge'] == false) 'noChargeReason': r['noChargeReason'],
      'discountCents': _cents(r['discountCents'] ?? 0),
    };
  }
}
