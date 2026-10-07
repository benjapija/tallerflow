import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../domain/models.dart';
import 'dialogs.dart';

const _notice =
    'Documentos de ensayo. Emisión y transmisión fiscal desactivadas. '
    'No son facturas ni justifican una aceptación por Hacienda.';

/// Views confirmed server records separately from durable local requests.
/// Callbacks preserve command identity, ownership and immutable content.
class FiscalDraftsPanel extends StatefulWidget {
  final Actor actor;
  final bool accessAllowed, offline, demo, loaded;
  final Map<String, dynamic> ledger;
  final Map<String, dynamic> fiscalProfile;
  final List<Map<String, dynamic>> queue, history;
  final String? syncError;
  final Map<String, dynamic> Function(List<Map<String, dynamic>>) calculate;
  final Future<void> Function(Map<String, dynamic>) onPrepare;
  final Future<void> Function(String, String) onWithdraw;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String) onRetry;
  final Future<void> Function(String, String) onReview;

  const FiscalDraftsPanel({
    super.key,
    required this.actor,
    required this.accessAllowed,
    required this.offline,
    required this.demo,
    this.loaded = false,
    required this.ledger,
    required this.fiscalProfile,
    required this.queue,
    required this.history,
    required this.calculate,
    required this.onPrepare,
    required this.onWithdraw,
    required this.onRefresh,
    required this.onRetry,
    required this.onReview,
    this.syncError,
  });

  @override
  State<FiscalDraftsPanel> createState() => _FiscalDraftsPanelState();
}

class _FiscalDraftsPanelState extends State<FiscalDraftsPanel> {
  bool busy = false;
  String? message;
  bool get available => widget.accessAllowed && widget.actor.active && !busy;
  bool get profileSupported =>
      widget.fiscalProfile['sii'] == 'no' &&
      [
        'common',
        'canary',
        'ceuta',
        'melilla',
      ].contains(widget.fiscalProfile['territory']);
  List<Map<String, dynamic>> get records => _maps(widget.ledger['records']);
  List<Map<String, dynamic>> get heads => _maps(widget.ledger['heads']);

  bool frozen(Map<String, dynamic> body) => heads.any(
    (h) =>
        h['issuer_nif'] == body['issuerNif'] &&
        h['installation'] == body['installation'] &&
        h['restored'] == true,
  );

  Future<void> run(Future<void> Function() action, String success) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
      if (mounted) setState(() => message = success);
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> prepare([Map<String, dynamic>? original]) async {
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FiscalDraftEditor(
        initial: original,
        calculate: widget.calculate,
        frozenHeads: heads.where((h) => h['restored'] == true).toList(),
      ),
    );
    if (payload == null || !mounted) return;
    await run(
      () => widget.onPrepare(payload),
      'Solicitud de ensayo conservada. Consulta su estado; solo el servidor confirma el registro.',
    );
  }

  Future<void> withdraw(Map<String, dynamic> body) async {
    final reason = await textDialog(
      context,
      'Retirar ensayo ${body['prefix']}-${body['number']}',
      'Motivo de la retirada',
      multiline: true,
      help:
          'Añade un registro vinculado al original y conserva su contenido y número. '
          'No es una anulación fiscal. Solo una respuesta del servidor confirma la retirada.',
    );
    if (reason == null || !mounted) return;
    await run(
      () => widget.onWithdraw(body['id'] as String, reason),
      'Solicitud de retirada conservada. Consulta su estado de confirmación.',
    );
  }

  Future<void> review(Map<String, dynamic> command) async {
    final reason = await textDialog(
      context,
      'Revisar operación de ensayo',
      'Motivo y conclusión de la revisión',
      multiline: true,
      help:
          'Conserva la solicitud original y su resultado. No cambia el contenido enviado '
          'ni reintenta con otra cabecera automáticamente. Actualiza el registro antes de preparar otro ensayo.',
    );
    if (reason == null || !mounted) return;
    await run(
      () => widget.onReview(command['id'] as String, reason),
      'Revisión conservada. El original sigue en el historial.',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.actor.role != Role.admin || !widget.actor.active) {
      return const SizedBox.shrink();
    }
    if (!widget.accessAllowed) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(22),
          child: Text('Renueva tu sesión para consultar y registrar ensayos.'),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Registro de ensayos',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(_notice),
            const SizedBox(height: 8),
            Text(
              widget.demo
                  ? 'Demostración local: ninguna operación está confirmada por un servidor.'
                  : widget.offline
                  ? 'Sin conexión: las solicitudes se guardan localmente hasta sincronizar.'
                  : 'Las solicitudes conservan su identidad y contenido ante respuestas inciertas.',
            ),
            if (!widget.loaded && !widget.demo)
              const Text(
                'Actualiza el registro para comprobar el estado de las cadenas del servidor.',
              ),
            if (!profileSupported)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Antes de preparar ensayos, revisa «Preparación fiscal». El circuito actual admite '
                  'territorio común, Canarias, Ceuta o Melilla y SII «No». '
                  'Conserva pendientes los datos desconocidos; esta selección no determina obligaciones.',
                ),
              ),
            if (busy) const LinearProgressIndicator(),
            if (message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(message!),
              ),
            if (widget.syncError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(widget.syncError!),
              ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed:
                      available &&
                          profileSupported &&
                          (widget.loaded || widget.demo)
                      ? prepare
                      : null,
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('Preparar ensayo'),
                ),
                OutlinedButton.icon(
                  onPressed: available && !widget.offline && !widget.demo
                      ? () => run(
                          widget.onRefresh,
                          'Registro actualizado desde el servidor.',
                        )
                      : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Actualizar registro'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Solicitudes locales',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            if (widget.queue.isEmpty) const Text('Sin solicitudes pendientes.'),
            for (final command in widget.queue) commandTile(command),
            const SizedBox(height: 18),
            const Text(
              'Registros inmutables',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            if (records.isEmpty)
              const Text('Todavía no hay ensayos registrados.'),
            for (final record in records) recordTile(record),
            if (heads.any((h) => h['restored'] == true)) ...[
              const SizedBox(height: 12),
              const Text(
                'Las instalaciones recuperadas están congeladas. Sus ensayos se conservan; '
                'prepara una instalación nueva para continuar las pruebas.',
              ),
            ],
            if (widget.history.isNotEmpty)
              ExpansionTile(
                title: const Text('Historial de solicitudes y revisiones'),
                children: [
                  for (final command in widget.history)
                    commandTile(command, historical: true),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget commandTile(Map<String, dynamic> command, {bool historical = false}) {
    final payload = _map(command['payload']);
    final status = command['status'] as String? ?? 'pending';
    final label =
        {
          'pending': 'Pendiente local · sin confirmación',
          'confirmed': 'Confirmada por el servidor',
          'rejected': 'Rechazada',
          'conflict': 'En conflicto · requiere revisión',
          'reviewed': 'Revisada · original conservado',
          'local': 'Ensayo local · sin confirmación del servidor',
          'demo': 'Ensayo local · sin confirmación del servidor',
        }[status] ??
        'Estado sin confirmar';
    return ExpansionTile(
      key: ValueKey('fiscal-command-${command['id']}'),
      tilePadding: EdgeInsets.zero,
      title: Text(
        command['action'] == 'fiscal_draft_withdraw'
            ? 'Retirada de ensayo'
            : 'Registro de ensayo',
      ),
      subtitle: Text(
        widget.demo && status == 'confirmed'
            ? 'Ensayo local · sin confirmación del servidor'
            : label,
      ),
      children: [
        _details(payload, confirmed: false),
        Text('Identificador conservado: ${command['id']}'),
        if (command['error'] != null) Text('Resultado: ${command['error']}'),
        if (command['reviewReason'] != null)
          Text('Revisión: ${command['reviewReason']}'),
        if (!historical)
          Wrap(
            spacing: 8,
            children: [
              if (status == 'pending')
                OutlinedButton(
                  onPressed: available && !widget.offline && !widget.demo
                      ? () => run(
                          () => widget.onRetry(command['id'] as String),
                          'Reintento conservado con la misma identidad.',
                        )
                      : null,
                  child: const Text('Reintentar misma solicitud'),
                ),
              if (status == 'rejected' || status == 'conflict')
                OutlinedButton(
                  onPressed: available ? () => review(command) : null,
                  child: const Text('Registrar revisión'),
                ),
            ],
          ),
      ],
    );
  }

  Widget recordTile(Map<String, dynamic> record) {
    final body = _map(record['body']);
    final withdrawal = body['kind'] == 'withdrawal';
    final retired = records.any(
      (r) => _map(r['body'])['targetId'] == body['id'],
    );
    final pendingWithdrawal = widget.queue.any(
      (q) =>
          q['action'] == 'fiscal_draft_withdraw' &&
          _map(q['payload'])['targetId'] == body['id'],
    );
    final isFrozen = frozen(body);
    return ExpansionTile(
      key: ValueKey('fiscal-record-${body['id']}'),
      tilePadding: EdgeInsets.zero,
      title: Text(
        '${withdrawal ? 'Retirada' : 'Ensayo'} ${body['prefix']}-${body['number']}',
      ),
      subtitle: Text(
        '${widget.demo ? 'Ensayo local · sin servidor' : 'Confirmado por el servidor'}'
        '${retired ? ' · retirado mediante registro posterior' : ''}'
        '${isFrozen ? ' · instalación recuperada' : ''}',
      ),
      children: [
        _details(body, confirmed: true),
        Text('Secuencia de ensayo: ${body['sequence']}'),
        Text('Autor: ${body['actorId']} · dispositivo: ${body['deviceId']}'),
        Text('Registro: ${body['createdAt']}'),
        SelectableText(
          'Huella interna de integridad: ${record['ledger_hash'] ?? body['ledgerHash'] ?? ''}',
        ),
        const Text(
          'Esta huella no es la huella AEAT ni una firma electrónica.',
        ),
        if (!withdrawal && !retired && !isFrozen)
          OutlinedButton(
            onPressed: available && profileSupported && !pendingWithdrawal
                ? () => withdraw(body)
                : null,
            child: Text(
              pendingWithdrawal
                  ? 'Retirada pendiente de confirmar'
                  : 'Retirar con motivo',
            ),
          ),
      ],
    );
  }
}

class FiscalDraftEditor extends StatefulWidget {
  final Map<String, dynamic>? initial;
  final Map<String, dynamic> Function(List<Map<String, dynamic>>) calculate;
  final List<Map<String, dynamic>> frozenHeads;
  const FiscalDraftEditor({
    super.key,
    this.initial,
    required this.calculate,
    this.frozenHeads = const [],
  });
  @override
  State<FiscalDraftEditor> createState() => _FiscalDraftEditorState();
}

class _FiscalDraftEditorState extends State<FiscalDraftEditor> {
  final form = GlobalKey<FormState>();
  late final issuer = TextEditingController(
    text: widget.initial?['issuerNif'] ?? '',
  );
  late final installation = TextEditingController(
    text: widget.initial?['installation'] ?? '',
  );
  late final prefix = TextEditingController(
    text: widget.initial?['prefix'] ?? 'ENSAYO-TALLER',
  );
  late final date = TextEditingController(
    text:
        widget.initial?['issueDate'] ??
        DateTime.now().toIso8601String().substring(0, 10),
  );
  late final name = TextEditingController(
    text: widget.initial?['recipient']?['name'] ?? '',
  );
  late final nif = TextEditingController(
    text: widget.initial?['recipient']?['nif'] ?? '',
  );
  final reason = TextEditingController();
  late final lines = _maps(widget.initial?['lines']).map(cloneMap).toList();
  Map<String, dynamic>? reviewed, preview;
  String? error;

  @override
  void dispose() {
    for (final c in [issuer, installation, prefix, date, name, nif, reason]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> line([int? index]) async {
    final old = index == null ? null : lines[index];
    final result = await formDialog(
      context,
      'Partida del ensayo',
      [
        FieldSpec(
          'description',
          'Descripción',
          initial: old?['description'] ?? '',
        ),
        FieldSpec(
          'quantity',
          'Cantidad',
          initial: quantity(old?['quantityMilli'] ?? 1000),
          numeric: true,
        ),
        FieldSpec(
          'price',
          'Precio por unidad (€)',
          initial: _decimal(old?['unitCents'] ?? 0),
          numeric: true,
        ),
        FieldSpec(
          'discount',
          'Descuento (%)',
          initial: _decimal(old?['discountBps'] ?? 0),
          numeric: true,
        ),
        FieldSpec(
          'tax',
          'Impuesto',
          initial: old?['tax'] ?? 'iva',
          choices: const {
            'iva': 'IVA',
            'igic': 'IGIC',
            'ipsi': 'IPSI',
            'other': 'Otro impuesto por revisar',
          },
        ),
        FieldSpec(
          'rate',
          'Tipo (%)',
          initial: _decimal(old?['taxBps'] ?? 2100),
          numeric: true,
        ),
        FieldSpec(
          'treatment',
          'Tratamiento',
          initial: old?['treatment'] ?? 'taxable',
          choices: const {
            'taxable': 'Sujeto con cuota',
            'exempt': 'Exento',
            'reverse_charge': 'Inversión del sujeto pasivo',
            'outside_scope': 'No sujeto',
          },
        ),
        FieldSpec(
          'reason',
          'Justificación fiscal (obligatoria para tratamientos sin cuota)',
          initial: old?['reason'] ?? '',
          required: false,
          multiline: true,
        ),
      ],
      (v) {
        final line = <String, dynamic>{
          'id': old?['id'] ?? const Uuid().v4(),
          'description': v['description']!.trim(),
          'quantityMilli': parseQuantity(v['quantity']!),
          'unitCents': parseMoney(v['price']!),
          'discountBps': parseMoney(v['discount']!),
          'tax': v['tax'],
          'taxBps': parseMoney(v['rate']!),
          'treatment': v['treatment'],
          'reason': v['reason']!.trim(),
        };
        widget.calculate([line]);
        return line;
      },
      help:
          'Revisa impuestos y tratamiento. Esta selección no determina obligaciones fiscales ni activa emisión.',
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        lines.add(result);
      } else {
        lines[index] = result;
      }
      error = null;
    });
  }

  void review() {
    if (!form.currentState!.validate()) return;
    try {
      final normalizedNif = issuer.text.trim().toUpperCase();
      final normalizedInstallation = installation.text.trim();
      if (widget.frozenHeads.any(
        (h) =>
            h['issuer_nif'] == normalizedNif &&
            h['installation'] == normalizedInstallation,
      )) {
        throw const FormatException(
          'Esta instalación recuperada está congelada. Indica una instalación nueva de ensayo.',
        );
      }
      final issued = date.text.trim();
      final parsed = DateTime.tryParse(issued);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(issued) ||
          parsed == null ||
          parsed.toIso8601String().substring(0, 10) != issued) {
        throw const FormatException(
          'Introduce una fecha real con formato AAAA-MM-DD',
        );
      }
      final series = prefix.text.trim().toUpperCase();
      if (!RegExp(r'^ENSAYO-[A-Z0-9-]{1,16}$').hasMatch(series)) {
        throw const FormatException(
          'La serie debe empezar por ENSAYO- y terminar en 1 a 16 letras, números o guiones',
        );
      }
      final calculated = widget.calculate(lines);
      setState(() {
        reviewed = {
          'issuerNif': normalizedNif,
          'installation': normalizedInstallation,
          'prefix': series,
          'issueDate': issued,
          'recipient': {
            'name': name.text.trim(),
            'nif': nif.text.trim().toUpperCase(),
          },
          'reason': reason.text.trim(),
          'lines': lines.map(cloneMap).toList(),
        };
        preview = calculated;
        error = null;
      });
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  Widget field(
    String label,
    TextEditingController controller, {
    int? maxLength,
    String? Function(String)? validate,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      maxLength: maxLength,
      maxLines: lines,
      validator: (v) => (v ?? '').trim().isEmpty
          ? 'Completa este campo'
          : validate?.call(v!.trim()),
    ),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      reviewed == null
          ? 'Preparar documento de ensayo'
          : 'Revisar antes de registrar',
    ),
    content: SizedBox(
      width: 620,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(_notice),
            const SizedBox(height: 16),
            if (reviewed != null) ...[
              _details({
                ...reviewed!,
                'calculation': preview,
              }, confirmed: false),
              const Text(
                'El número de ensayo se asigna al confirmar el servidor. No se reserva un número local.',
              ),
            ] else
              Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    field(
                      'NIF del emisor de ensayo',
                      issuer,
                      maxLength: 9,
                      validate: _nif,
                    ),
                    field('Instalación de ensayo', installation, maxLength: 80),
                    field('Serie de ensayo', prefix, maxLength: 23),
                    field('Fecha de ensayo · AAAA-MM-DD', date, maxLength: 10),
                    field(
                      'Nombre del destinatario ficticio',
                      name,
                      maxLength: 120,
                    ),
                    field(
                      'NIF del destinatario ficticio',
                      nif,
                      maxLength: 9,
                      validate: _nif,
                    ),
                    field('Motivo del ensayo', reason, lines: 3),
                    const Text(
                      'Partidas',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    for (var i = 0; i < lines.length; i++)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(lines[i]['description']),
                        subtitle: Text(
                          '${quantity(lines[i]['quantityMilli'])} × ${money(lines[i]['unitCents'])}',
                        ),
                        trailing: Wrap(
                          children: [
                            IconButton(
                              onPressed: () => line(i),
                              tooltip: 'Editar partida',
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              onPressed: () =>
                                  setState(() => lines.removeAt(i)),
                              tooltip:
                                  'Quitar partida del ensayo sin registrar',
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    ),
    actions: [
      if (reviewed == null)
        TextButton.icon(
          onPressed: lines.length < 1000 ? line : null,
          icon: const Icon(Icons.add),
          label: const Text('Añadir partida'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      if (reviewed != null)
        TextButton(
          onPressed: () => setState(() {
            reviewed = null;
            preview = null;
          }),
          child: const Text('Volver a preparar'),
        ),
      FilledButton(
        onPressed: reviewed == null
            ? review
            : () => Navigator.pop(context, reviewed),
        child: Text(
          reviewed == null ? 'Revisar ensayo' : 'Guardar solicitud de ensayo',
        ),
      ),
    ],
  );
}

String? _nif(String value) =>
    RegExp(r'^[A-Z0-9]{9}$').hasMatch(value.toUpperCase())
    ? null
    : 'Introduce 9 letras o números; no se acredita la identidad fiscal';
String _decimal(int value) =>
    (value / 100).toStringAsFixed(2).replaceAll('.', ',');
Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Map<String, dynamic>> _maps(dynamic value) => value is List
    ? value.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList()
    : [];

Widget _details(Map<String, dynamic> body, {required bool confirmed}) {
  final calculation = _map(body['calculation']);
  final recipient = _map(body['recipient']);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'Emisor: ${body['issuerNif'] ?? ''} · instalación: ${body['installation'] ?? ''}',
      ),
      if (body['prefix'] != null) Text('Serie de ensayo: ${body['prefix']}'),
      if (body['issueDate'] != null) Text('Fecha: ${body['issueDate']}'),
      if (recipient.isNotEmpty)
        Text('Destinatario: ${recipient['name']} · ${recipient['nif']}'),
      if (body['targetId'] != null)
        Text('Original conservado: ${body['targetId']}'),
      Text('Motivo: ${body['reason'] ?? ''}'),
      for (final line
          in _maps(calculation['lines']).isEmpty
              ? _maps(body['lines'])
              : _maps(calculation['lines']))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${line['description']} · ${quantity(line['quantityMilli'])} × ${money(line['unitCents'])}',
              ),
              Text(
                'Descuento ${_decimal(line['discountBps'])} % · ${('${line['tax']}').toUpperCase()} ${_decimal(line['taxBps'])} % · ${_treatment(line['treatment'])}',
              ),
              if ((line['reason'] as String? ?? '').isNotEmpty)
                Text('Justificación: ${line['reason']}'),
              if (line['baseCents'] != null)
                Text(
                  'Base ${money(line['baseCents'])} · cuota ${money(line['taxCents'])} · total ${money(line['totalCents'])}',
                ),
            ],
          ),
        ),
      if (calculation.isNotEmpty) ...[
        const Divider(),
        Text(
          'Base ${money(calculation['baseCents'])} · impuestos ${money(calculation['taxCents'])}',
        ),
        Text(
          '${confirmed ? 'Total registrado' : 'Total revisado'}: ${money(calculation['totalCents'])}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ],
  );
}

String _treatment(dynamic value) =>
    const {
      'taxable': 'Sujeto con cuota',
      'exempt': 'Exento',
      'reverse_charge': 'Inversión del sujeto pasivo',
      'outside_scope': 'No sujeto',
    }[value] ??
    'Tratamiento por revisar';
