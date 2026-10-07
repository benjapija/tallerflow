import 'package:flutter/material.dart';
import '../domain/diagnosis_notebook.dart';
import '../domain/models.dart';
import 'dialogs.dart';

class DiagnosisPanel extends StatelessWidget {
  final WorkOrder order;
  final Actor actor;
  final Future<void> Function(String, Map<String, dynamic>, int?) onSave;
  const DiagnosisPanel({
    super.key,
    required this.order,
    required this.actor,
    required this.onSave,
  });

  Future<void> add(
    BuildContext context, [
    Map<String, dynamic>? previous,
  ]) async {
    final p = await formDialog(
      context,
      previous == null ? 'Añadir al cuaderno' : 'Revisar entrada del cuaderno',
      [
        FieldSpec(
          'stage',
          'Tipo de entrada',
          initial: previous?['stage'] ?? 'symptom',
          choices: diagnosisStages,
        ),
        FieldSpec(
          'text',
          'Observación, comprobación o resultado',
          initial: previous?['text'] ?? '',
          multiline: true,
        ),
        FieldSpec(
          'context',
          'Condiciones, equipo, unidades y valores de referencia',
          initial: previous?['context'] ?? '',
          required: false,
          multiline: true,
        ),
        FieldSpec(
          'dtcs',
          'DTC registrados',
          initial: previous?['dtcs'] ?? '',
          required: false,
        ),
        FieldSpec(
          'source',
          'Fuente y referencia documental consultada',
          initial: previous?['source'] ?? '',
          required: false,
          multiline: true,
        ),
        const FieldSpec(
          'confirmed',
          'Comprobación personal',
          initial: 'no',
          choices: {
            'no': 'Todavía no confirmada',
            'yes': 'Sí, comprobada personalmente',
          },
        ),
        if (previous != null)
          const FieldSpec('reason', 'Motivo de revisión', multiline: true),
      ],
      (v) {
        if (['conclusion', 'verification'].contains(v['stage']) &&
            v['confirmed'] != 'yes') {
          throw const FormatException(
            'Confirma personalmente la conclusión o verificación',
          );
        }
        return {
          ...v,
          'confirmed': v['confirmed'] == 'yes',
          if (previous != null) 'replacesId': previous['id'],
        };
      },
      help:
          'Un DTC o una hipótesis no confirma una avería. Las conclusiones y verificaciones requieren tu confirmación. El cuaderno no registra tiempos, piezas ni autoriza trabajos.',
    );
    if (p != null) {
      await onSave(
        'diagnosis_add',
        p,
        previous == null ? null : order.revision,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = diagnosisEntries(order);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cuaderno de diagnóstico',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Síntoma → hipótesis → comprobación → resultado → conclusión → intervención → verificación.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => add(context),
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Añadir entrada'),
            ),
            for (final row in rows.reversed) ...[
              const Divider(height: 28),
              Text(
                '${diagnosisStages[row['stage']] ?? 'Retirada'} · ${row['actorName']} · ${row['at']}',
              ),
              if (row['text'] != null) Text(row['text']),
              for (final k in ['context', 'dtcs', 'source', 'reason'])
                if ((row[k] ?? '').isNotEmpty) Text(row[k]),
              if (row['confirmed'] == true)
                const Text('Confirmada personalmente'),
              if (row['stage'] != 'withdrawal' &&
                  !diagnosisEntryActive(rows, row['id']))
                const Text(
                  'Entrada conservada como antecedente; revisada o retirada',
                ),
              if (diagnosisEntryActive(rows, row['id']) &&
                  (actor.isOffice || row['actorId'] == actor.id))
                Wrap(
                  children: [
                    TextButton(
                      onPressed: () => add(context, row),
                      child: const Text('Revisar conservando original'),
                    ),
                    TextButton(
                      onPressed: () async {
                        final reason = await textDialog(
                          context,
                          'Retirar conclusión o entrada',
                          'Motivo de retirada',
                        );
                        if (reason != null) {
                          await onSave('diagnosis_withdraw', {
                            'sourceId': row['id'],
                            'reason': reason,
                          }, order.revision);
                        }
                      },
                      child: const Text('Retirar con motivo'),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}
