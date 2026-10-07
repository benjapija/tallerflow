import 'engine.dart';
import 'models.dart';
import 'fiscal_profile.dart';

const defaultSettings = <String, dynamic>{
  'hourlyRateCents': 4800,
  'taxBps': 2100,
  'internalHourlyCostCents': 2200,
  'internalCostKnown': false,
};
int boundedInt(dynamic value, int max, String label, {int min = 0}) {
  if (value is! int || value < min || value > max) {
    throw RuleException('$label: valor fuera de rango');
  }
  return value;
}

String requiredText(dynamic value, String label, {int max = 2000}) {
  if (value is! String || value.trim().isEmpty || value.length > max) {
    throw RuleException('$label: completa un texto válido');
  }
  return value.trim();
}

void applyManagement(
  WorkshopState state,
  String id,
  String action,
  Map<String, dynamic> p,
  Actor actor,
  DateTime at,
) {
  if (!actor.active || actor.role != Role.admin) {
    throw const RuleException('Se requiere administrador');
  }
  if (state.applied.contains(id)) return;
  if (p['revision'] != state.managementRevision) {
    throw const RuleException(
      'La configuración ha cambiado. Actualiza y revisa',
    );
  }
  requiredText(p['reason'], 'Motivo');
  final before = cloneMap(state.toJson());
  switch (action) {
    case 'fiscal_profile_save':
      final profile = validateFiscalProfile(p['profile']);
      state.configuration['settings'] = {
        ...state.settings,
        'fiscalProfile': profile,
      };
    case 'settings_save':
      final v = Map<String, dynamic>.from(p['settings']);
      final settings = state.settings;
      for (final k in ['hourlyRateCents', 'internalHourlyCostCents']) {
        settings[k] = boundedInt(v[k], 10000000, k);
      }
      settings['taxBps'] = boundedInt(v['taxBps'], 10000, 'Impuesto');
      if (v['internalCostKnown'] is! bool) {
        throw const RuleException('Confirma si se conoce el coste interno');
      }
      settings['internalCostKnown'] = v['internalCostKnown'];
      state.configuration['settings'] = settings;
    case 'member_save':
      final index = state.members.indexWhere((m) => m.id == p['userId']);
      if (index < 0) {
        throw const RuleException('La cuenta debe existir en el taller');
      }
      final role = Role.values.byName(p['role']);
      if (p['active'] is! bool ||
          p['seePrices'] is! bool ||
          p['seeCosts'] is! bool) {
        throw const RuleException('Permisos inválidos');
      }
      final active = p['active'] == true;
      if ((!active || role != Role.admin) &&
          state.members[index].role == Role.admin &&
          state.members.where((m) => m.active && m.role == Role.admin).length <=
              1) {
        throw const RuleException('Conserva un administrador activo');
      }
      if (!active &&
          state.orders.values
              .expand((o) => o.times)
              .any((t) => t['actorId'] == p['userId'] && t['end'] == null)) {
        throw const RuleException(
          'Pausa o recupera los cronómetros de esta cuenta',
        );
      }
      if (p['seeCosts'] == true &&
          role == Role.technician &&
          p['seePrices'] != true) {
        throw const RuleException('Ver costes requiere acceso a precios');
      }
      state.members[index] = Actor(
        p['userId'],
        requiredText(p['name'], 'Nombre', max: 120),
        role,
        active: active,
        seePrices: p['seePrices'],
        seeCosts: p['seeCosts'],
      );
    case 'catalog_save':
      final j = Map<String, dynamic>.from(p['item']);
      final index = state.catalog.indexWhere((c) => c.id == j['id']);
      final reference = requiredText(j['reference'], 'Referencia', max: 120);
      if (state.catalog.any(
        (c) =>
            c.id != j['id'] &&
            c.reference.toUpperCase() == reference.toUpperCase(),
      )) {
        throw const RuleException('Referencia duplicada');
      }
      final available = boundedInt(j['stockMilli'], 100000000, 'Existencias');
      final old = index < 0 ? null : state.catalog[index];
      final used = old == null ? 0 : old.stockMilli - state.stock(old.id);
      final saved = CatalogItem(
        id: requiredText(j['id'], 'Referencia interna', max: 100),
        reference: reference,
        description: requiredText(j['description'], 'Descripción', max: 300),
        unit: requiredText(j['unit'], 'Unidad', max: 20),
        priceCents: boundedInt(j['priceCents'], 10000000, 'Precio'),
        costCents: boundedInt(j['costCents'], 10000000, 'Coste'),
        stockMilli: available + used,
        minMilli: boundedInt(j['minMilli'], 100000000, 'Mínimo'),
        taxBps: boundedInt(j['taxBps'], 10000, 'Impuesto'),
        active: j['active'] == true,
        costKnown: j['costKnown'] == true,
        supplier: j['supplier'] as String? ?? '',
      );
      if (index < 0) {
        state.catalog.add(saved);
      } else {
        state.catalog[index] = saved;
      }
    case 'template_save':
      final v = cloneMap(Map<String, dynamic>.from(p['template']));
      v['name'] = requiredText(v['name'], 'Nombre de plantilla', max: 120);
      requiredText(v['id'], 'Plantilla interna', max: 100);
      if (v['tasks'] is! List ||
          (v['tasks'] as List).isEmpty ||
          (v['tasks'] as List).length > 40) {
        throw const RuleException('Incluye entre una y cuarenta tareas');
      }
      for (final t in v['tasks']) {
        requiredText(t['title'], 'Tarea', max: 300);
        boundedInt(t['estimateMinutes'], 14400, 'Minutos estimados', min: 1);
        final refs = t['references'] as List? ?? [];
        for (final r in refs) {
          if (!state.catalog.any((c) => c.id == r['itemId'] && c.active)) {
            throw const RuleException(
              'Referencia de plantilla inexistente o desactivada',
            );
          }
          boundedInt(r['quantityMilli'], 10000000, 'Cantidad', min: 1);
        }
      }
      final list = state.templates.toList();
      final index = list.indexWhere((t) => t['id'] == v['id']);
      v['version'] = index < 0 ? 1 : (list[index]['version'] as int) + 1;
      if (index < 0) {
        list.add(v);
      } else {
        list[index] = v;
      }
      state.configuration['templates'] = list;
    default:
      throw const RuleException('Acción de administración desconocida');
  }
  state.configuration['managementRevision'] = state.managementRevision + 1;
  state.applied.add(id);
  state.audit.add({
    'id': id,
    'actorId': actor.id,
    'actor': actor.name,
    'kind': action,
    'at': at.toUtc().toIso8601String(),
    'reason': p['reason'],
    'payload': cloneMap(p),
    'beforeConfiguration': {
      'settings': before['settings'],
      'members': before['members'],
      'catalog': before['catalog'],
      'templates': before['templates'],
    },
  });
}
