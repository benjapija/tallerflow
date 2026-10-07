import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../data/controller.dart';
import '../domain/models.dart';
import 'dialogs.dart';
import '../domain/capture_draft.dart';
import '../domain/fiscal_profile.dart';

class ManagementPanel extends StatefulWidget {
  final WorkshopController controller;
  const ManagementPanel({super.key, required this.controller});
  @override
  State<ManagementPanel> createState() => _ManagementPanelState();
}

class _ManagementPanelState extends State<ManagementPanel> {
  WorkshopController get c => widget.controller;
  String? message;
  bool busy = false;
  Future<void> save(String action, Map<String, dynamic>? p) async {
    if (p == null) return;
    setState(() => busy = true);
    try {
      await c.manage(action, p);
      if (mounted) {
        setState(
          () => message = 'Cambio guardado y registrado en la auditoría.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String amount(int cents) =>
      (cents / 100).toStringAsFixed(2).replaceAll('.', ',');
  Future<void> newAccount() async {
    final prior = c.pendingAccountCreation?['payload'] as Map?;
    final retry = prior != null;
    final p = await formDialog(
      context,
      retry ? 'Reintentar cuenta pendiente' : 'Crear cuenta del taller',
      [
        FieldSpec(
          'name',
          'Nombre',
          initial: prior?['name'] ?? '',
          readOnly: retry,
        ),
        FieldSpec(
          'email',
          'Correo electrónico',
          initial: prior?['email'] ?? '',
          readOnly: retry,
        ),
        FieldSpec(
          'role',
          'Perfil',
          initial: prior?['role'] ?? 'technician',
          readOnly: retry,
          choices: {for (final r in Role.values) r.name: roleLabels[r.index]},
        ),
        FieldSpec(
          'prices',
          'Acceso adicional a precios',
          initial: prior?['seePrices'] == true ? 'yes' : 'no',
          readOnly: retry,
          choices: const {
            'no': 'Sin acceso adicional',
            'yes': 'Puede consultar precios',
          },
        ),
        FieldSpec(
          'costs',
          'Acceso adicional a costes',
          initial: prior?['seeCosts'] == true ? 'yes' : 'no',
          readOnly: retry,
          choices: const {
            'no': 'Sin acceso adicional',
            'yes': 'Puede consultar costes',
          },
        ),
        FieldSpec(
          'reason',
          'Motivo del alta',
          initial: prior?['reason'] ?? '',
          multiline: true,
          readOnly: retry,
        ),
        const FieldSpec(
          'password',
          'Contraseña nueva · mínimo 12 caracteres',
          obscure: true,
        ),
        const FieldSpec('confirm', 'Repite la contraseña', obscure: true),
      ],
      (v) {
        if (v['password'] != v['confirm'] ||
            v['password']!.length < 12 ||
            v['password']!.length > 1024) {
          throw const FormatException(
            'Repite la misma contraseña de entre 12 y 1024 caracteres',
          );
        }
        return {
          'name': v['name'],
          'email': v['email'],
          'role': v['role'],
          'seePrices': v['prices'] == 'yes',
          'seeCosts': v['costs'] == 'yes',
          'reason': v['reason'],
          'password': v['password'],
        };
      },
      help: retry
          ? 'Se recupera la misma solicitud. Si la cuenta ya se creó, conserva su contraseña original; este reintento no la cambia.'
          : 'Entrega las credenciales a la persona por un canal acordado. El alta no envía correos. La contraseña se transmite al servicio de acceso y no se guarda en TallerFlow.',
    );
    if (p == null) return;
    final password = p.remove('password') as String;
    setState(() => busy = true);
    try {
      await c.createMember(p, password);
      if (mounted) {
        setState(() => message = 'Cuenta creada y vinculada al taller.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'La solicitud se conserva. Comprueba la conexión, los permisos y que el correo no pertenezca a otra cuenta antes de reintentar.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> archiveAccount() async {
    final reason = await textDialog(
      context,
      'Archivar solicitud pendiente',
      'Motivo de la revisión',
      help:
          'Se conserva la solicitud para revisión. Archivar no borra ninguna cuenta que ya se haya creado ni cambia sus credenciales.',
    );
    if (reason == null) return;
    await c.archiveAccountCreation(reason);
    if (mounted) {
      setState(
        () => message = 'Solicitud conservada en el historial de recuperación.',
      );
    }
  }

  Future<void> settings() async {
    final s = c.state.settings;
    final p = await formDialog(
      context,
      'Tarifas e impuestos',
      [
        FieldSpec(
          'rate',
          'Tarifa general por hora (€)',
          initial: amount(s['hourlyRateCents'] ?? 0),
          numeric: true,
        ),
        FieldSpec(
          'tax',
          'Impuesto habitual (%)',
          initial: amount(s['taxBps'] ?? 0),
          numeric: true,
        ),
        FieldSpec(
          'cost',
          'Coste interno estimado por hora (€)',
          initial: amount(s['internalHourlyCostCents'] ?? 0),
          numeric: true,
        ),
        FieldSpec(
          'known',
          '¿Coste interno contrastado por el taller?',
          initial: s['internalCostKnown'] == true ? 'yes' : 'no',
          choices: const {
            'no': 'Pendiente de confirmar',
            'yes': 'Sí, dato contrastado',
          },
        ),
        const FieldSpec('reason', 'Motivo del cambio', multiline: true),
      ],
      (v) => {
        'settings': {
          'hourlyRateCents': parseMoney(v['rate']!),
          'taxBps': parseMoney(v['tax']!),
          'internalHourlyCostCents': parseMoney(v['cost']!),
          'internalCostKnown': v['known'] == 'yes',
        },
        'reason': v['reason'],
      },
      help:
          'Se aplicarán a los registros nuevos. Los trabajos y documentos anteriores conservan sus importes. La configuración fiscal requiere una validación específica antes del piloto.',
    );
    await save('settings_save', p);
  }

  Future<void> fiscalProfile() async {
    final current = c.state.settings['fiscalProfile'] ?? initialFiscalProfile();
    final p = await formDialog(
      context,
      'Preparación fiscal del taller',
      [
        for (final field in fiscalChoices.keys)
          FieldSpec(
            field,
            fiscalFieldLabels[field]!,
            initial: current[field] ?? 'unknown',
            choices: fiscalChoices[field],
          ),
        const FieldSpec('reason', 'Motivo del cambio', multiline: true),
      ],
      (values) => {
        'profile': validateFiscalProfile({
          'country': 'ES',
          for (final field in fiscalChoices.keys) field: values[field],
        }),
        'reason': values['reason'],
      },
      help:
          'Cada taller configura sus propias opciones. Puedes dejar los datos pendientes. Esta preparación no activa facturación ni envíos fiscales, no calcula obligaciones y no cambia tarifas ni documentos anteriores. Las notas siguen siendo documentos de trabajo hasta validar el circuito aplicable.',
    );
    await save('fiscal_profile_save', p);
  }

  Future<void> member(Actor m) async {
    final p = await formDialog(
      context,
      'Permisos de ${m.name}',
      [
        FieldSpec('name', 'Nombre', initial: m.name),
        FieldSpec(
          'role',
          'Perfil',
          initial: m.role.name,
          choices: {for (final r in Role.values) r.name: roleLabels[r.index]},
        ),
        FieldSpec(
          'active',
          'Acceso al taller',
          initial: m.active ? 'yes' : 'no',
          choices: const {'yes': 'Activo', 'no': 'Desactivado'},
        ),
        FieldSpec(
          'prices',
          'Acceso a precios',
          initial: m.seePrices ? 'yes' : 'no',
          choices: const {
            'no': 'Sin acceso adicional',
            'yes': 'Puede consultar precios',
          },
        ),
        FieldSpec(
          'costs',
          'Acceso a costes',
          initial: m.seeCosts ? 'yes' : 'no',
          choices: const {
            'no': 'Sin acceso adicional',
            'yes': 'Puede consultar costes',
          },
        ),
        const FieldSpec('reason', 'Motivo del cambio', multiline: true),
      ],
      (v) => {
        'userId': m.id,
        'name': v['name'],
        'role': v['role'],
        'active': v['active'] == 'yes',
        'seePrices': v['prices'] == 'yes',
        'seeCosts': v['costs'] == 'yes',
        'reason': v['reason'],
      },
      help:
          'Oficina consulta precios. El administrador consulta costes. Los permisos adicionales permiten ampliar las consultas de un operario. Se conserva al menos un administrador activo.',
    );
    await save('member_save', p);
  }

  Future<void> catalog(CatalogItem? item) async {
    final s = c.state.settings;
    final p = await formDialog(
      context,
      item == null ? 'Nueva referencia' : 'Editar referencia',
      [
        FieldSpec(
          'reference',
          'Referencia',
          initial: item?.reference ?? '',
          capture: CaptureKind.reference,
        ),
        FieldSpec(
          'description',
          'Descripción',
          initial: item?.description ?? '',
        ),
        FieldSpec('unit', 'Unidad de consumo', initial: item?.unit ?? 'ud'),
        FieldSpec(
          'supplier',
          'Proveedor habitual',
          initial: item?.supplier ?? '',
          required: false,
        ),
        FieldSpec(
          'price',
          'Precio de venta sin impuesto (€)',
          initial: amount(item?.priceCents ?? 0),
          numeric: true,
        ),
        FieldSpec(
          'cost',
          'Coste de compra por unidad (€)',
          initial: amount(item?.costCents ?? 0),
          numeric: true,
        ),
        FieldSpec(
          'known',
          '¿Coste de compra conocido?',
          initial: item?.costKnown == true ? 'yes' : 'no',
          choices: const {
            'no': 'Pendiente de conocer',
            'yes': 'Coste conocido',
          },
        ),
        FieldSpec(
          'tax',
          'Impuesto (%)',
          initial: amount(item?.taxBps ?? s['taxBps'] ?? 2100),
          numeric: true,
        ),
        FieldSpec(
          'stock',
          'Existencias disponibles',
          initial: quantity(item == null ? 0 : c.state.stock(item.id)),
          numeric: true,
        ),
        FieldSpec(
          'minimum',
          'Existencias mínimas',
          initial: quantity(item?.minMilli ?? 0),
          numeric: true,
        ),
        FieldSpec(
          'active',
          'Estado',
          initial: item?.active == false ? 'no' : 'yes',
          choices: const {'yes': 'Disponible', 'no': 'Desactivada'},
        ),
        const FieldSpec(
          'reason',
          'Motivo del cambio o ajuste de existencias',
          multiline: true,
        ),
      ],
      (v) => {
        'item': {
          'id': item?.id ?? const Uuid().v4(),
          'reference': v['reference'],
          'description': v['description'],
          'unit': v['unit'],
          'supplier': v['supplier'],
          'priceCents': parseMoney(v['price']!),
          'costCents': parseMoney(v['cost']!),
          'costKnown': v['known'] == 'yes',
          'taxBps': parseMoney(v['tax']!),
          'stockMilli': zeroQuantity(v['stock']!),
          'minMilli': zeroQuantity(v['minimum']!),
          'active': v['active'] == 'yes',
        },
        'reason': v['reason'],
      },
      help:
          'El ajuste mantiene el historial de movimientos. Los consumos anteriores conservan su precio y coste. Para cantidades decimales utiliza coma o punto.',
    );
    await save('catalog_save', p);
  }

  Future<void> template(Map<String, dynamic>? source) async {
    final v = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TemplateEditor(
        source: source,
        catalog: c.state.catalog.where((i) => i.active).toList(),
      ),
    );
    await save('template_save', v);
  }

  @override
  Widget build(BuildContext context) {
    if (c.actor.role != Role.admin) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Administración del taller',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const Text(
              'Los cambios requieren un motivo y quedan registrados. Cada persona utiliza su propia cuenta y sus permisos.',
            ),
            if (busy) const LinearProgressIndicator(),
            if (message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(message!),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: busy || c.demo || c.offline ? null : newAccount,
                  child: Text(
                    c.pendingAccountCreation == null
                        ? 'Crear cuenta'
                        : 'Reintentar cuenta pendiente',
                  ),
                ),
                if (c.pendingAccountCreation != null)
                  TextButton(
                    onPressed: busy ? null : archiveAccount,
                    child: const Text('Archivar solicitud'),
                  ),
                OutlinedButton(
                  onPressed: busy ? null : settings,
                  child: const Text('Tarifas e impuestos'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : fiscalProfile,
                  child: const Text('Preparación fiscal'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : () => catalog(null),
                  child: const Text('Nueva referencia'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : () => template(null),
                  child: const Text('Nueva plantilla'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Cuentas y permisos',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            for (final m in c.state.members)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(m.name),
                subtitle: Text(
                  '${roleLabels[m.role.index]} · ${m.active ? 'Activo' : 'Desactivado'}',
                ),
                trailing: TextButton(
                  onPressed: busy ? null : () => member(m),
                  child: const Text('Permisos'),
                ),
              ),
            ExpansionTile(
              title: const Text('Catálogo'),
              children: [
                for (final i in c.state.catalog)
                  ListTile(
                    title: Text('${i.reference} · ${i.description}'),
                    subtitle: Text(
                      '${quantity(c.state.stock(i.id))} ${i.unit} · ${money(i.priceCents)} · ${i.active ? 'Disponible' : 'Desactivada'}',
                    ),
                    trailing: TextButton(
                      onPressed: busy ? null : () => catalog(i),
                      child: const Text('Editar'),
                    ),
                  ),
              ],
            ),
            ExpansionTile(
              title: const Text('Plantillas de trabajo'),
              children: [
                if (c.state.templates.isEmpty)
                  const ListTile(
                    title: Text('Todavía no hay plantillas configuradas.'),
                  ),
                for (final t in c.state.templates)
                  ListTile(
                    title: Text(t['name']),
                    subtitle: Text(
                      'Versión ${t['version']} · ${(t['tasks'] as List).length} tareas',
                    ),
                    trailing: TextButton(
                      onPressed: busy ? null : () => template(t),
                      child: const Text('Editar'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

int zeroQuantity(String value) =>
    RegExp(r'^0([.,]0{1,3})?$').hasMatch(value.trim())
    ? 0
    : parseQuantity(value);

class TemplateEditor extends StatefulWidget {
  final Map<String, dynamic>? source;
  final List<CatalogItem> catalog;
  const TemplateEditor({super.key, this.source, required this.catalog});
  @override
  State<TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<TemplateEditor> {
  late final name = TextEditingController(text: widget.source?['name'] ?? '');
  late final vehicle = TextEditingController(
    text: widget.source?['vehicleRule'] ?? '',
  );
  late final engine = TextEditingController(
    text: widget.source?['engineRule'] ?? '',
  );
  final reason = TextEditingController();
  late final tasks = <Map<String, dynamic>>[
    for (final t in widget.source?['tasks'] ?? [])
      cloneMap(Map<String, dynamic>.from(t)),
  ];
  late bool active = widget.source?['active'] != false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    vehicle.dispose();
    engine.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> task([int? index]) async {
    final old = index == null ? null : tasks[index];
    final v = await formDialog(
      context,
      'Tarea de plantilla',
      [
        FieldSpec('title', 'Descripción', initial: old?['title'] ?? ''),
        FieldSpec(
          'estimate',
          'Minutos estimados',
          initial: '${old?['estimateMinutes'] ?? 30}',
          numeric: true,
        ),
      ],
      (v) => {
        'title': v['title'],
        'estimateMinutes': positiveInteger(v['estimate']!),
        'references': old?['references'] ?? [],
      },
    );
    if (v != null && mounted) {
      setState(() {
        if (index == null) {
          tasks.add(v);
        } else {
          tasks[index] = v;
        }
      });
    }
  }

  Future<void> reference(int index) async {
    if (widget.catalog.isEmpty) {
      setState(() => error = 'Añade primero una referencia al catálogo.');
      return;
    }
    final v = await formDialog(
      context,
      'Referencia prevista',
      [
        FieldSpec(
          'item',
          'Referencia',
          initial: widget.catalog.first.id,
          choices: {
            for (final c in widget.catalog)
              c.id: '${c.reference} · ${c.description}',
          },
        ),
        const FieldSpec(
          'quantity',
          'Cantidad en la unidad de consumo',
          initial: '1',
          numeric: true,
        ),
      ],
      (v) => {
        'itemId': v['item'],
        'quantityMilli': parseQuantity(v['quantity']!),
      },
    );
    if (v != null && mounted) {
      setState(() => (tasks[index]['references'] as List).add(v));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Plantilla de trabajo'),
    content: SizedBox(
      width: 580,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(
                labelText: 'Nombre de plantilla',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: vehicle,
              decoration: const InputDecoration(
                labelText: 'Vehículos compatibles · orientación para revisión',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: engine,
              decoration: const InputDecoration(
                labelText: 'Motores compatibles · orientación para revisión',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Plantilla disponible'),
              value: active,
              onChanged: (v) => setState(() => active = v),
            ),
            const Text(
              'La aplicación pedirá confirmar compatibilidad y creará tareas pendientes de autorización. Las referencias previstas no consumen existencias ni se cobran.',
            ),
            for (var i = 0; i < tasks.length; i++)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${i + 1}. ${tasks[i]['title']} · ${tasks[i]['estimateMinutes']} min',
                      ),
                      Wrap(
                        children: [
                          TextButton(
                            onPressed: () => task(i),
                            child: const Text('Editar tarea'),
                          ),
                          TextButton(
                            onPressed: () => reference(i),
                            child: const Text('Añadir referencia'),
                          ),
                          TextButton(
                            onPressed: () => setState(() => tasks.removeAt(i)),
                            child: const Text('Quitar tarea'),
                          ),
                        ],
                      ),
                      for (final r in tasks[i]['references'])
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${widget.catalog.where((c) => c.id == r['itemId']).firstOrNull?.reference ?? 'Referencia no disponible'} · ${quantity(r['quantityMilli'])}',
                          ),
                          trailing: IconButton(
                            tooltip: 'Quitar referencia',
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(
                              () => (tasks[i]['references'] as List).remove(r),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            TextButton.icon(
              onPressed: () => task(),
              icon: const Icon(Icons.add),
              label: const Text('Añadir tarea'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Motivo de creación o cambio',
              ),
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
          if (name.text.trim().isEmpty ||
              reason.text.trim().isEmpty ||
              tasks.isEmpty) {
            setState(
              () => error = 'Completa nombre, motivo y al menos una tarea.',
            );
            return;
          }
          Navigator.pop(context, {
            'template': {
              'id': widget.source?['id'] ?? const Uuid().v4(),
              'name': name.text.trim(),
              'active': active,
              'vehicleRule': vehicle.text.trim(),
              'engineRule': engine.text.trim(),
              'tasks': tasks,
            },
            'reason': reason.text.trim(),
          });
        },
        child: const Text('Guardar plantilla'),
      ),
    ],
  );
}
