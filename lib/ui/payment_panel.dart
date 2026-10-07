import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../domain/payments.dart';
import 'dialogs.dart';

const paymentMethods = {
  'cash': 'Efectivo',
  'card': 'Tarjeta',
  'transfer': 'Transferencia',
  'other': 'Otro',
};

class PaymentPanel extends StatelessWidget {
  final WorkOrder order;
  final bool canEdit;
  final Future<void> Function(String, Map<String, dynamic>) onSave;
  const PaymentPanel({
    super.key,
    required this.order,
    required this.canEdit,
    required this.onSave,
  });

  Future<void> record(
    BuildContext context, [
    Map<String, dynamic>? source,
  ]) async {
    final balance = PaymentBalance.forOrder(order);
    final available = source == null
        ? balance.outstandingCents
        : reversibleCents(order, source['id']);
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _PaymentDialog(available: available, source: source),
    );
    if (payload != null) {
      await onSave(
        source == null ? 'payment_record' : 'payment_reverse',
        payload,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = PaymentBalance.forOrder(order);
    final rows = paymentEntries(order);
    final delivery = order.data['delivery'] as Map<String, dynamic>?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cobros y saldo',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                Text('Nota: ${money(balance.totalCents)}'),
                Text('Cobrado neto: ${money(balance.paidCents)}'),
                Text('Pendiente: ${money(balance.outstandingCents)}'),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Registra dinero ya recibido o devuelto. Anotar una tarjeta no realiza un cargo bancario.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: canEdit && balance.outstandingCents > 0
                  ? () => record(context)
                  : null,
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Registrar cobro recibido'),
            ),
            for (final row in rows.reversed) ...[
              const Divider(),
              Text(
                '${row['kind'] == 'reversal' ? 'Devolución' : 'Cobro'} · ${money(row['amountCents'])} · ${paymentMethods[row['method']] ?? row['method']}',
              ),
              Text('${row['reference']} · ${row['reason']}'),
              Text('Fecha: ${DateTime.parse(row['paidAt']).toLocal()}'),
              if (row['kind'] == 'receipt' &&
                  reversibleCents(order, row['id']) > 0)
                TextButton.icon(
                  onPressed: canEdit ? () => record(context, row) : null,
                  icon: const Icon(Icons.undo),
                  label: const Text('Registrar devolución de este cobro'),
                ),
            ],
            if (delivery != null) ...[
              const Divider(),
              Text(
                'Entrega registrada · Pendiente entonces: ${money(delivery['outstandingCents'])}',
              ),
              Text(delivery['reason']),
            ],
          ],
        ),
      ),
    );
  }
}

class _PaymentDialog extends StatefulWidget {
  final int available;
  final Map<String, dynamic>? source;
  const _PaymentDialog({required this.available, this.source});
  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final form = GlobalKey<FormState>();
  late final amount = TextEditingController(
    text:
        '${widget.available ~/ 100},${(widget.available % 100).toString().padLeft(2, '0')}',
  );
  final date = TextEditingController(
    text: DateTime.now().toIso8601String().replaceFirst('T', ' '),
  );
  final reference = TextEditingController();
  final reason = TextEditingController();
  String method = 'cash';
  @override
  void dispose() {
    amount.dispose();
    date.dispose();
    reference.dispose();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.source == null ? 'Cobro ya recibido' : 'Devolución ya realizada',
    ),
    content: SizedBox(
      width: 480,
      child: Form(
        key: form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Máximo disponible: ${money(widget.available)}'),
              TextFormField(
                controller: amount,
                decoration: const InputDecoration(labelText: 'Importe (€)'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) {
                  try {
                    final cents = parseMoney(v ?? '');
                    if (cents > 0 && cents <= widget.available) return null;
                  } catch (_) {}
                  return 'Indica un importe dentro del saldo disponible';
                },
              ),
              if (widget.source == null)
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: const InputDecoration(
                    labelText: 'Medio de cobro',
                  ),
                  items: paymentMethods.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => method = v!),
                ),
              TextFormField(
                controller: date,
                decoration: const InputDecoration(
                  labelText: 'Fecha local',
                  helperText: 'AAAA-MM-DD HH:MM:SS',
                ),
                validator: (v) =>
                    DateTime.tryParse((v ?? '').replaceFirst(' ', 'T')) == null
                    ? 'Revisa la fecha'
                    : null,
              ),
              TextFormField(
                controller: reference,
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: 'Justificante o referencia',
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Indica una referencia' : null,
              ),
              TextFormField(
                controller: reason,
                maxLength: 2000,
                decoration: const InputDecoration(labelText: 'Motivo'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Indica el motivo' : null,
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate()) return;
          Navigator.pop(context, <String, dynamic>{
            'amountCents': parseMoney(amount.text),
            'paidAt': DateTime.parse(
              date.text.replaceFirst(' ', 'T'),
            ).toUtc().toIso8601String(),
            'reference': reference.text.trim(),
            'reason': reason.text.trim(),
            if (widget.source == null)
              'method': method
            else
              'sourceId': widget.source!['id'],
          });
        },
        child: const Text('Guardar registro'),
      ),
    ],
  );
}
