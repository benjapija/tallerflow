import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../domain/models.dart';
import '../domain/purchases.dart';
import 'dialogs.dart';

class PurchasePanel extends StatelessWidget {
  final PurchaseLedger ledger;
  final List<CatalogItem> catalog;
  final List<WorkOrder> repairOrders;
  final bool canEdit;
  final bool pending;
  final Future<void> Function(String, Map<String, dynamic>) onSave;
  const PurchasePanel({
    super.key,
    required this.ledger,
    required this.catalog,
    required this.repairOrders,
    required this.canEdit,
    required this.pending,
    required this.onSave,
  });

  Future<void> create(BuildContext context) async {
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PurchaseDialog(
        catalog: catalog.where((c) => c.active).toList(),
        orders: repairOrders,
      ),
    );
    if (payload != null) await onSave('purchase_create', payload);
  }

  Future<void> movement(
    BuildContext context,
    Map<String, dynamic> purchase,
    Map<String, dynamic> line,
    bool returning,
  ) async {
    final payload = await formDialog(
      context,
      returning ? 'Devolver material al proveedor' : 'Recibir material',
      [
        const FieldSpec(
          'packages',
          'Número de envases',
          initial: '1',
          numeric: true,
        ),
        const FieldSpec('reference', 'Albarán o justificante'),
        const FieldSpec(
          'reason',
          'Motivo y comprobación física',
          multiline: true,
        ),
      ],
      (v) => {
        'purchaseId': purchase['id'],
        'lineId': line['id'],
        'packagesMilli': parseQuantity(v['packages']!),
        'reference': v['reference'],
        'reason': v['reason'],
      },
      help:
          '${line['description']} · Cada envase contiene ${quantity(line['packageSizeMilli'])} ${line['unit']}. '
          '${returning ? 'La devolución requiere material recibido y disponible sin reservas.' : 'Registra solo el material que ha llegado. Las recepciones pueden ser parciales.'}',
    );
    if (payload != null) {
      await onSave(returning ? 'supplier_return' : 'purchase_receive', payload);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Compras y recepciones',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      const Text(
        'Pedidos manuales al proveedor. Crear un pedido no aumenta las existencias; recibir o devolver material sí las modifica.',
      ),
      if (pending)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Hay registros pendientes. Sincroniza y revisa su resultado antes de continuar. Las existencias muestran los movimientos confirmados.',
          ),
        ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: canEdit && !pending && catalog.any((c) => c.active)
            ? () => create(context)
            : null,
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('Crear pedido al proveedor'),
      ),
      if (ledger.orders.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('Todavía no hay pedidos registrados.'),
        ),
      for (final purchase in ledger.orders.reversed)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${purchase['supplier']} · ${purchase['reference']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    'Previsto: ${DateTime.parse(purchase['expectedAt']).toLocal().toString().split(' ').first}',
                  ),
                  Text(purchase['reason']),
                  if (purchase['orderId'] != null)
                    Text(
                      'Reparación: ${repairOrders.where((o) => o.id == purchase['orderId']).firstOrNull?.number ?? purchase['orderId']}',
                    ),
                  for (final raw in purchase['lines'])
                    _line(context, purchase, Map<String, dynamic>.from(raw)),
                ],
              ),
            ),
          ),
        ),
    ],
  );

  Widget _line(
    BuildContext context,
    Map<String, dynamic> purchase,
    Map<String, dynamic> line,
  ) {
    final rows = ledger.movements
        .where(
          (m) => m['purchaseId'] == purchase['id'] && m['lineId'] == line['id'],
        )
        .toList();
    final received = rows
        .where((m) => m['kind'] == 'receive')
        .fold<int>(0, (s, m) => s + (m['quantityMilli'] as int));
    final returned = rows
        .where((m) => m['kind'] == 'supplier_return')
        .fold<int>(0, (s, m) => s + (m['quantityMilli'] as int));
    final remaining = (line['requestedMilli'] as int) - received;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 28),
        Text('${line['reference']} · ${line['description']}'),
        Text(
          '${quantity(line['requestedPackagesMilli'])} envases de ${quantity(line['packageSizeMilli'])} ${line['unit']} · Coste por ${line['unit']}: ${money(line['unitCostCents'])}',
        ),
        Text(
          'Solicitado: ${quantity(line['requestedMilli'])} · Recibido: ${quantity(received)} · Pendiente: ${quantity(remaining)} · Devuelto: ${quantity(returned)} ${line['unit']}',
        ),
        Wrap(
          spacing: 12,
          children: [
            TextButton.icon(
              onPressed: canEdit && !pending && remaining > 0
                  ? () => movement(context, purchase, line, false)
                  : null,
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Recibir'),
            ),
            TextButton.icon(
              onPressed: canEdit && !pending && received > returned
                  ? () => movement(context, purchase, line, true)
                  : null,
              icon: const Icon(Icons.assignment_return_outlined),
              label: const Text('Devolver al proveedor'),
            ),
          ],
        ),
        for (final row in rows.reversed)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${row['kind'] == 'receive' ? 'Recepción' : 'Devolución'} · ${quantity(row['quantityMilli'])} ${row['unit']} · ${money(row['costCents'])} · ${row['reference']}\n${row['reason']} · ${DateTime.parse(row['at']).toLocal()}',
            ),
          ),
      ],
    );
  }
}

class _PurchaseDialog extends StatefulWidget {
  final List<CatalogItem> catalog;
  final List<WorkOrder> orders;
  const _PurchaseDialog({required this.catalog, required this.orders});
  @override
  State<_PurchaseDialog> createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends State<_PurchaseDialog> {
  final form = GlobalKey<FormState>();
  final supplier = TextEditingController(),
      reference = TextEditingController(),
      reason = TextEditingController();
  final expected = TextEditingController(
    text: DateTime.now().toIso8601String().split('T').first,
  );
  final rows = <Map<String, String>>[];
  String orderId = '';
  String? error;
  @override
  void initState() {
    super.initState();
    addLine();
  }

  void addLine() {
    final item = widget.catalog.first;
    rows.add({
      'id': const Uuid().v4(),
      'itemId': item.id,
      'size': '1',
      'packages': '1',
      'cost':
          '${item.costCents ~/ 100},${(item.costCents % 100).toString().padLeft(2, '0')}',
    });
  }

  @override
  void dispose() {
    for (final c in [supplier, reference, reason, expected]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Pedido al proveedor'),
    content: SizedBox(
      width: 600,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Los costes son por unidad del catálogo, antes de impuestos. El pedido queda registrado aquí; debes enviarlo al proveedor por tu canal habitual.',
              ),
              for (final field in [
                (supplier, 'Proveedor'),
                (reference, 'Referencia del pedido'),
                (expected, 'Fecha prevista · AAAA-MM-DD'),
                (reason, 'Motivo'),
              ])
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextFormField(
                    controller: field.$1,
                    decoration: InputDecoration(labelText: field.$2),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Completa este campo' : null,
                  ),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: orderId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Reparación vinculada',
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Reposición general'),
                  ),
                  for (final o in widget.orders)
                    DropdownMenuItem(
                      value: o.id,
                      child: Text(
                        '${o.number} · ${o.plate}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => orderId = v ?? '',
              ),
              for (final row in rows)
                Padding(
                  key: ValueKey(row['id']),
                  padding: const EdgeInsets.only(top: 18),
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: row['itemId'],
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Artículo',
                        ),
                        items: widget.catalog
                            .map(
                              (i) => DropdownMenuItem(
                                value: i.id,
                                child: Text(
                                  '${i.reference} · ${i.description}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => row['itemId'] = v!),
                      ),
                      const SizedBox(height: 8),
                      for (final f in [
                        (
                          'size',
                          'Contenido por envase (${widget.catalog.firstWhere((i) => i.id == row['itemId']).unit})',
                        ),
                        ('packages', 'Envases solicitados'),
                        ('cost', 'Coste por unidad del catálogo (€)'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextFormField(
                            initialValue: row[f.$1],
                            decoration: InputDecoration(labelText: f.$2),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (v) => row[f.$1] = v,
                          ),
                        ),
                      if (rows.length > 1)
                        TextButton(
                          onPressed: () => setState(() => rows.remove(row)),
                          child: const Text('Quitar partida'),
                        ),
                    ],
                  ),
                ),
              TextButton.icon(
                onPressed: rows.length < 100 ? () => setState(addLine) : null,
                icon: const Icon(Icons.add),
                label: const Text('Añadir partida'),
              ),
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red)),
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
          try {
            final date = DateTime.tryParse(expected.text.trim());
            if (date == null) {
              throw const FormatException('Revisa la fecha prevista');
            }
            final lines = rows
                .map(
                  (r) => {
                    'id': r['id'],
                    'itemId': r['itemId'],
                    'packageSizeMilli': parseQuantity(r['size']!),
                    'packagesMilli': parseQuantity(r['packages']!),
                    'unitCostCents': parseMoney(r['cost']!),
                  },
                )
                .toList();
            Navigator.pop(context, <String, dynamic>{
              'id': const Uuid().v4(),
              'supplier': supplier.text.trim(),
              'reference': reference.text.trim(),
              'expectedAt': date.toUtc().toIso8601String(),
              'orderId': orderId.isEmpty ? null : orderId,
              'reason': reason.text.trim(),
              'lines': lines,
            });
          } catch (e) {
            setState(() => error = '$e');
          }
        },
        child: const Text('Guardar pedido'),
      ),
    ],
  );
}
