import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../data/controller.dart';
import '../domain/case_library.dart';
import '../domain/diagnosis_notebook.dart';
import '../domain/models.dart';
import 'dialogs.dart';

Future<void> draftCase(
  BuildContext context,
  WorkshopController c,
  WorkOrder order,
  Future<void> Function(Future<void> Function()) run, [
  Map<String, dynamic>? previous,
]) async {
  final entries = diagnosisEntries(order);
  Map<String, String> choices(String stage) => {
    for (final e in entries)
      if (e['stage'] == stage &&
          e['confirmed'] == true &&
          diagnosisEntryActive(entries, e['id']))
        e['id']: '${e['text']}',
  };
  final conclusions = choices('conclusion'),
      verifications = choices('verification');
  if (conclusions.isEmpty || verifications.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Registra una conclusión y una verificación confirmadas en el cuaderno',
        ),
      ),
    );
    return;
  }
  final latest = previous == null ? null : (previous['versions'] as List).last;
  final content = latest?['content'] as Map<String, dynamic>? ?? {};
  String initialLink(String key, Map<String, String> values) =>
      values.containsKey(latest?[key]) ? latest![key] : values.keys.first;
  final p = await formDialog(
    context,
    previous == null ? 'Preparar caso técnico' : 'Nueva versión del caso',
    [
      FieldSpec(
        'conclusionId',
        'Conclusión vigente del cuaderno',
        choices: conclusions,
        initial: initialLink('conclusionId', conclusions),
      ),
      FieldSpec(
        'verificationId',
        'Verificación vigente del cuaderno',
        choices: verifications,
        initial: initialLink('verificationId', verifications),
      ),
      for (final f in caseFields.entries)
        FieldSpec(
          f.key,
          f.value,
          initial:
              content[f.key] ??
              (f.key == 'vehicle'
                  ? order.data['vehicle'] ?? ''
                  : f.key == 'engine'
                  ? order.data['engine'] ?? ''
                  : ''),
          required: !['dtcs', 'sources'].contains(f.key),
          multiline: !['title', 'vehicle', 'engine', 'dtcs'].contains(f.key),
        ),
      const FieldSpec(
        'reason',
        'Motivo del registro o revisión',
        multiline: true,
      ),
    ],
    (v) => {
      'id': previous?['id'] ?? const Uuid().v4(),
      'sourceOrderId': order.id,
      'conclusionId': v['conclusionId'],
      'verificationId': v['verificationId'],
      'content': {for (final key in caseFields.keys) key: v[key]},
      'reason': v['reason'],
    },
    help:
        'Redacta solo información técnica. Omite matrícula, VIN, nombres, contacto y documentos personales. El borrador necesita una revisión humana antes de publicarse en tu taller.',
  );
  if (p != null) await run(() => c.library('case_draft', p));
}

class CaseLibraryPanel extends StatefulWidget {
  final WorkshopController controller;
  final Future<void> Function(Future<void> Function()) run;
  const CaseLibraryPanel({
    super.key,
    required this.controller,
    required this.run,
  });
  @override
  State<CaseLibraryPanel> createState() => _CaseLibraryPanelState();
}

class _CaseLibraryPanelState extends State<CaseLibraryPanel> {
  String query = '';
  Future<void> validate(Map<String, dynamic> c) async {
    final p = await formDialog(
      context,
      'Validar caso para el taller',
      [
        const FieldSpec(
          'technicalConfirmed',
          'Revisión técnica',
          initial: 'no',
          choices: {
            'no': 'Pendiente',
            'yes': 'He revisado las comprobaciones y el resultado',
          },
        ),
        const FieldSpec(
          'privacyConfirmed',
          'Revisión de datos personales',
          initial: 'no',
          choices: {
            'no': 'Pendiente',
            'yes': 'He eliminado los datos personales del texto',
          },
        ),
        const FieldSpec(
          'reason',
          'Evidencia y motivo de validación',
          multiline: true,
        ),
      ],
      (v) {
        if (v['technicalConfirmed'] != 'yes' ||
            v['privacyConfirmed'] != 'yes') {
          throw const FormatException(
            'Confirma ambas revisiones antes de publicar',
          );
        }
        return {
          'id': c['id'],
          'revision': c['revision'],
          'version': (c['versions'] as List).last['version'],
          'technicalConfirmed': true,
          'privacyConfirmed': true,
          'reason': v['reason'],
        };
      },
      help:
          'Valida el último borrador. Un caso similar es un antecedente y no confirma la causa de otra avería.',
    );
    if (p != null) {
      await widget.run(() => widget.controller.library('case_validate', p));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final rows = visibleLibrary(state, widget.controller.actor)
        .where(
          (c) => (c['versions'] as List).any(
            (v) => (v['content'] as Map).values
                .join(' ')
                .toLowerCase()
                .contains(query.toLowerCase()),
          ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Biblioteca de casos del taller',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Casos propios revisados por una persona. Un caso parecido es un antecedente, no una prueba de la causa actual.',
        ),
        const SizedBox(height: 16),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Buscar por vehículo, motor, síntoma o DTC',
          ),
          onChanged: (v) => setState(() => query = v),
        ),
        const SizedBox(height: 16),
        if (rows.isEmpty)
          const Text(
            'No hay casos visibles para esta búsqueda. Prepara uno desde una orden con conclusión y verificación confirmadas.',
          ),
        for (final c in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${(c['versions'] as List).last['content']['title']}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      c['withdrawn'] == true
                          ? 'Retirado de consulta'
                          : c['activeVersion'] == null
                          ? 'Borrador pendiente de validación'
                          : 'Publicada la versión ${c['activeVersion']}',
                    ),
                    if (c['needsReview'] == true)
                      const Text(
                        'Necesita revisión: la conclusión o verificación de origen ha cambiado.',
                        style: TextStyle(color: Colors.deepOrange),
                      ),
                    for (final v in (c['versions'] as List).reversed)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(
                          'Versión ${v['version']}${c['activeVersion'] == v['version'] ? ' · publicada' : ' · borrador o antecedente'}',
                        ),
                        children: [
                          for (final f in caseFields.entries)
                            if ('${v['content'][f.key] ?? ''}'.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '${f.value}: ${v['content'][f.key]}',
                                  ),
                                ),
                              ),
                        ],
                      ),
                    if (c['editable'] == true)
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => validate(c),
                            child: const Text('Validar último borrador'),
                          ),
                          if (state.orders[c['sourceOrderId']] != null)
                            TextButton(
                              onPressed: () => draftCase(
                                context,
                                widget.controller,
                                state.orders[c['sourceOrderId']]!,
                                widget.run,
                                c,
                              ),
                              child: const Text('Crear nueva versión'),
                            ),
                          if (c['activeVersion'] != null &&
                              c['withdrawn'] != true)
                            TextButton(
                              onPressed: () async {
                                final p = await formDialog(
                                  context,
                                  'Retirar caso de consulta',
                                  [
                                    const FieldSpec(
                                      'reason',
                                      'Motivo, por ejemplo reaparición de la avería',
                                      multiline: true,
                                    ),
                                  ],
                                  (v) => {
                                    'id': c['id'],
                                    'revision': c['revision'],
                                    'reason': v['reason'],
                                  },
                                );
                                if (p != null) {
                                  await widget.run(
                                    () => widget.controller.library(
                                      'case_withdraw',
                                      p,
                                    ),
                                  );
                                }
                              },
                              child: const Text('Retirar caso'),
                            ),
                        ],
                      ),
                    if (c['editable'] == true)
                      for (final e in (c['events'] as List).reversed)
                        Text(
                          '${e['kind'] == 'case_validate'
                              ? 'Validación'
                              : e['kind'] == 'case_withdraw'
                              ? 'Retirada'
                              : 'Borrador'} · ${e['actorName']} · ${e['at']} · ${e['reason']}',
                        ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
