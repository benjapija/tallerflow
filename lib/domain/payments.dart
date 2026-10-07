import 'engine.dart';
import 'management.dart';
import 'models.dart';

class PaymentBalance {
  final int totalCents, receivedCents, refundedCents;
  const PaymentBalance(this.totalCents, this.receivedCents, this.refundedCents);
  int get paidCents => receivedCents - refundedCents;
  int get outstandingCents => totalCents - paidCents;
  String get status => outstandingCents == 0
      ? 'paid'
      : paidCents == 0
      ? 'pending'
      : 'partial';
  factory PaymentBalance.forOrder(WorkOrder order) {
    final total = boundedInt(
      order.data['document']?['totalCents'],
      1000000000000,
      'Total de la nota',
    );
    var received = 0, refunded = 0;
    for (final row in paymentEntries(order)) {
      final amount = boundedInt(
        row['amountCents'],
        1000000000000,
        'Cobro',
        min: 1,
      );
      if (row['kind'] == 'receipt') {
        received += amount;
      } else if (row['kind'] == 'reversal') {
        refunded += amount;
      } else {
        throw const RuleException('Registro de cobro incompatible');
      }
    }
    if (refunded > received || received - refunded > total) {
      throw const RuleException('Revisa el saldo y sus registros');
    }
    return PaymentBalance(total, received, refunded);
  }
}

List<Map<String, dynamic>> paymentEntries(WorkOrder order) =>
    (order.data['payments'] as List? ?? []).cast<Map<String, dynamic>>();

int reversibleCents(WorkOrder order, String sourceId) {
  final rows = paymentEntries(order);
  final source = rows
      .where((r) => r['id'] == sourceId && r['kind'] == 'receipt')
      .firstOrNull;
  if (source == null) {
    throw const RuleException('Cobro original no encontrado');
  }
  return (source['amountCents'] as int) -
      rows
          .where((r) => r['kind'] == 'reversal' && r['sourceId'] == sourceId)
          .fold<int>(0, (sum, r) => sum + (r['amountCents'] as int));
}

// Accounting evidence of money already received/refunded. This never charges a
// card or changes the issued document. Corrections append a linked reversal.
void applyPayment(WorkOrder order, Actor actor, Operation op) {
  if (!actor.isOffice ||
      !actor.active ||
      op.actorId != actor.id ||
      op.orderId != order.id) {
    throw const RuleException('Se requiere una cuenta activa de oficina');
  }
  if (!order.issued) {
    throw const RuleException('Emite la nota antes de registrar el cobro');
  }
  if (op.baseRevision != order.revision) {
    throw const RuleException('El saldo cambió. Actualiza y revisa');
  }
  final p = op.payload;
  final reversal = op.kind == 'payment_reverse';
  final allowed = {
    'amountCents',
    'paidAt',
    'reference',
    'reason',
    if (reversal) 'sourceId' else 'method',
  };
  if (p.keys.any((k) => !allowed.contains(k))) {
    throw const RuleException('Campo de cobro no permitido');
  }
  final balance = PaymentBalance.forOrder(order);
  final amount = boundedInt(p['amountCents'], 1000000000000, 'Importe', min: 1);
  final reference = requiredText(
    p['reference'],
    'Justificante o referencia',
    max: 300,
  );
  final reason = requiredText(p['reason'], 'Motivo', max: 2000);
  final paidAt = p['paidAt'] is String ? DateTime.tryParse(p['paidAt']) : null;
  if (paidAt == null ||
      paidAt.isAfter(op.at) ||
      paidAt.isBefore(DateTime.parse(order.data['document']['issuedAt']))) {
    throw const RuleException(
      'Indica una fecha real desde la emisión de la nota',
    );
  }
  String method;
  String? sourceId;
  if (reversal) {
    sourceId = requiredText(p['sourceId'], 'Cobro original', max: 100);
    final source = paymentEntries(
      order,
    ).where((r) => r['id'] == sourceId && r['kind'] == 'receipt').firstOrNull;
    if (source == null || amount > reversibleCents(order, sourceId)) {
      throw const RuleException('La devolución supera el cobro disponible');
    }
    if (paidAt.isBefore(DateTime.parse(source['paidAt']))) {
      throw const RuleException('La devolución es anterior al cobro');
    }
    method = source['method'];
  } else {
    if (!['cash', 'card', 'transfer', 'other'].contains(p['method'])) {
      throw const RuleException('Selecciona el medio de cobro');
    }
    if (amount > balance.outstandingCents) {
      throw const RuleException('El cobro supera el saldo pendiente');
    }
    method = p['method'];
  }
  order.data['payments'] = [
    ...paymentEntries(order),
    {
      'id': op.id,
      'kind': reversal ? 'reversal' : 'receipt',
      'amountCents': amount,
      'currency': 'EUR',
      'method': method,
      'reference': reference,
      'reason': reason,
      'paidAt': paidAt.toUtc().toIso8601String(),
      'recordedAt': op.at.toUtc().toIso8601String(),
      'actorId': actor.id,
      'orderId': order.id,
      'ownerId': order.data['ownerId'],
      'documentRevision': order.data['document']['revision'],
      'sourceId': ?sourceId,
    },
  ];
}

void applyDelivery(WorkOrder order, Actor actor, Operation op) {
  if (!actor.isOffice || !actor.active) {
    throw const RuleException('Se requiere permiso de oficina');
  }
  if (!order.issued) {
    throw const RuleException('Revisa y emite la nota antes de entregar');
  }
  if (op.baseRevision != order.revision) {
    throw const RuleException(
      'La orden cambió. Revisa el saldo antes de entregar',
    );
  }
  if (order.status == OrderStatus.delivered) {
    throw const RuleException('La entrega original se conserva');
  }
  if (op.payload.keys.any((k) => k != 'reason')) {
    throw const RuleException('Campo de entrega no permitido');
  }
  final reason = requiredText(
    op.payload['reason'],
    'Motivo y autorización de entrega',
  );
  final balance = PaymentBalance.forOrder(order);
  order.data['status'] = 'delivered';
  order.data['delivery'] = {
    'reason': reason,
    'actorId': actor.id,
    'at': op.at.toUtc().toIso8601String(),
    'outstandingCents': balance.outstandingCents,
    'paymentStatus': balance.status,
    'creditAuthorized': balance.outstandingCents > 0,
  };
}
