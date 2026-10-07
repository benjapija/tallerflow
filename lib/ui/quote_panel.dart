import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../domain/models.dart';
import '../domain/engine.dart';
import '../domain/quotes.dart';
import 'dialogs.dart';

class QuotePanel extends StatelessWidget {
  final WorkOrder order;
  final Actor actor;
  final List<CatalogItem> catalog;
  final bool canEdit;
  final Future<void> Function(String, Map<String, dynamic>) onSave;
  const QuotePanel({
    super.key,
    required this.order,
    required this.actor,
    required this.catalog,
    required this.canEdit,
    required this.onSave,
  });

  List<Map<String, dynamic>> get versions =>
      (order.data['quoteLedger']?['versions'] as List? ?? [])
          .cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get decisions =>
      (order.data['quoteLedger']?['decisions'] as List? ?? [])
          .cast<Map<String, dynamic>>();
  Future<void> draft(BuildContext context, Map<String, dynamic>? old) async {
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _QuoteEditor(
        order: order,
        actor: actor,
        catalog: catalog,
        original: old,
      ),
    );
    if (payload == null || !context.mounted) return;
    final ledger = QuoteLedger.fromJson(
      Map<String, dynamic>.from(
        order.data['quoteLedger'] ?? {'versions': [], 'decisions': []},
      ),
    );
    final q = ledger.prepare(
      order,
      actor,
      Operation(
        id: const Uuid().v4(),
        orderId: order.id,
        kind: 'quote_draft',
        actorId: actor.id,
        baseRevision: order.revision,
        at: DateTime.now().toUtc(),
        payload: payload,
      ),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Revisar presupuesto'),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(child: quoteContent(q)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar versión'),
          ),
        ],
      ),
    );
    if (confirmed == true) await onSave('quote_draft', payload);
  }

  Future<void> decide(BuildContext context, Map<String, dynamic> quote) async {
    final available = (quote['lines'] as List)
        .cast<Map<String, dynamic>>()
        .where(
          (line) => !decisions.any(
            (d) =>
                d['quoteId'] == quote['id'] &&
                d['version'] == quote['version'] &&
                (d['decisions'] as List).any((v) => v['lineId'] == line['id']),
          ),
        )
        .toList();
    final p = await formDialog(
      context,
      'Decisión del cliente · versión ${quote['version']}',
      [
        FieldSpec(
          'customer',
          'Destinatario',
          initial: quote['customer'],
          readOnly: true,
        ),
        const FieldSpec(
          'channel',
          'Canal',
          initial: 'telephone',
          choices: {
            'telephone': 'Teléfono',
            'in_person': 'En el taller',
            'email': 'Correo',
            'written': 'Documento escrito',
          },
        ),
        const FieldSpec(
          'evidence',
          'Soporte y persona que autoriza',
          multiline: true,
        ),
        const FieldSpec('reason', 'Motivo de registro', multiline: true),
        for (final line in available)
          FieldSpec(
            line['id'],
            '${line['description']} · ${money(line['totalCents'])}',
            initial: 'pending',
            choices: const {
              'pending': 'Sin decisión',
              'accepted': 'Autoriza',
              'rejected': 'Rechaza',
            },
          ),
      ],
      (v) {
        final result = [
          for (final line in available)
            if (v[line['id']] != 'pending')
              {'lineId': line['id'], 'accepted': v[line['id']] == 'accepted'},
        ];
        if (result.isEmpty) {
          throw const RuleException('Selecciona al menos una partida');
        }
        return {
          'quoteId': quote['id'],
          'version': quote['version'],
          'customer': v['customer'],
          'channel': v['channel'],
          'evidence': v['evidence'],
          'reason': v['reason'],
          'decisions': result,
        };
      },
      help:
          'Registra la decisión obtenida del destinatario sobre esta versión. El importe incluye impuestos. Un rechazo conserva las autorizaciones anteriores.',
    );
    if (p != null) await onSave('quote_decision', p);
  }

  Widget quoteContent(Map<String, dynamic> q) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '${q['title']} · versión ${q['version']}',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      Text('Destinatario: ${q['customer']}\nVálido hasta ${q['validUntil']}'),
      for (final line in q['lines'])
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${line['description']} · ${money(line['totalCents'])}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              for (final component in line['components'])
                Text(
                  '${component['description']} · ${component['kind'] == 'labor' ? '${component['minutes']} min' : '${quantity(component['quantityMilli'])} ${component['unit']}'} · ${money(component['unitPriceCents'])}/unidad · dto. ${(component['discountBps'] / 100).toStringAsFixed(2)} % · IVA ${(component['taxBps'] / 100).toStringAsFixed(2)} %',
                ),
              Text(
                'Base ${money(line['netCents'])} · impuesto ${money(line['taxCents'])}',
              ),
              for (final decision in decisions.where(
                (d) => d['quoteId'] == q['id'] && d['version'] == q['version'],
              ))
                for (final result in (decision['decisions'] as List).where(
                  (v) => v['lineId'] == line['id'],
                ))
                  Text(
                    '${result['accepted'] == true ? 'Autorizado' : 'Rechazado'} · ${decision['at']} · ${decision['channel']}\nSoporte: ${decision['evidence']}',
                  ),
            ],
          ),
        ),
      Text('Total con impuestos: ${money(q['totalCents'])}'),
      Text('Motivo: ${q['reason']}'),
      const Text('Presupuesto · no es una factura'),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final latest = <String, Map<String, dynamic>>{};
    for (final q in versions) {
      latest[q['id']] = q;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Presupuestos y autorizaciones',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Cada versión conserva precios y alcance. Preparar una ampliación mantiene el trabajo autorizado.',
            ),
            for (final q in latest.values)
              ExpansionTile(
                title: Text(
                  '${q['title']} · versión ${q['version']} · ${money(q['totalCents'])}',
                ),
                children: [
                  quoteContent(q),
                  if (canEdit && !order.issued)
                    Wrap(
                      spacing: 12,
                      children: [
                        TextButton(
                          onPressed: () => draft(context, q),
                          child: const Text('Nueva versión'),
                        ),
                        if ((q['lines'] as List).any(
                          (line) => !decisions.any(
                            (d) =>
                                d['quoteId'] == q['id'] &&
                                d['version'] == q['version'] &&
                                (d['decisions'] as List).any(
                                  (r) => r['lineId'] == line['id'],
                                ),
                          ),
                        ))
                          TextButton(
                            onPressed: () => decide(context, q),
                            child: const Text('Registrar decisión'),
                          ),
                      ],
                    ),
                ],
              ),
            if (versions.length > latest.length)
              ExpansionTile(
                title: const Text('Versiones anteriores'),
                children: [
                  for (final q in versions.where(
                    (q) => latest[q['id']]!['version'] != q['version'],
                  ))
                    ExpansionTile(
                      title: Text('${q['title']} · versión ${q['version']}'),
                      children: [quoteContent(q)],
                    ),
                ],
              ),
            if (canEdit && !order.issued)
              TextButton.icon(
                onPressed: () => draft(context, null),
                icon: const Icon(Icons.request_quote_outlined),
                label: const Text('Nuevo presupuesto'),
              ),
          ],
        ),
      ),
    );
  }
}

class _QuoteEditor extends StatefulWidget {
  final WorkOrder order;
  final Actor actor;
  final List<CatalogItem> catalog;
  final Map<String, dynamic>? original;
  const _QuoteEditor({
    required this.order,
    required this.actor,
    required this.catalog,
    this.original,
  });
  @override
  State<_QuoteEditor> createState() => _QuoteEditorState();
}

class _QuoteEditorState extends State<_QuoteEditor> {
  late List<Map<String, dynamic>> lines;
  late final TextEditingController title, reason, expiry;
  String? error;
  @override
  void initState() {
    super.initState();
    title = TextEditingController(
      text: widget.original?['title'] ?? 'Presupuesto de reparación',
    );
    reason = TextEditingController();
    expiry = TextEditingController(
      text: DateTime.now()
          .add(const Duration(days: 15))
          .toIso8601String()
          .substring(0, 10),
    );
    lines = [
      for (final line in widget.original?['lines'] ?? [])
        {
          'id': line['id'],
          'taskId': line['taskId'],
          'description': line['description'],
          'laborMinutes':
              ((line['components'] as List)
                  .where((p) => p['kind'] == 'labor')
                  .firstOrNull?['minutes'] ??
              0),
          'parts': [
            for (final part in line['components'])
              if (part['kind'] == 'part')
                {
                  for (final key in [
                    'reference',
                    'description',
                    'unit',
                    'quantityMilli',
                    'unitPriceCents',
                    'taxBps',
                    'discountBps',
                  ])
                    key: part[key],
                },
          ],
        },
    ];
  }

  @override
  void dispose() {
    title.dispose();
    reason.dispose();
    expiry.dispose();
    super.dispose();
  }

  Future<void> addLine() async {
    final tasks = widget.order.tasks
        .where(
          (t) =>
              t['cancelled'] != true &&
              !lines.any((l) => l['taskId'] == t['id']),
        )
        .toList();
    if (tasks.isEmpty) {
      setState(
        () => error = 'Añade una tarea vigente a la orden para presupuestarla',
      );
      return;
    }
    final p = await formDialog(
      context,
      'Partida de trabajo',
      [
        FieldSpec(
          'taskId',
          'Tarea',
          initial: tasks.first['id'],
          choices: {for (final t in tasks) t['id']: t['title']},
        ),
        const FieldSpec(
          'description',
          'Alcance que verá el cliente',
          multiline: true,
        ),
        const FieldSpec(
          'minutes',
          'Mano de obra estimada en minutos',
          initial: '30',
          numeric: true,
        ),
      ],
      (v) => {
        'id': const Uuid().v4(),
        'taskId': v['taskId'],
        'description': v['description'],
        'laborMinutes': int.parse(v['minutes']!),
        'parts': <Map<String, dynamic>>[],
      },
      help:
          'Se aplican la tarifa, impuesto y descuento actuales de la tarea. Los minutos estimados no se facturan automáticamente.',
    );
    if (p != null) setState(() => lines.add(p));
  }

  Future<void> addPart(Map<String, dynamic> line) async {
    final p = await formDialog(
      context,
      'Pieza presupuestada',
      const [
        FieldSpec('reference', 'Referencia'),
        FieldSpec('description', 'Descripción'),
        FieldSpec('unit', 'Unidad', initial: 'unidad'),
        FieldSpec('quantity', 'Cantidad', initial: '1', numeric: true),
        FieldSpec(
          'price',
          'Precio unitario sin impuestos (€)',
          initial: '0',
          numeric: true,
        ),
        FieldSpec('tax', 'Impuesto (%)', initial: '21', numeric: true),
        FieldSpec('discount', 'Descuento (%)', initial: '0', numeric: true),
      ],
      (v) => {
        'reference': v['reference'],
        'description': v['description'],
        'unit': v['unit'],
        'quantityMilli': parseQuantity(v['quantity']!),
        'unitPriceCents': parseMoney(v['price']!),
        'taxBps': parseMoney(v['tax']!),
        'discountBps': parseMoney(v['discount']!),
      },
      help:
          'Una pieza presupuestada no reserva ni consume existencias. Revisa referencia, unidad y cantidad para este vehículo.',
    );
    if (p != null) setState(() => (line['parts'] as List).add(p));
  }

  Future<void> catalogPart(Map<String, dynamic> line) async {
    final available = widget.catalog
        .where((c) => c.active && c.priceCents >= 0)
        .toList();
    if (available.isEmpty) return;
    final p = await formDialog(
      context,
      'Pieza del catálogo',
      [
        FieldSpec(
          'itemId',
          'Referencia',
          initial: available.first.id,
          choices: {
            for (final c in available)
              c.id:
                  '${c.reference} · ${c.description} · ${money(c.priceCents)} / ${c.unit}',
          },
        ),
        const FieldSpec('quantity', 'Cantidad', initial: '1', numeric: true),
        const FieldSpec(
          'discount',
          'Descuento (%)',
          initial: '0',
          numeric: true,
        ),
      ],
      (v) {
        final item = available.firstWhere((c) => c.id == v['itemId']);
        return {
          'reference': item.reference,
          'description': item.description,
          'unit': item.unit,
          'quantityMilli': parseQuantity(v['quantity']!),
          'unitPriceCents': item.priceCents,
          'taxBps': item.taxBps,
          'discountBps': parseMoney(v['discount']!),
        };
      },
      help:
          'Confirma que corresponde a este vehículo. Se conservarán precio, unidad e impuesto de esta versión; las existencias no cambian.',
    );
    if (p != null) setState(() => (line['parts'] as List).add(p));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.original == null ? 'Nuevo presupuesto' : 'Preparar nueva versión',
    ),
    content: SizedBox(
      width: 620,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Título'),
            ),
            TextField(
              controller: reason,
              decoration: const InputDecoration(
                labelText: 'Motivo de esta versión',
              ),
            ),
            TextField(
              controller: expiry,
              decoration: const InputDecoration(
                labelText: 'Válido hasta (AAAA-MM-DD)',
              ),
            ),
            for (final line in lines)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      ListTile(
                        title: Text(line['description']),
                        subtitle: Text(
                          '${line['laborMinutes']} minutos de mano de obra',
                        ),
                        trailing: IconButton(
                          tooltip: 'Quitar partida',
                          onPressed: () => setState(() => lines.remove(line)),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                      for (final part in line['parts'])
                        ListTile(
                          title: Text(
                            '${part['reference']} · ${part['description']}',
                          ),
                          subtitle: Text(
                            '${quantity(part['quantityMilli'])} ${part['unit']} · ${money(part['unitPriceCents'])} sin IVA',
                          ),
                          trailing: IconButton(
                            tooltip: 'Quitar pieza',
                            onPressed: () => setState(
                              () => (line['parts'] as List).remove(part),
                            ),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      TextButton(
                        onPressed: () => addPart(line),
                        child: const Text('Añadir pieza'),
                      ),
                      if (widget.catalog.any(
                        (c) => c.active && c.priceCents >= 0,
                      ))
                        TextButton(
                          onPressed: () => catalogPart(line),
                          child: const Text('Elegir del catálogo'),
                        ),
                    ],
                  ),
                ),
              ),
            TextButton.icon(
              onPressed: addLine,
              icon: const Icon(Icons.add),
              label: const Text('Añadir partida'),
            ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
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
        onPressed: () {
          try {
            if (title.text.trim().isEmpty ||
                reason.text.trim().isEmpty ||
                lines.isEmpty) {
              throw const RuleException('Completa título, motivo y partidas');
            }
            final day = DateTime.parse('${expiry.text.trim()}T23:59:59');
            if (day.toIso8601String().substring(0, 10) != expiry.text.trim() ||
                !day.isAfter(DateTime.now())) {
              throw const RuleException('Indica una fecha de validez futura');
            }
            final payload = {
              'id': widget.original?['id'] ?? const Uuid().v4(),
              'expectedVersion': widget.original?['version'] ?? 0,
              'title': title.text.trim(),
              'reason': reason.text.trim(),
              'validUntil': day.toUtc().toIso8601String(),
              'lines': lines,
            };
            final ledger = QuoteLedger.fromJson(
              Map<String, dynamic>.from(
                widget.order.data['quoteLedger'] ??
                    {'versions': [], 'decisions': []},
              ),
            );
            ledger.prepare(
              widget.order,
              widget.actor,
              Operation(
                id: const Uuid().v4(),
                orderId: widget.order.id,
                kind: 'quote_draft',
                actorId: widget.actor.id,
                baseRevision: widget.order.revision,
                at: DateTime.now().toUtc(),
                payload: payload,
              ),
            );
            Navigator.pop(context, payload);
          } catch (e) {
            setState(() => error = '$e');
          }
        },
        child: const Text('Revisar importes'),
      ),
    ],
  );
}
