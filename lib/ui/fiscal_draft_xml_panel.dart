import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../domain/models.dart';

const _xmlNotice =
    'XML técnico de ensayo · no es una factura emitida ni una respuesta de Hacienda. '
    'Emisión y transmisión fiscal desactivadas. Se conserva el registro original.';

class FiscalDraftXmlPanel extends StatefulWidget {
  final Actor actor;
  final bool accessAllowed;
  final List<Map<String, dynamic>> confirmedRecords, artifacts;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  onGenerate;
  final Future<void> Function(Uint8List, String)? onSaveBytes;
  const FiscalDraftXmlPanel({
    super.key,
    required this.actor,
    required this.accessAllowed,
    required this.confirmedRecords,
    required this.artifacts,
    required this.onGenerate,
    this.onSaveBytes,
  });
  @override
  State<FiscalDraftXmlPanel> createState() => _FiscalDraftXmlPanelState();
}

class _FiscalDraftXmlPanelState extends State<FiscalDraftXmlPanel> {
  bool busy = false;
  String? message;
  List<Map<String, dynamic>> get records => widget.confirmedRecords
      .where((r) => r['kind'] == 'draft' || _map(r['body'])['kind'] == 'draft')
      .toList();
  bool retired(Map<String, dynamic> record) => widget.confirmedRecords.any(
    (r) =>
        (r['target_id'] ?? _map(r['body'])['targetId']) ==
        (record['id'] ?? _map(record['body'])['id']),
  );

  Map<String, dynamic>? savedSettings(Map<String, dynamic> source) {
    final body = _map(source['body']);
    for (final artifact in widget.artifacts) {
      final snapshot = _map(artifact['snapshot']);
      final record = _map(snapshot['sourceRecord']);
      final issuer = _map(snapshot['issuer']);
      final system = _map(snapshot['system']);
      if (issuer['nif'] != (source['issuer_nif'] ?? body['issuerNif']) ||
          system['installation'] !=
              (source['installation'] ?? body['installation']) ||
          (record.isNotEmpty &&
              record['installation'] != system['installation'])) {
        continue;
      }
      final manufacturer = _map(system['manufacturer']);
      return {
        'issuerName': issuer['name'],
        'manufacturerName': manufacturer['name'],
        'manufacturerNif': manufacturer['nif'],
        for (final key in [
          'name',
          'id',
          'version',
          'installation',
          'onlyVerifactu',
          'canHaveMultipleTaxpayers',
          'hasMultipleTaxpayers',
        ])
          key: system[key],
      };
    }
    return null;
  }

  Future<void> generate(Map<String, dynamic> record) async {
    final body = _map(record['body']);
    final conserved = savedSettings(record);
    final settings = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FiscalDraftXmlSettingsDialog(
        issuerNif: '${record['issuer_nif'] ?? body['issuerNif']}',
        installation: '${record['installation'] ?? body['installation']}',
        savedSettings: conserved,
      ),
    );
    if (settings == null || !mounted) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await widget.onGenerate('${record['id'] ?? body['id']}', settings);
      if (mounted) {
        setState(() {
          message =
              'XML de ensayo conservado. Revisa sus datos y huellas antes de guardar una copia. No se ha enviado.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save(Map<String, dynamic> artifact) async {
    final xml = artifact['xml'];
    if (xml is! String || xml.isEmpty) return;
    final snapshot = _map(artifact['snapshot']);
    final source = _map(snapshot['sourceRecord']);
    final safe = '${artifact['recordId']}-${artifact['generatorVersion']}'
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-');
    final filename = 'TallerFlow-${source['prefix'] ?? 'ENSAYO'}-$safe.xml';
    final bytes = Uint8List.fromList(utf8.encode(xml));
    setState(() {
      busy = true;
      message = null;
    });
    try {
      if (widget.onSaveBytes != null) {
        await widget.onSaveBytes!(bytes, filename);
      } else {
        await FilePicker.saveFile(
          dialogTitle: 'Guardar XML técnico de ensayo',
          fileName: filename,
          type: FileType.custom,
          allowedExtensions: ['xml'],
          bytes: bytes,
        );
      }
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
          child: Text('Renueva tu sesión para consultar los XML de ensayo.'),
        ),
      );
    }
    final artifacts = widget.artifacts
        .where(
          (a) => records.any(
            (r) => (r['id'] ?? _map(r['body'])['id']) == a['recordId'],
          ),
        )
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'XML técnicos de ensayo',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(_xmlNotice),
            const SizedBox(height: 8),
            const Text(
              'Proyección técnica F1 de régimen general desde registros confirmados. '
              'La generación valida la cadena completa y conserva la versión del generador; '
              'un caso no admitido se rechaza sin sustituir originales.',
            ),
            if (busy) const LinearProgressIndicator(),
            if (message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(message!),
              ),
            const SizedBox(height: 14),
            if (records.isEmpty)
              const Text(
                'Confirma un ensayo en el servidor antes de preparar su XML. Las solicitudes locales pendientes no generan XML.',
              ),
            if (records.any(retired))
              const Text(
                'Las retiradas de ensayo conservan los XML originales. No se convierten en anulaciones AEAT.',
              ),
            for (final record in records)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Ensayo ${record['prefix'] ?? _map(record['body'])['prefix']}-${record['number'] ?? _map(record['body'])['number']}${retired(record) ? ' · retirado' : ''}',
                ),
                subtitle: Text(
                  'Instalación ${record['installation'] ?? _map(record['body'])['installation']} · original confirmado',
                ),
                trailing: OutlinedButton(
                  onPressed: busy ? null : () => generate(record),
                  child: const Text('Preparar XML'),
                ),
              ),
            if (artifacts.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Copias técnicas conservadas',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final artifact in artifacts) artifactTile(artifact),
            ],
          ],
        ),
      ),
    );
  }

  Widget artifactTile(Map<String, dynamic> artifact) => ExpansionTile(
    key: ValueKey(
      'fiscal-xml-${artifact['recordId']}-${artifact['generatorVersion']}',
    ),
    tilePadding: EdgeInsets.zero,
    title: Text('XML de ensayo · secuencia ${artifact['sequence']}'),
    subtitle: Text(
      'Generador ${artifact['generatorVersion']} · original conservado',
    ),
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(_xmlNotice),
          Text('Registro de origen: ${artifact['recordId']}'),
          Text('Instante conservado: ${artifact['generatedAt']}'),
          SelectableText(
            'Huella interna del registro: ${artifact['ledgerHash']}',
          ),
          const Text(
            'Comprueba la integridad del registro de TallerFlow; no es la huella AEAT.',
          ),
          const SizedBox(height: 8),
          SelectableText(
            'Huella AEAT del XML de ensayo: ${artifact['aeatHash']}',
          ),
          const Text(
            'Calculada para esta proyección técnica. No acredita envío, firma ni aceptación oficial.',
          ),
          const SizedBox(height: 8),
          SelectableText(
            'Integridad del archivo XML (SHA-256): ${artifact['xmlSha256']}',
          ),
          ExpansionTile(
            title: const Text('Vista previa del XML técnico'),
            children: [
              SizedBox(
                height: 260,
                width: double.infinity,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: SelectableText(
                    '${artifact['xml']}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : () => save(artifact),
            icon: const Icon(Icons.save_alt),
            label: const Text('Guardar XML de ensayo'),
          ),
        ],
      ),
    ],
  );
}

class FiscalDraftXmlSettingsDialog extends StatefulWidget {
  final String issuerNif, installation;
  final Map<String, dynamic>? savedSettings;
  const FiscalDraftXmlSettingsDialog({
    super.key,
    required this.issuerNif,
    required this.installation,
    this.savedSettings,
  });
  @override
  State<FiscalDraftXmlSettingsDialog> createState() =>
      _FiscalDraftXmlSettingsDialogState();
}

class _FiscalDraftXmlSettingsDialogState
    extends State<FiscalDraftXmlSettingsDialog> {
  final form = GlobalKey<FormState>();
  late final issuer = TextEditingController(
    text: widget.savedSettings?['issuerName'] ?? 'Taller ficticio de ensayo',
  );
  late final manufacturer = TextEditingController(
    text:
        widget.savedSettings?['manufacturerName'] ??
        'Fabricante ficticio de ensayo',
  );
  late final manufacturerNif = TextEditingController(
    text: widget.savedSettings?['manufacturerNif'] ?? 'B12345674',
  );
  late final name = TextEditingController(
    text: widget.savedSettings?['name'] ?? 'TallerFlow ensayo',
  );
  late final id = TextEditingController(
    text: widget.savedSettings?['id'] ?? 'TF',
  );
  late final version = TextEditingController(
    text: widget.savedSettings?['version'] ?? '0.3-ensayo',
  );
  late bool only = widget.savedSettings?['onlyVerifactu'] ?? true;
  late bool canMultiple =
      widget.savedSettings?['canHaveMultipleTaxpayers'] ?? true;
  late bool multiple = widget.savedSettings?['hasMultipleTaxpayers'] ?? true;
  bool reviewed = false;
  String? error;
  bool get locked => widget.savedSettings != null;
  @override
  void dispose() {
    for (final c in [
      issuer,
      manufacturer,
      manufacturerNif,
      name,
      id,
      version,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget field(String label, TextEditingController controller, int limit) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          readOnly: locked,
          decoration: InputDecoration(labelText: label),
          maxLength: limit,
          validator: (v) =>
              (v ?? '').trim().isEmpty ? 'Completa este campo' : null,
        ),
      );
  void confirm() {
    if (!form.currentState!.validate()) return;
    if (!reviewed) {
      setState(
        () =>
            error = 'Confirma la revisión del ensayo antes de generar el XML.',
      );
      return;
    }
    if (multiple && !canMultiple) {
      setState(
        () => error =
            'Revisa las opciones de varios obligados: la capacidad debe estar declarada.',
      );
      return;
    }
    if (!RegExp(
      r'^[A-Z0-9]{9}$',
    ).hasMatch(manufacturerNif.text.trim().toUpperCase())) {
      setState(() => error = 'Revisa el NIF ficticio del fabricante.');
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'issuerName': issuer.text.trim(),
      'manufacturerName': manufacturer.text.trim(),
      'manufacturerNif': manufacturerNif.text.trim().toUpperCase(),
      'name': name.text.trim(),
      'id': id.text.trim(),
      'version': version.text.trim(),
      'installation': widget.installation,
      'onlyVerifactu': only,
      'canHaveMultipleTaxpayers': canMultiple,
      'hasMultipleTaxpayers': multiple,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Revisar datos ficticios del XML'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(_xmlNotice),
              const SizedBox(height: 12),
              Text(
                'NIF del emisor conservado: ${widget.issuerNif}\nInstalación conservada: ${widget.installation}',
              ),
              if (locked)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Esta cadena ya tiene XML. Se utilizan los mismos datos técnicos conservados; no se modifican los originales.',
                  ),
                ),
              const SizedBox(height: 12),
              field('Nombre ficticio del emisor', issuer, 120),
              field('Nombre ficticio del fabricante', manufacturer, 120),
              field('NIF ficticio del fabricante', manufacturerNif, 9),
              field('Nombre del sistema de ensayo', name, 30),
              field('Identificador del sistema', id, 2),
              field('Versión técnica conservada', version, 50),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Uso exclusivo VERI*FACTU declarado en este ensayo',
                ),
                value: only,
                onChanged: locked
                    ? null
                    : (v) => setState(() => only = v ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'El sistema de ensayo admite varios obligados',
                ),
                value: canMultiple,
                onChanged: locked
                    ? null
                    : (v) => setState(() => canMultiple = v ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Esta instalación de ensayo utiliza varios obligados',
                ),
                value: multiple,
                onChanged: locked
                    ? null
                    : (v) => setState(() => multiple = v ?? false),
              ),
              const Text(
                'Estas opciones describen únicamente el XML de prueba; no activan un sistema fiscal ni una transmisión.',
              ),
              CheckboxListTile(
                key: const ValueKey('fiscal-xml-review'),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'He revisado los datos ficticios y entiendo que este XML no se envía ni es una factura emitida',
                ),
                value: reviewed,
                onChanged: (v) => setState(() {
                  reviewed = v ?? false;
                  error = null;
                }),
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
        onPressed: confirm,
        child: const Text('Generar y conservar XML de ensayo'),
      ),
    ],
  );
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
