import 'engine.dart';
import 'management.dart';
import 'models.dart';

const diagnosisStages = {
  'symptom': 'Síntoma',
  'hypothesis': 'Hipótesis',
  'test': 'Comprobación propuesta o realizada',
  'result': 'Resultado o medición',
  'conclusion': 'Conclusión confirmada',
  'intervention': 'Intervención registrada',
  'verification': 'Verificación del resultado',
};

List<Map<String, dynamic>> diagnosisEntries(WorkOrder order) =>
    (cloneMap({'rows': order.data['diagnosisNotebook'] ?? []})['rows'] as List)
        .cast<Map<String, dynamic>>();

bool diagnosisEntryActive(List<Map<String, dynamic>> rows, String id) =>
    rows.any((e) => e['id'] == id && e['stage'] != 'withdrawal') &&
    !rows.any((e) => e['replacesId'] == id || e['withdrawsId'] == id);

void applyDiagnosisEntry(WorkOrder order, Operation op, Actor actor) {
  if (!actor.active || (!actor.isOffice && !order.assigned(actor.id))) {
    throw const RuleException(
      'Se requiere una orden asignada o permiso de oficina',
    );
  }
  final p = op.payload, rows = diagnosisEntries(order);
  final withdrawing = op.kind == 'diagnosis_withdraw';
  final allowed = withdrawing
      ? {'sourceId', 'reason'}
      : {
          'stage',
          'text',
          'context',
          'dtcs',
          'source',
          'confirmed',
          'replacesId',
          'reason',
        };
  if (p.keys.any((k) => !allowed.contains(k))) {
    throw const RuleException('Campo de diagnóstico no permitido');
  }
  final sourceId = withdrawing ? p['sourceId'] : p['replacesId'];
  if (withdrawing || sourceId != null) {
    if (op.baseRevision != order.revision) {
      throw const RuleException('El cuaderno cambió. Actualiza y revisa');
    }
    if (sourceId is! String || !diagnosisEntryActive(rows, sourceId)) {
      throw const RuleException(
        'Selecciona una entrada vigente del mismo cuaderno',
      );
    }
    final source = rows.firstWhere((e) => e['id'] == sourceId);
    if (!actor.isOffice && source['actorId'] != actor.id) {
      throw const RuleException(
        'Solo oficina puede revisar entradas de otro operario',
      );
    }
  }
  Map<String, dynamic> entry;
  if (withdrawing) {
    entry = {
      'stage': 'withdrawal',
      'withdrawsId': sourceId,
      'reason': requiredText(p['reason'], 'Motivo de retirada', max: 2000),
    };
  } else {
    if (!diagnosisStages.containsKey(p['stage'])) {
      throw const RuleException('Selecciona el tipo de entrada');
    }
    final confirmed = p['confirmed'] == true;
    if (['conclusion', 'verification'].contains(p['stage']) && !confirmed) {
      throw const RuleException(
        'Confirma personalmente la conclusión o verificación',
      );
    }
    if (p['confirmed'] is! bool) {
      throw const RuleException(
        'Indica si has comprobado personalmente la entrada',
      );
    }
    String optional(String key, int max) {
      final v = p[key] ?? '';
      if (v is! String || v.length > max) throw RuleException('Revisa $key');
      return v.trim();
    }

    entry = {
      'stage': p['stage'],
      'text': requiredText(p['text'], 'Observación', max: 4000),
      'context': optional('context', 2000),
      'dtcs': optional('dtcs', 500),
      'source': optional('source', 2000),
      'confirmed': confirmed,
    };
    if (sourceId != null) {
      entry.addAll({
        'replacesId': sourceId,
        'reason': requiredText(p['reason'], 'Motivo de revisión', max: 2000),
      });
    } else if (p['reason'] != null) {
      throw const RuleException(
        'El motivo de revisión necesita una entrada anterior',
      );
    }
  }
  entry.addAll({
    'id': op.id,
    'actorId': actor.id,
    'actorName': actor.name,
    'actorRole': actor.role.name,
    'at': op.at.toUtc().toIso8601String(),
  });
  order.data['diagnosisNotebook'] = [...rows, entry];
  order.data['quality'] = null;
}
