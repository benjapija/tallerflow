import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../data/demo.dart';
import '../domain/models.dart';

class FieldSpec {
  final String key, label, initial;
  final bool required, multiline, numeric;
  final Map<String, String>? choices;
  const FieldSpec(
    this.key,
    this.label, {
    this.initial = '',
    this.required = true,
    this.multiline = false,
    this.numeric = false,
    this.choices,
  });
}

Future<Map<String, dynamic>?> formDialog(
  BuildContext context,
  String title,
  List<FieldSpec> fields,
  Map<String, dynamic> Function(Map<String, String>) convert, {
  String? help,
}) => showDialog<Map<String, dynamic>>(
  context: context,
  barrierDismissible: false,
  builder: (_) =>
      FieldsDialog(title: title, fields: fields, convert: convert, help: help),
);

class FieldsDialog extends StatefulWidget {
  final String title;
  final List<FieldSpec> fields;
  final Map<String, dynamic> Function(Map<String, String>) convert;
  final String? help;
  const FieldsDialog({
    super.key,
    required this.title,
    required this.fields,
    required this.convert,
    this.help,
  });
  @override
  State<FieldsDialog> createState() => _FieldsDialogState();
}

class _FieldsDialogState extends State<FieldsDialog> {
  final form = GlobalKey<FormState>();
  late Map<String, String> values = {
    for (final f in widget.fields) f.key: f.initial,
  };
  String? error;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.help != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Text(
                    widget.help!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xff72827e),
                      height: 1.5,
                    ),
                  ),
                ),
              for (final f in widget.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: f.choices != null
                      ? DropdownButtonFormField<String>(
                          initialValue: f.initial,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: f.label),
                          items: f.choices!.entries
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(
                                    e.value,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => values[f.key] = v ?? '',
                        )
                      : TextFormField(
                          initialValue: f.initial,
                          decoration: InputDecoration(labelText: f.label),
                          maxLines: f.multiline ? 3 : 1,
                          keyboardType: f.numeric
                              ? const TextInputType.numberWithOptions(
                                  decimal: true,
                                )
                              : TextInputType.text,
                          validator: (v) =>
                              f.required && (v ?? '').trim().isEmpty
                              ? 'Completa este campo'
                              : null,
                          onChanged: (v) => values[f.key] = v,
                        ),
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
            final result = widget.convert(values);
            Navigator.pop(context, result);
          } catch (e) {
            setState(
              () => error = e.toString().replaceFirst('FormatException: ', ''),
            );
          }
        },
        child: const Text('Confirmar y guardar'),
      ),
    ],
  );
}

Future<String?> textDialog(
  BuildContext context,
  String title,
  String label, {
  String initial = '',
  bool multiline = false,
  String? help,
}) async {
  final result = await formDialog(
    context,
    title,
    [FieldSpec('text', label, initial: initial, multiline: multiline)],
    (v) => {'text': v['text']!.trim()},
    help: help,
  );
  return result?['text'];
}

int positiveInteger(String value, {bool allowZero = false}) {
  final n = int.tryParse(value.trim());
  if (n == null || n < (allowZero ? 0 : 1)) {
    throw const FormatException('Introduce un número entero válido');
  }
  return n;
}

int parseMoney(String value) {
  final s = value.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(s)) {
    throw const FormatException('Introduce un importe con hasta 2 decimales');
  }
  final p = s.split('.');
  return int.parse(p[0]) * 100 +
      int.parse((p.length == 2 ? p[1] : '').padRight(2, '0'));
}

Future<Map<String, dynamic>?> receptionDialog(
  BuildContext context,
  List<Actor> members,
) => formDialog(
  context,
  'Nueva recepción',
  [
    const FieldSpec('plate', 'Matrícula'),
    const FieldSpec('country', 'País de matriculación', initial: 'ES'),
    const FieldSpec('vin', 'VIN o bastidor (opcional)', required: false),
    const FieldSpec('vehicle', 'Marca y modelo'),
    const FieldSpec('engine', 'Año y motorización', required: false),
    const FieldSpec('client', 'Cliente'),
    const FieldSpec('phone', 'Teléfono', required: false),
    const FieldSpec('km', 'Kilometraje de entrada', numeric: true),
    const FieldSpec(
      'symptom',
      'Descripción original del cliente',
      multiline: true,
    ),
    const FieldSpec('location', 'Ubicación del vehículo', initial: 'Recepción'),
    const FieldSpec(
      'keys',
      'Ubicación de las llaves',
      initial: 'Panel de recepción',
    ),
    const FieldSpec('due', 'Fecha prevista', initial: 'Por confirmar'),
    const FieldSpec(
      'priority',
      'Prioridad',
      initial: 'Normal',
      choices: {'Normal': 'Normal', 'Alta': 'Alta'},
    ),
    FieldSpec(
      'technician',
      'Operario asignado',
      initial:
          members.where((m) => m.role == Role.technician).firstOrNull?.id ??
          members.first.id,
      choices: {for (final m in members) m.id: m.name},
    ),
    const FieldSpec(
      'template',
      'Plantilla de tareas',
      initial: 'diagnosis',
      choices: {
        'diagnosis': 'Diagnóstico inicial',
        'service': 'Servicio de aceite y filtro',
      },
    ),
    const FieldSpec(
      'taskTitle',
      'Descripción de la tarea (opcional)',
      required: false,
    ),
    const FieldSpec(
      'estimate',
      'Tiempo estimado en minutos (opcional)',
      numeric: true,
      required: false,
    ),
    const FieldSpec(
      'compatibility',
      '¿Operaciones y referencias comprobadas para este vehículo?',
      initial: 'no',
      choices: {
        'no': 'Pendiente: crear para revisión',
        'yes': 'Sí, comprobadas por el taller',
      },
    ),
  ],
  (v) {
    final km = positiveInteger(v['km']!, allowZero: true);
    final tid = const Uuid().v4();
    final approved = false; // A template is never a customer authorization.
    final t = demoTask(
      tid,
      v['template'] == 'service'
          ? 'Servicio de aceite y filtro'
          : 'Diagnóstico inicial',
      authorized: approved,
      assignees: [v['technician']!],
      estimate: v['template'] == 'service' ? 45 : 30,
    );
    if (v['taskTitle']!.trim().isNotEmpty) t['title'] = v['taskTitle']!.trim();
    if (v['estimate']!.trim().isNotEmpty) {
      t['estimateMinutes'] = positiveInteger(v['estimate']!);
    }
    t['template'] = v['template'];
    t['compatibilityChecked'] = v['compatibility'] == 'yes';
    return {
      'plate': v['plate'],
      'country': v['country']!.toUpperCase(),
      'vin': v['vin']!.trim().toUpperCase(),
      'vehicleId': const Uuid().v4(),
      'number': 'OT-${const Uuid().v4().substring(0, 6).toUpperCase()}',
      'vehicle': v['vehicle'],
      'engine': v['engine'] ?? '',
      'client': v['client'],
      'phone': v['phone'],
      'km': km,
      'symptom': v['symptom'],
      'location': v['location'],
      'keys': v['keys'],
      'due': v['due'],
      'priority': v['priority'],
      'tasks': [t],
      'quality': null,
    };
  },
  help:
      'Conserva las palabras del cliente. La plantilla prepara las tareas; oficina registrará la autorización antes de empezar.',
);
Future<Map<String, dynamic>?> partDialog(
  BuildContext context,
  List<CatalogItem> catalog,
  List<Map<String, dynamic>> tasks,
) async {
  if (tasks.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No hay tareas autorizadas disponibles.')),
    );
    return null;
  }
  return formDialog(
    context,
    'Registrar pieza o consumible',
    [
      FieldSpec(
        'taskId',
        'Tarea',
        initial: tasks.first['id'],
        choices: {for (final t in tasks) t['id']: t['title']},
      ),
      FieldSpec(
        'itemId',
        'Referencia del catálogo',
        initial: catalog.first.id,
        choices: {
          for (final c in catalog) c.id: '${c.reference} · ${c.description}',
        },
      ),
      const FieldSpec(
        'quantity',
        'Cantidad · usa litros o unidades del catálogo',
        initial: '1',
        numeric: true,
      ),
      const FieldSpec(
        'kind',
        'Tipo de registro',
        initial: 'consume',
        choices: {
          'consume': 'Consumida en la reparación',
          'reserve': 'Reservada · todavía sin consumir',
          'customer': 'Aportada por el cliente',
        },
      ),
    ],
    (v) => {
      'taskId': v['taskId'],
      'itemId': v['itemId'],
      'quantityMilli': parseQuantity(v['quantity']!),
      'kind': v['kind'],
    },
    help:
        'Comprueba la referencia para este vehículo. Una reserva no añade un cargo ni descuenta existencias.',
  );
}

Future<Map<String, dynamic>?> manualTimeDialog(BuildContext context) {
  final now = DateTime.now();
  return formDialog(
    context,
    'Añadir tiempo manual',
    [
      FieldSpec(
        'start',
        'Inicio · fecha y hora del dispositivo',
        initial: now
            .subtract(const Duration(minutes: 30))
            .toString()
            .substring(0, 16),
      ),
      FieldSpec(
        'end',
        'Final · fecha y hora del dispositivo',
        initial: now.toString().substring(0, 16),
      ),
      const FieldSpec('reason', 'Motivo del registro manual', multiline: true),
    ],
    (v) => {
      'start': DateTime.parse(v['start']!).toUtc().toIso8601String(),
      'end': DateTime.parse(v['end']!).toUtc().toIso8601String(),
      'reason': v['reason'],
    },
    help:
        'Se registra tiempo trabajado. Oficina decidirá los minutos facturables. No se admiten intervalos que dupliquen un cronómetro.',
  );
}

Future<Map<String, dynamic>?> authorizationDialog(
  BuildContext context,
  String client,
) => formDialog(
  context,
  'Registrar autorización del cliente',
  [
    FieldSpec('customer', 'Persona que autoriza', initial: client),
    const FieldSpec(
      'version',
      'Versión del presupuesto o ampliación',
      initial: '1',
      numeric: true,
    ),
    const FieldSpec(
      'amount',
      'Máximo autorizado para esta tarea · impuestos incluidos (€)',
      numeric: true,
    ),
    const FieldSpec(
      'evidence',
      'Canal, fecha y soporte de la autorización',
      multiline: true,
    ),
  ],
  (v) => {
    'customer': v['customer'],
    'version': positiveInteger(v['version']!),
    'approvedCents': parseMoney(v['amount']!),
    'evidence': v['evidence'],
  },
  help:
      'Registra únicamente una autorización obtenida del cliente. Un cambio de alcance o precio requiere una nueva autorización.',
);
Future<Map<String, dynamic>?> billableDialog(
  BuildContext context,
  int current,
) => formDialog(
  context,
  'Revisar mano de obra facturable',
  [
    FieldSpec(
      'minutes',
      'Minutos facturables',
      initial: '$current',
      numeric: true,
    ),
    const FieldSpec('reason', 'Motivo de la revisión', multiline: true),
  ],
  (v) => {
    'minutes': positiveInteger(v['minutes']!, allowZero: true),
    'reason': v['reason'],
  },
  help:
      'El tiempo trabajado permanece intacto. Las esperas no se cobran automáticamente.',
);
Future<Map<String, dynamic>?> qualityDialog(BuildContext context) => formDialog(
  context,
  'Comprobación final del técnico',
  [
    const FieldSpec(
      'result',
      'Trabajo comprobado y resultado',
      multiline: true,
    ),
    const FieldSpec(
      'pendingSymptoms',
      'Síntomas o recomendaciones pendientes',
      required: false,
      multiline: true,
    ),
  ],
  (v) => {'result': v['result'], 'pendingSymptoms': v['pendingSymptoms']},
  help:
      'Confirma el resultado de la intervención. Las recomendaciones pendientes no son trabajos autorizados.',
);

Future<Map<String, String>?> replacementCredentials(
  BuildContext context, {
  bool replacing = true,
}) async {
  final email = TextEditingController(), password = TextEditingController();
  final result = await showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        replacing
            ? 'Iniciar sesión para sustituir el dispositivo'
            : 'Revalidar tu cuenta',
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Utiliza la misma cuenta. El equipo anterior seguirá retirado y el nuevo tendrá una identidad distinta.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Correo electrónico',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, {
            'email': email.text.trim(),
            'password': password.text,
          }),
          child: const Text('Revalidar y sustituir'),
        ),
      ],
    ),
  );
  // Let the dialog finish its exit animation before releasing field controllers.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  email.dispose();
  password.dispose();
  return result;
}
