import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/controller.dart';
import '../domain/models.dart';
import 'dialogs.dart';

class AssistantPanel extends StatelessWidget {
  final WorkshopController controller;
  final WorkOrder order;
  final Future<void> Function(Future<void> Function()) run;
  const AssistantPanel({
    super.key,
    required this.controller,
    required this.order,
    required this.run,
  });

  Future<void> consult(BuildContext context, String mode) async {
    await run(() async {
      final preview = await controller.previewAssistant(order.id, mode);
      if (!context.mounted) return;
      if (preview['available'] != true) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Asistente pendiente de activar'),
            content: const Text(
              'El acceso y el límite gratuito de IA todavía no están confirmados. Puedes seguir registrando diagnósticos, tiempos, piezas y notas.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Continuar trabajando'),
              ),
            ],
          ),
        );
        return;
      }
      final sources = (preview['sources'] as List).cast<Map<String, dynamic>>();
      final chosen = await showDialog<List<String>>(
        context: context,
        builder: (ctx) => _SourceChoice(sources: sources),
      );
      if (chosen == null || !context.mounted) return;
      final form = await formDialog(
        context,
        mode == 'technical'
            ? 'Consulta técnica con fuentes'
            : 'Borrador de trabajos registrados',
        [
          const FieldSpec('question', 'Qué necesitas revisar', multiline: true),
          if (mode == 'technical') ...[
            const FieldSpec('make', 'Marca comprobada'),
            const FieldSpec('model', 'Modelo comprobado'),
            const FieldSpec('year', 'Año comprobado'),
            const FieldSpec('engine', 'Motor comprobado'),
            const FieldSpec(
              'variant',
              'Variante necesaria para esta consulta',
              required: false,
            ),
            const FieldSpec(
              'identity',
              'Identificación del vehículo',
              initial: 'no',
              choices: {
                'no': 'Todavía no comprobada',
                'yes': 'He comprobado marca, modelo, año, motor y variante',
              },
            ),
          ],
          const FieldSpec(
            'privacy',
            'Datos que se enviarán al proveedor de IA',
            initial: 'no',
            choices: {
              'no': 'Todavía no revisados',
              'yes': 'He revisado las fuentes; no contienen datos personales',
            },
          ),
        ],
        (v) {
          if (v['privacy'] != 'yes' ||
              (mode == 'technical' && v['identity'] != 'yes')) {
            throw const FormatException(
              'Revisa las fuentes y la identificación antes de enviar',
            );
          }
          if (mode == 'technical' &&
              !RegExp(r'^(19|20)\d{2}$').hasMatch(v['year'] ?? '')) {
            throw const FormatException('Indica el año comprobado');
          }
          return {
            'mode': mode,
            'revision': preview['revision'],
            'question': v['question'],
            'sourceIds': chosen,
            'privacyConfirmed': true,
            if (mode == 'technical') 'identityConfirmed': true,
            if (mode == 'technical')
              'identity': {
                for (final k in ['make', 'model', 'year', 'engine', 'variant'])
                  k: v[k],
              },
          };
        },
        help:
            'Se enviarán únicamente las fuentes seleccionadas y esta consulta. La IA prepara un borrador: no confirma averías, consulta documentación contratada ni registra cargos.',
      );
      if (form != null) await controller.requestAssistant(order.id, form);
    });
  }

  Future<void> review(BuildContext context, Map<String, dynamic> record) async {
    final result = record['result'] as Map, draft = result['draft'] as Map;
    final lines = <String>[
      for (final k in ['hypotheses', 'checks', 'paragraphs'])
        for (final r in (draft[k] as List? ?? [])) r['text'],
      for (final text in (draft['missingInfo'] as List? ?? []))
        'Pendiente: $text',
    ];
    final v = await formDialog(
      context,
      'Revisar borrador y fuentes',
      [
        FieldSpec(
          'text',
          'Texto revisado',
          initial: lines.join('\n\n'),
          multiline: true,
        ),
        const FieldSpec(
          'confirmed',
          'Revisión humana',
          initial: 'no',
          choices: {
            'no': 'Todavía pendiente',
            'yes': 'He comprobado el texto y sus fuentes originales',
          },
        ),
      ],
      (v) {
        if (v['confirmed'] != 'yes') {
          throw const FormatException('Comprueba personalmente el borrador');
        }
        return v;
      },
      help:
          'El texto quedará como borrador revisado. Los tiempos, cantidades, precios, autorizaciones y documentos se gestionan con sus procesos habituales.',
    );
    if (v != null) {
      await run(() => controller.reviewAssistant(record['id'], v['text']));
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = controller.assistantRecords
        .where((r) => r['orderId'] == order.id)
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Asistente con fuentes',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Hipótesis y borradores pendientes de revisión. La documentación técnica autorizada todavía no está conectada.',
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => consult(context, 'technical'),
                  icon: const Icon(Icons.manage_search),
                  label: const Text('Consulta técnica'),
                ),
                if (controller.actor.isOffice)
                  TextButton.icon(
                    onPressed: () => consult(context, 'office'),
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Borrador para oficina'),
                  ),
              ],
            ),
            for (final r in records.reversed) ...[
              const Divider(),
              Text(
                '${r['request']['mode'] == 'office' ? 'Oficina' : 'Técnica'} · ${r['at']}',
              ),
              Text(switch (r['status']) {
                'completed' => 'Borrador pendiente de revisión',
                'reviewed' => 'Revisado personalmente',
                'archived' => 'Consulta archivada',
                'uncertain' => 'Respuesta incierta; conserva la consulta',
                _ => 'Respuesta pendiente de recuperar',
              }),
              if (r['result']?['sources'] is List)
                for (final s in r['result']['sources'])
                  ExpansionTile(
                    title: Text('Fuente original · ${_sourceLabel(s)}'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: SelectableText(_sourceText(s)),
                      ),
                    ],
                  ),
              if (r['status'] == 'completed')
                TextButton(
                  onPressed: () => review(context, r),
                  child: const Text('Revisar texto y fuentes'),
                ),
              if (r['status'] == 'reviewed') ...[
                SelectableText(r['review']['text']),
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: r['review']['text']),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Texto revisado copiado')),
                      );
                    }
                  },
                  child: const Text('Copiar texto revisado'),
                ),
              ],
              if (r['status'] == 'pending')
                TextButton(
                  onPressed: () =>
                      run(() => controller.recoverAssistant(r['id'])),
                  child: const Text('Recuperar respuesta sin reenviar'),
                ),
              if (['pending', 'uncertain'].contains(r['status']))
                TextButton(
                  onPressed: () async {
                    final reason = await textDialog(
                      context,
                      'Archivar conservando la consulta',
                      'Motivo',
                    );
                    if (reason != null) {
                      await run(
                        () => controller.archiveAssistant(r['id'], reason),
                      );
                    }
                  },
                  child: const Text('Archivar con motivo'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SourceChoice extends StatefulWidget {
  final List<Map<String, dynamic>> sources;
  const _SourceChoice({required this.sources});
  @override
  State<_SourceChoice> createState() => _SourceChoiceState();
}

class _SourceChoiceState extends State<_SourceChoice> {
  final chosen = <String>{};
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Elegir fuentes originales'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Revisa el contenido. Selecciona solo los registros necesarios, sin datos personales. Máximo veinte fuentes.',
            ),
            if (widget.sources.isEmpty)
              const Text('Añade primero observaciones o trabajos registrados.'),
            for (final s in widget.sources)
              CheckboxListTile(
                value: chosen.contains(s['id']),
                onChanged: (v) => setState(() {
                  if (v == true && chosen.length < 20) {
                    chosen.add(s['id']);
                  } else {
                    chosen.remove(s['id']);
                  }
                }),
                title: Text(
                  s['kind'] == 'validated_antecedent'
                      ? 'Antecedente validado; requiere comprobación actual'
                      : 'Registro · ${_sourceLabel(s)}',
                ),
                subtitle: Text(_sourceText(s)),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: chosen.isEmpty
            ? null
            : () => Navigator.pop(context, chosen.toList()),
        child: const Text('Usar fuentes seleccionadas'),
      ),
    ],
  );
}

String _sourceLabel(Map s) =>
    const {
      'symptom': 'Síntoma',
      'hypothesis': 'Hipótesis',
      'test': 'Comprobación',
      'result': 'Resultado',
      'conclusion': 'Conclusión confirmada',
      'intervention': 'Intervención registrada',
      'verification': 'Verificación',
      'recorded_note': 'Observación registrada',
      'recorded_time': 'Tiempo registrado',
      'recorded_consumption': 'Consumo registrado',
      'recorded_return': 'Devolución registrada',
      'validated_antecedent': 'Antecedente validado',
    }[s['kind']] ??
    'Entrada del cuaderno';
String _sourceText(Map s) {
  if (s['content'] is Map) {
    final c = s['content'] as Map;
    return [
      for (final key in const {
        'title': 'Caso',
        'vehicle': 'Vehículo',
        'engine': 'Motor',
        'symptom': 'Síntoma',
        'dtcs': 'DTC',
        'checks': 'Comprobaciones',
        'result': 'Resultado',
        'conclusion': 'Conclusión',
        'intervention': 'Intervención',
        'verification': 'Verificación',
        'sources': 'Referencias',
      }.entries)
        if (c[key.key] != null) '${key.value}: ${c[key.key]}',
    ].join('\n');
  }
  return [
    s['text'],
    s['context'],
    s['dtcs'],
  ].where((v) => v != null && v.toString().isNotEmpty).join('\n');
}
