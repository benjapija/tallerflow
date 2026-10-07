import 'package:flutter/material.dart';
import '../domain/fiscal_calculation.dart';
import '../domain/models.dart';

class TaxBreakdownButton extends StatelessWidget {
  final Map<String, dynamic> Function() source;
  final Actor Function() actor;
  const TaxBreakdownButton({
    super.key,
    required this.source,
    required this.actor,
  });
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    icon: const Icon(Icons.receipt_long_outlined),
    label: const Text('Desglose de impuestos'),
    onPressed: () {
      try {
        final summary = SavedTaxBreakdown.fromNote(source(), actor());
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Desglose de impuestos'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 420,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Documento de trabajo. Se muestran los importes registrados sin recalcularlos. La preparación fiscal no activa emisión.',
                    ),
                    const SizedBox(height: 16),
                    for (final g in summary.groups) ...[
                      Text(
                        g.rateBps == null
                            ? 'Tipo no guardado en el documento original'
                            : '${fiscalDecimal(g.rateBps!).replaceAll('.', ',')} % registrado',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${g.lineCount} ${g.lineCount == 1 ? 'partida' : 'partidas'} · base ${money(g.baseCents)} · cuota ${money(g.taxCents)}',
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (summary.groups.isEmpty) const Text('Sin partidas.'),
                    const Divider(),
                    Text('Base: ${money(summary.baseCents)}'),
                    Text('Impuestos: ${money(summary.taxCents)}'),
                    Text('Total: ${money(summary.totalCents)}'),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    },
  );
}
