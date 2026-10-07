import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../domain/models.dart';
import '../domain/inspections.dart';

class InspectionPanel extends StatelessWidget {
  final WorkOrder order;
  final bool canEdit;
  final Future<void> Function(Map<String, dynamic>) onSave;
  const InspectionPanel({
    super.key,
    required this.order,
    required this.canEdit,
    required this.onSave,
  });
  Future<void> edit(BuildContext context, Map<String, dynamic>? value) async {
    final p = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _InspectionEditor(order: order, original: value),
    );
    if (p != null) await onSave(p);
  }

  Widget entry(Map<String, dynamic> i, {Widget? action}) => ExpansionTile(
    title: Text('${i['title']} · versión ${i['version']}'),
    subtitle: Text(
      '${i['at']} · ${(i['items'] as List).length} comprobaciones',
    ),
    trailing: action,
    children: [
      for (final item in i['items'])
        ListTile(
          leading: Icon(
            Icons.circle,
            size: 16,
            color: switch (item['status']) {
              'correct' => Colors.green,
              'follow_up' => Colors.orange,
              _ => Colors.red,
            },
          ),
          title: Text('${item['label']} · ${inspectionStates[item['status']]}'),
          subtitle: Text(
            '${item['observation']}${(item['photoIds'] as List).isEmpty ? '' : '\n${(item['photoIds'] as List).length} fotografías vinculadas'}',
          ),
        ),
      ListTile(title: Text('Motivo: ${i['reason']}')),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final current = (order.data['inspections'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final history = (order.data['inspectionHistory'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Inspección', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Configura las comprobaciones y registra hallazgos. Las recomendaciones pendientes requieren una autorización antes de convertirse en trabajos cobrables.',
            ),
            for (final i in current)
              entry(
                i,
                action: canEdit && !order.issued
                    ? IconButton(
                        tooltip: 'Revisar inspección',
                        onPressed: () => edit(context, i),
                        icon: const Icon(Icons.edit_outlined),
                      )
                    : null,
              ),
            if (history.isNotEmpty)
              ExpansionTile(
                title: const Text('Versiones anteriores'),
                children: [for (final i in history) entry(i)],
              ),
            if (canEdit && !order.issued)
              TextButton.icon(
                onPressed: () => edit(context, null),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Nueva inspección'),
              ),
          ],
        ),
      ),
    );
  }
}

class _InspectionEditor extends StatefulWidget {
  final WorkOrder order;
  final Map<String, dynamic>? original;
  const _InspectionEditor({required this.order, this.original});
  @override
  State<_InspectionEditor> createState() => _InspectionEditorState();
}

class _InspectionEditorState extends State<_InspectionEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title, reason;
  late final List<Map<String, dynamic>> items;
  Map<String, dynamic> newItem() => {
    'id': const Uuid().v4(),
    'label': '',
    'status': '',
    'observation': '',
    'photoIds': <String>[],
  };
  @override
  void initState() {
    super.initState();
    title = TextEditingController(
      text: widget.original?['title'] ?? 'Inspección del vehículo',
    );
    reason = TextEditingController(
      text: widget.original == null ? 'Inspección inicial' : '',
    );
    items = widget.original == null
        ? [newItem()]
        : [
            for (final i in widget.original!['items'])
              cloneMap(Map<String, dynamic>.from(i)),
          ];
  }

  @override
  void dispose() {
    title.dispose();
    reason.dispose();
    super.dispose();
  }

  String? requiredValue(String? v) =>
      (v ?? '').trim().isEmpty ? 'Completa este dato' : null;
  @override
  Widget build(BuildContext context) {
    final photos = (widget.order.data['photos'] as List? ?? [])
        .where((p) => p['status'] == 'attached')
        .toList();
    return AlertDialog(
      title: Text(
        widget.original == null ? 'Nueva inspección' : 'Revisar inspección',
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: title,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de inspección',
                  ),
                  validator: requiredValue,
                ),
                for (final item in items)
                  Card(
                    key: ValueKey(item['id']),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextFormField(
                            initialValue: item['label'],
                            maxLength: 200,
                            decoration: const InputDecoration(
                              labelText: 'Comprobación',
                            ),
                            onChanged: (v) => item['label'] = v,
                            validator: requiredValue,
                          ),
                          DropdownButtonFormField<String>(
                            initialValue:
                                inspectionStates.containsKey(item['status'])
                                ? item['status']
                                : null,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Resultado de la comprobación',
                            ),
                            items: [
                              for (final e in inspectionStates.entries)
                                DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value),
                                ),
                            ],
                            onChanged: (v) =>
                                setState(() => item['status'] = v),
                            validator: requiredValue,
                          ),
                          TextFormField(
                            initialValue: item['observation'],
                            maxLength: 2000,
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: 'Observación o recomendación',
                            ),
                            onChanged: (v) => item['observation'] = v,
                            validator: (v) => item['status'] != 'correct'
                                ? requiredValue(v)
                                : null,
                          ),
                          if (photos.isNotEmpty)
                            Wrap(
                              spacing: 4,
                              children: [
                                for (final p in photos)
                                  FilterChip(
                                    label: Text(
                                      '${p['caption']}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    selected: (item['photoIds'] as List)
                                        .contains(p['id']),
                                    onSelected: (v) => setState(() {
                                      final ids = item['photoIds'] as List;
                                      if (v && ids.length < 10) {
                                        ids.add(p['id']);
                                      } else if (!v) {
                                        ids.remove(p['id']);
                                      }
                                    }),
                                  ),
                              ],
                            ),
                          if (photos.isEmpty)
                            const Text(
                              'Sincroniza las fotografías de esta orden para poder vincularlas.',
                            ),
                          if (items.length > 1)
                            TextButton(
                              onPressed: () =>
                                  setState(() => items.remove(item)),
                              child: const Text('Quitar comprobación'),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (items.length < 40)
                  TextButton.icon(
                    onPressed: () => setState(() => items.add(newItem())),
                    icon: const Icon(Icons.add),
                    label: const Text('Añadir comprobación'),
                  ),
                TextFormField(
                  controller: reason,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Motivo de esta versión',
                  ),
                  validator: requiredValue,
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
            if (form.currentState!.validate()) {
              Navigator.pop(context, {
                'id': widget.original?['id'] ?? const Uuid().v4(),
                'expectedVersion': widget.original?['version'] ?? 0,
                'title': title.text,
                'items': items,
                'reason': reason.text,
              });
            }
          },
          child: const Text('Guardar inspección'),
        ),
      ],
    );
  }
}
