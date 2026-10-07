import 'diagnosis_notebook.dart';
import 'engine.dart';
import 'management.dart';
import 'models.dart';

const caseFields = {
  'title': 'Título técnico',
  'vehicle': 'Marca, modelo y año',
  'engine': 'Motorización',
  'symptom': 'Síntoma',
  'dtcs': 'DTC',
  'checks': 'Comprobaciones y condiciones',
  'result': 'Mediciones y resultado',
  'conclusion': 'Conclusión confirmada',
  'intervention': 'Intervención',
  'verification': 'Verificación',
  'sources': 'Fuentes y referencias autorizadas',
};

List<Map<String, dynamic>> libraryCases(WorkshopState state) =>
    (cloneMap({'rows': state.configuration['caseLibrary'] ?? []})['rows']
            as List)
        .cast<Map<String, dynamic>>();

bool caseEvidenceCurrent(
  WorkshopState state,
  Map<String, dynamic> c,
  Map<String, dynamic> version,
) {
  final order = state.orders[c['sourceOrderId']];
  if (order == null) return c['needsReview'] != true;
  final rows = diagnosisEntries(order);
  for (final link in {
    'conclusionId': 'conclusion',
    'verificationId': 'verification',
  }.entries) {
    final id = version[link.key];
    if (id is! String ||
        !diagnosisEntryActive(rows, id) ||
        !rows.any(
          (e) =>
              e['id'] == id &&
              e['stage'] == link.value &&
              e['confirmed'] == true,
        )) {
      return false;
    }
  }
  return true;
}

/// Other technicians receive only the published technical version, without
/// source order identities, authors, drafts or private review reasons.
List<Map<String, dynamic>> visibleLibrary(WorkshopState state, Actor actor) {
  final result = <Map<String, dynamic>>[];
  for (final c in libraryCases(state)) {
    final versions = (c['versions'] as List).cast<Map<String, dynamic>>();
    final published = versions
        .where((v) => v['version'] == c['activeVersion'])
        .firstOrNull;
    final canEdit = actor.isOffice || c['authorId'] == actor.id;
    if (canEdit) {
      result.add({
        ...c,
        'editable': true,
        'needsReview':
            published != null && !caseEvidenceCurrent(state, c, published),
      });
    } else if (published != null && c['withdrawn'] != true) {
      result.add({
        'id': c['id'],
        'revision': c['revision'],
        'activeVersion': c['activeVersion'],
        'editable': false,
        'needsReview': !caseEvidenceCurrent(state, c, published),
        'versions': [
          {'version': published['version'], 'content': published['content']},
        ],
        'events': [],
        'withdrawn': false,
      });
    }
  }
  return result;
}

void applyCaseCommand(
  WorkshopState state,
  String cid,
  String action,
  Map<String, dynamic> p,
  Actor actor,
  DateTime at,
) {
  if (!actor.active) throw const RuleException('Cuenta desactivada');
  final cases = libraryCases(state);
  final existing = cases.where((c) => c['id'] == p['id']).firstOrNull;
  if (existing != null && !actor.isOffice && existing['authorId'] != actor.id) {
    throw const RuleException('Solo el autor u oficina pueden revisar el caso');
  }
  final revision = existing?['revision'] ?? 0;
  if (p['revision'] is! int || p['revision'] != revision) {
    throw const RuleException('El caso cambió. Sincroniza y revisa su versión');
  }
  final id = requiredText(p['id'], 'Identificador del caso', max: 100);
  final reason = requiredText(p['reason'], 'Motivo de revisión', max: 2000);
  final c =
      existing ??
      {
        'id': id,
        'revision': 0,
        'authorId': actor.id,
        'sourceOrderId': p['sourceOrderId'],
        'versions': <Map<String, dynamic>>[],
        'events': <Map<String, dynamic>>[],
        'activeVersion': null,
        'withdrawn': false,
      };
  final allowed = action == 'case_draft'
      ? [
          'id',
          'revision',
          'sourceOrderId',
          'conclusionId',
          'verificationId',
          'content',
          'reason',
        ]
      : action == 'case_validate'
      ? [
          'id',
          'revision',
          'version',
          'technicalConfirmed',
          'privacyConfirmed',
          'reason',
        ]
      : ['id', 'revision', 'reason'];
  if (p.keys.any((k) => !allowed.contains(k))) {
    throw const RuleException('Campos de caso no admitidos');
  }
  final order = state.orders[c['sourceOrderId']];
  if (order == null || (!actor.isOffice && !order.assigned(actor.id))) {
    throw const RuleException('Se necesita acceso a la orden de origen');
  }
  final versions = (c['versions'] as List).cast<Map<String, dynamic>>();
  int? version;
  if (action == 'case_draft') {
    if (p['sourceOrderId'] != c['sourceOrderId']) {
      throw const RuleException('Conserva la orden de origen');
    }
    if (p['content'] is! Map ||
        (p['content'] as Map).keys.any((k) => k is! String)) {
      throw const RuleException('Contenido técnico requerido');
    }
    final content = Map<String, dynamic>.from(p['content']);
    if (content.keys.any((k) => !caseFields.containsKey(k)) ||
        content.length != caseFields.length) {
      throw const RuleException('Usa únicamente los campos técnicos del caso');
    }
    final clean = <String, dynamic>{};
    for (final key in caseFields.keys) {
      final v = content[key];
      if (v is! String ||
          v.length >
              (['title', 'vehicle', 'engine', 'dtcs'].contains(key)
                  ? 500
                  : 4000)) {
        throw RuleException('Revisa ${caseFields[key]}');
      }
      clean[key] = v.trim();
      if (!['dtcs', 'sources'].contains(key) && clean[key].isEmpty) {
        throw RuleException('Completa ${caseFields[key]}');
      }
    }
    final v = {
      'version': versions.length + 1,
      'content': clean,
      'conclusionId': p['conclusionId'],
      'verificationId': p['verificationId'],
      'actorId': actor.id,
      'at': at.toUtc().toIso8601String(),
    };
    if (!caseEvidenceCurrent(state, c, v)) {
      throw const RuleException(
        'Elige conclusión y verificación vigentes y confirmadas',
      );
    }
    version = v['version'] as int;
    c['versions'] = [...versions, v];
  } else if (action == 'case_validate') {
    if (versions.isEmpty || p['version'] != versions.last['version']) {
      throw const RuleException('Valida el último borrador');
    }
    if (p['technicalConfirmed'] != true || p['privacyConfirmed'] != true) {
      throw const RuleException(
        'Confirma la revisión técnica y la ausencia de datos personales',
      );
    }
    if (!caseEvidenceCurrent(state, c, versions.last)) {
      throw const RuleException('La evidencia de origen necesita revisión');
    }
    version = versions.last['version'];
    c['activeVersion'] = version;
    c['withdrawn'] = false;
  } else if (action == 'case_withdraw') {
    if (existing == null ||
        c['activeVersion'] == null ||
        c['withdrawn'] == true) {
      throw const RuleException('Selecciona un caso publicado vigente');
    }
    c['withdrawn'] = true;
    version = c['activeVersion'];
  } else {
    throw const RuleException('Acción de biblioteca no admitida');
  }
  c['events'] = [
    ...c['events'],
    {
      'id': cid,
      'kind': action,
      'version': version,
      'reason': reason,
      'actorId': actor.id,
      'actorName': actor.name,
      'at': at.toUtc().toIso8601String(),
    },
  ];
  c['revision'] = revision + 1;
  state.configuration['caseLibrary'] = [
    ...cases.where((x) => x['id'] != id),
    c,
  ];
  state.audit.add({
    'id': cid,
    'kind': action,
    'actorId': actor.id,
    'caseId': id,
    'at': at.toUtc().toIso8601String(),
  });
}
