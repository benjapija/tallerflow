import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../domain/pricing.dart';
import 'dialogs.dart';

class PricingPanel extends StatelessWidget {
  final WorkOrder order;
  final bool canEdit, showPrices, showCosts;
  final Map<String, dynamic> settings;
  final List<Actor> members;
  final Future<void> Function(Map<String, dynamic>) onReview;
  const PricingPanel({
    super.key,
    required this.order,
    required this.canEdit,
    required this.showPrices,
    required this.showCosts,
    required this.settings,
    required this.members,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showPrices)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Precios y descuentos'),
              subtitle: const Text('Revisión de oficina con motivo'),
              children: [
                for (final t in order.tasks.where(
                  (t) => t['cancelled'] != true,
                ))
                  line(context, t, true),
                for (final p in order.parts.where(
                  (p) => p['kind'] == 'consume',
                ))
                  line(context, p, false),
                if (canEdit && !order.issued)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Subir el precio o el impuesto, reducir el descuento o volver a cobrar requiere una nueva autorización del cliente.',
                    ),
                  ),
                if (canEdit)
                  for (final r
                      in (order.data['pricingReviews'] as List? ?? []).reversed)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(r['reason']),
                      subtitle: Text(
                        '${members.where((m) => m.id == r['actorId']).firstOrNull?.name ?? 'Usuario'} · ${r['at'].toString().substring(0, 16)} UTC\n${r['requiresAuthorization'] == true ? 'Requiere nueva autorización' : 'Revisión registrada'}',
                      ),
                    ),
              ],
            ),
          if (showCosts) margin(),
        ],
      ),
    ),
  );

  Widget line(BuildContext context, Map<String, dynamic> entry, bool labor) {
    final price = (entry[labor ? 'rateCents' : 'priceCents'] ?? 0) as int;
    final charged = labor || entry['charge'] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            entry[labor ? 'title' : 'description'],
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            '${money(price)} / ${labor ? 'hora' : entry['unit']} · IVA ${percent(entry['taxBps'] ?? 2100)} · descuento ${percent(entry['discountBps'] ?? 0)}',
          ),
          if (!charged)
            Text(
              'Sin cobro · ${entry['noChargeReason'] ?? 'Justificación pendiente'}',
            ),
          if (canEdit && !order.issued)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () async {
                  final p = await pricingDialog(context, entry, labor);
                  if (p != null) await onReview(p);
                },
                child: Text(
                  labor
                      ? 'Revisar tarifa y descuento'
                      : 'Revisar precio y cobro',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget margin() {
    final e = estimateMargin(
      order,
      settings,
      DateTime.now(),
      includeRevenue: showPrices,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Costes y margen estimado',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (showPrices)
            Text('Importe previsto sin impuestos: ${money(e.revenueCents)}'),
          Text('Piezas con coste conocido: ${money(e.materialCostCents)}'),
          Text(
            'Tiempo trabajado con coste conocido: ${money(e.laborCostCents)}',
          ),
          if (showPrices && e.marginCents != null)
            Text(
              'Margen estimado: ${money(e.marginCents!)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          if (!e.complete)
            Text(
              'Estimación incompleta: ${e.missingMaterialCosts > 0 ? '${e.missingMaterialCosts} consumo(s) sin coste conocido. ' : ''}${e.laborCostKnown ? '' : 'Falta el coste horario interno.'}',
            ),
          const SizedBox(height: 8),
          const Text(
            'Se basa en piezas consumidas y tiempo trabajado. No incluye todos los gastos del taller; no es beneficio neto.',
            style: TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

String percent(int bps) =>
    '${(bps / 100).toStringAsFixed(2).replaceAll('.', ',')} %';

Future<Map<String, dynamic>?> pricingDialog(
  BuildContext context,
  Map<String, dynamic> entry,
  bool labor,
) => formDialog(
  context,
  labor ? 'Revisar tarifa y descuento' : 'Revisar precio y cobro',
  [
    FieldSpec(
      'price',
      labor ? 'Tarifa por hora (€)' : 'Precio por unidad (€)',
      initial: ((entry[labor ? 'rateCents' : 'priceCents'] ?? 0) / 100)
          .toStringAsFixed(2),
      numeric: true,
    ),
    FieldSpec(
      'tax',
      'IVA (%)',
      initial: ((entry['taxBps'] ?? 2100) / 100).toStringAsFixed(2),
      numeric: true,
    ),
    FieldSpec(
      'discount',
      'Descuento (%)',
      initial: ((entry['discountBps'] ?? 0) / 100).toStringAsFixed(2),
      numeric: true,
    ),
    if (!labor)
      FieldSpec(
        'charge',
        'Cobro del consumo',
        initial: entry['charge'] == true ? 'yes' : 'no',
        choices: const {'yes': 'Se cobra', 'no': 'Sin cobro justificado'},
      ),
    const FieldSpec('reason', 'Motivo de la revisión', multiline: true),
  ],
  (v) => {
    'target': labor ? 'labor' : 'part',
    'targetId': entry['id'],
    'unitPriceCents': parseMoney(v['price']!),
    'taxBps': parseMoney(v['tax']!),
    'discountBps': parseMoney(v['discount']!),
    'charge': labor || v['charge'] == 'yes',
    'reason': v['reason'],
  },
  help:
      'La revisión conserva el tiempo trabajado, el movimiento de almacén y el coste registrado. El descuento se aplica antes del IVA. Un consumo sin cobro requiere motivo.',
);
