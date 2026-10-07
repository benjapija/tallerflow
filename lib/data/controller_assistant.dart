part of 'controller.dart';

extension ReviewedAssistant on WorkshopController {
  void _validateAssistantRecords(List<Map<String, dynamic>> records) {
    final ids = <String>{};
    for (final r in records) {
      if (r['id'] is! String ||
          !ids.add(r['id']) ||
          r['actorId'] != actor.id ||
          r['deviceId'] is! String ||
          r['orderId'] is! String ||
          r['request'] is! Map ||
          ![
            'pending',
            'completed',
            'uncertain',
            'reviewed',
            'archived',
          ].contains(r['status']) ||
          (r['request'] as Map).keys.any(
            (k) => ![
              'action',
              'orderId',
              'requestId',
              'revision',
              'mode',
              'question',
              'identity',
              'identityConfirmed',
              'privacyConfirmed',
              'sourceIds',
            ].contains(k),
          ) ||
          r['request']['requestId'] != r['id'] ||
          r['request']['orderId'] != r['orderId'] ||
          !['technical', 'office'].contains(r['request']['mode']) ||
          r['request']['revision'] is! int ||
          r['request']['privacyConfirmed'] != true ||
          r['request']['sourceIds'] is! List ||
          (r['request']['sourceIds'] as List).isEmpty ||
          (r['request']['sourceIds'] as List).length > 20 ||
          (r['request']['sourceIds'] as List).any((x) => x is! String) ||
          jsonEncode(r).length > 64000) {
        throw const RuleException(
          'Consulta del asistente incompatible en la copia',
        );
      }
    }
  }

  Future<void> _assistantReady(String orderId, String mode) async {
    _checkAccess();
    _checkOnline();
    if (outbox.isNotEmpty || pendingCommands.isNotEmpty || hasPendingPhotos) {
      throw const RuleException(
        'Sincroniza los registros y fotografías antes de consultar',
      );
    }
    await _refresh();
    final order = state.orders[orderId];
    if (order == null ||
        (!actor.isOffice && !order.assigned(actor.id)) ||
        (mode == 'office' && !actor.isOffice) ||
        !['office', 'technical'].contains(mode)) {
      throw const RuleException(
        'Selecciona una orden asignada y un perfil autorizado',
      );
    }
  }

  Future<Map<String, dynamic>> previewAssistant(String orderId, String mode) =>
      _locked(() async {
        await _assistantReady(orderId, mode);
        return remote!.assistant({
          'action': 'preview',
          'orderId': orderId,
          'mode': mode,
        });
      });

  Future<Map<String, dynamic>> requestAssistant(
    String orderId,
    Map<String, dynamic> input,
  ) => _locked(() async {
    final mode = input['mode'] as String;
    await _assistantReady(orderId, mode);
    if (assistantRecords.any(
      (r) => r['orderId'] == orderId && r['status'] == 'pending',
    )) {
      throw const RuleException(
        'Recupera o archiva la consulta pendiente antes de enviar otra',
      );
    }
    final request = cloneMap({
      ...input,
      'action': 'draft',
      'orderId': orderId,
      'requestId': const Uuid().v4(),
    });
    if (request['revision'] != state.orders[orderId]!.revision ||
        request['privacyConfirmed'] != true) {
      throw const RuleException(
        'Revisa las fuentes actuales y los datos personales',
      );
    }
    final record = <String, dynamic>{
      'id': request['requestId'],
      'actorId': actor.id,
      'deviceId': deviceId,
      'orderId': orderId,
      'request': request,
      'status': 'pending',
      'at': clock().toUtc().toIso8601String(),
    };
    _validateAssistantRecords([...assistantRecords, record]);
    assistantRecords.add(record);
    try {
      await _persist();
    } catch (_) {
      assistantRecords.remove(record);
      rethrow;
    }
    notifyListeners();
    // A network interruption retains this exact identity. Recovery only
    // reads the saved server response and never resubmits provider work.
    final result = await remote!.assistant(request);
    final updated = cloneMap(record);
    _acceptAssistantResult(updated, result);
    await _saveAssistantRecord(record, updated);
    return cloneMap(record);
  });

  Future<void> _saveAssistantRecord(
    Map<String, dynamic> record,
    Map<String, dynamic> updated,
  ) async {
    final previous = cloneMap(record);
    record
      ..clear()
      ..addAll(updated);
    try {
      await _persist();
    } catch (_) {
      record
        ..clear()
        ..addAll(previous);
      rethrow;
    }
    notifyListeners();
  }

  void _acceptAssistantResult(
    Map<String, dynamic> record,
    Map<String, dynamic> result,
  ) {
    if (result['state'] == 'completed') {
      if (result['reviewRequired'] != true ||
          result['draft'] is! Map ||
          result['sources'] is! List ||
          result['sourceRevision'] != record['request']['revision'] ||
          result['mode'] != record['request']['mode']) {
        throw const RuleException(
          'El borrador no conserva sus fuentes originales',
        );
      }
      record['status'] = 'completed';
      record['result'] = cloneMap(result);
    } else if (result['state'] == 'uncertain') {
      record['status'] = 'uncertain';
      record['result'] = cloneMap(result);
    }
  }

  Future<void> recoverAssistant(String id) => _locked(() async {
    final record = assistantRecords.firstWhere((r) => r['id'] == id);
    await _assistantReady(record['orderId'], record['request']['mode']);
    if (record['deviceId'] != deviceId || record['actorId'] != actor.id) {
      throw const RuleException(
        'La consulta pertenece a la identidad original del dispositivo',
      );
    }
    final result = await remote!.assistant({
      'action': 'receipt',
      'orderId': record['orderId'],
      'requestId': id,
      'mode': record['request']['mode'],
    });
    final updated = cloneMap(record);
    _acceptAssistantResult(updated, result);
    await _saveAssistantRecord(record, updated);
  });

  Future<void> reviewAssistant(String id, String text) => _locked(() async {
    final record = assistantRecords.firstWhere((r) => r['id'] == id);
    await _assistantReady(record['orderId'], record['request']['mode']);
    if (record['status'] != 'completed' ||
        text.trim().isEmpty ||
        text.length > 4000 ||
        record['result']['sourceRevision'] !=
            state.orders[record['orderId']]!.revision) {
      throw const RuleException(
        'Actualiza y revisa el borrador y sus fuentes antes de usarlo',
      );
    }
    final current = await remote!.assistant({
      'action': 'preview',
      'orderId': record['orderId'],
      'mode': record['request']['mode'],
    });
    final selected = (record['result']['sources'] as List);
    final originals = (current['sources'] as List);
    if (current['revision'] != record['result']['sourceRevision'] ||
        selected.any(
          (s) => !originals.any((x) => jsonEncode(x) == jsonEncode(s)),
        )) {
      throw const RuleException(
        'Una fuente cambió. Revisa los originales antes de usar el borrador',
      );
    }
    final updated = cloneMap(record);
    updated['review'] = {
      'text': text.trim(),
      'actorId': actor.id,
      'at': clock().toUtc().toIso8601String(),
    };
    updated['status'] = 'reviewed';
    await _saveAssistantRecord(record, updated);
  });

  Future<void> archiveAssistant(String id, String reason) => _locked(() async {
    _checkAccess();
    if (reason.trim().isEmpty) {
      throw const RuleException('Indica el motivo de archivo');
    }
    final r = assistantRecords.firstWhere((r) => r['id'] == id);
    final updated = cloneMap(r);
    updated['archivedFrom'] = r['status'];
    updated['status'] = 'archived';
    updated['archiveReason'] = reason.trim();
    await _saveAssistantRecord(r, updated);
  });
}
