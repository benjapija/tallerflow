part of 'controller.dart';

extension FiscalDraftController on WorkshopController {
  bool get _fiscalVisible =>
      accessAllowed && actor.role == Role.admin && actor.active;
  bool get fiscalDraftsLoaded => _fiscalVisible && _fiscalDraftsLoaded;
  Map<String, dynamic> get fiscalDraftLedger =>
      _fiscalVisible ? cloneMap(_fiscalDraftLedger) : emptyFiscalDraftLedger();
  List<Map<String, dynamic>> get fiscalDraftQueue => _fiscalVisible
      ? WorkshopController._maps(cloneMap({'rows': _fiscalDraftQueue})['rows'])
      : [];
  List<Map<String, dynamic>> get fiscalDraftXmlArtifacts => _fiscalVisible
      ? WorkshopController._maps(
          cloneMap({'rows': _fiscalDraftXmlArtifacts})['rows'],
        )
      : [];
  bool get hasPendingFiscalDrafts =>
      _fiscalDraftQueue.any((r) => r['status'] == 'pending');

  void _requireFiscalAdmin() {
    _checkAccess();
    if (actor.role != Role.admin || !actor.active) {
      throw const RuleException('Se requiere administrador para los ensayos');
    }
  }

  Future<void> _validateFiscalLocal(Map<String, dynamic> local) async {
    final ledger = await validateFiscalDraftLedger(
      local['fiscalDraftLedger'] ?? emptyFiscalDraftLedger(),
      state.workshopId,
    );
    if (local.containsKey('fiscalDraftsLoaded') &&
        local['fiscalDraftsLoaded'] is! bool) {
      throw const RuleException('Estado de ensayo incompatible');
    }
    final ids = <String>{};
    for (final r in WorkshopController._maps(local['fiscalDraftQueue'])) {
      if (r['id'] is! String ||
          !RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ).hasMatch(r['id']) ||
          !ids.add(r['id']) ||
          (!demo && r['actorId'] != local['actor']['id']) ||
          r['deviceId'] is! String ||
          r['deviceId'] != local['deviceId'] &&
              r['sourceDeviceRetained'] != true ||
          !fiscalDraftActions.contains(r['action']) ||
          !{
            'pending',
            'confirmed',
            'rejected',
            'conflict',
            'reviewed',
          }.contains(r['status']) ||
          r['payload'] is! Map ||
          r['createdAt'] is! String ||
          DateTime.tryParse(r['createdAt']) == null ||
          !fiscalDraftSame(
            r['payload'],
            normalizeFiscalDraftPayload(
              r['action'],
              Map<String, dynamic>.from(r['payload']),
            ),
          )) {
        throw const RuleException(
          'Solicitud de ensayo incompatible en la copia',
        );
      }
      if (r['status'] == 'confirmed') {
        final records = fiscalDraftRows(
          ledger['records'],
        ).where((v) => v['id'] == r['id']).toList();
        if (records.length != 1 ||
            !fiscalDraftRecordMatchesCommand(records.single, r) ||
            !fiscalDraftSame(r['result'], _fiscalReceipt(records.single))) {
          throw const RuleException(
            'Confirmación de ensayo sin original verificable',
          );
        }
      }
      if (r['status'] == 'reviewed' &&
          (r['reviewReason'] is! String ||
              (r['reviewReason'] as String).trim().isEmpty)) {
        throw const RuleException('Revisión de ensayo sin motivo');
      }
    }
    final artifactIds = <String>{};
    final artifacts = WorkshopController._maps(
      local['fiscalDraftXmlArtifacts'],
    );
    for (final a in artifacts) {
      final originals = fiscalDraftRows(
        ledger['records'],
      ).where((r) => r['id'] == a['recordId']).toList();
      if (originals.length != 1 ||
          !artifactIds.add('${a['recordId']}|${a['generatorVersion']}')) {
        throw const RuleException('XML de ensayo sin original o repetido');
      }
      await validateFiscalDraftXmlStoredArtifact(
        a,
        confirmedRecord: originals.single,
      );
      if (a['previousXmlRecordId'] != null) {
        final previous = artifacts
            .where((p) => p['recordId'] == a['previousXmlRecordId'])
            .toList();
        if (previous.length != 1 ||
            previous.single['sequence'] >= a['sequence'] ||
            a['snapshot']['previousXml']['aeatHash'] !=
                previous.single['aeatHash']) {
          throw const RuleException(
            'Predecesor XML de ensayo ausente o incoherente',
          );
        }
      }
    }
  }

  /// Technical settings are explicit sandbox data, never manufacturer approval
  /// or a real fiscal identity. Confirmed snapshots are saved atomically once.
  Future<Map<String, dynamic>> generateFiscalDraftXml(
    String recordId,
    Map<String, dynamic> technicalSettings,
  ) => _locked(() async {
    _requireFiscalAdmin();
    if (demo || !_fiscalDraftsLoaded) {
      throw const RuleException(
        'Selecciona un registro confirmado por el servidor para generar el XML de ensayo',
      );
    }
    final records = fiscalDraftRows(_fiscalDraftLedger['records']);
    final target = records
        .where((r) => r['id'] == recordId && r['kind'] == 'draft')
        .firstOrNull;
    if (target == null) {
      throw const RuleException(
        'El registro de ensayo todavía no está confirmado',
      );
    }
    final existing = _fiscalDraftXmlArtifacts
        .where((a) => a['recordId'] == recordId)
        .firstOrNull;
    if (existing != null) {
      await validateFiscalDraftXmlStoredArtifact(
        existing,
        confirmedRecord: target,
      );
      return cloneMap(existing);
    }
    if (technicalSettings.keys.any(
          (k) => !{
            'issuerName',
            'manufacturerName',
            'manufacturerNif',
            'name',
            'id',
            'version',
            'installation',
            'onlyVerifactu',
            'canHaveMultipleTaxpayers',
            'hasMultipleTaxpayers',
            'dateValidationZone',
          }.contains(k),
        ) ||
        [
          'onlyVerifactu',
          'canHaveMultipleTaxpayers',
          'hasMultipleTaxpayers',
        ].any((k) => technicalSettings[k] is! bool)) {
      throw const RuleException('Identificación técnica del ensayo incompleta');
    }
    final input = cloneMap(technicalSettings);
    VerifactuParty issuer;
    VerifactuSystem system;
    Map<String, dynamic> preparation;
    String zone;
    final savedChain = _fiscalDraftXmlArtifacts
        .where(
          (a) =>
              a['snapshot']['sourceRecord']['issuer_nif'] ==
                  target['issuer_nif'] &&
              a['snapshot']['sourceRecord']['installation'] ==
                  target['installation'],
        )
        .toList();
    if (savedChain.isNotEmpty) {
      // New records extend the technical projection with the SAME preserved
      // settings. Changing today's profile never regenerates old documents.
      final snapshot = savedChain.first['snapshot'],
          source = snapshot['system'];
      final preserved = {
        'issuerName': snapshot['issuer']['name'],
        'manufacturerName': source['manufacturer']['name'],
        'manufacturerNif': source['manufacturer']['nif'],
        'name': source['name'],
        'id': source['id'],
        'version': source['version'],
        'installation': source['installation'],
        'onlyVerifactu': source['onlyVerifactu'],
        'canHaveMultipleTaxpayers': source['canHaveMultipleTaxpayers'],
        'hasMultipleTaxpayers': source['hasMultipleTaxpayers'],
      };
      final comparable = cloneMap(input)..remove('dateValidationZone');
      if (!fiscalDraftSame(comparable, preserved) ||
          (input.containsKey('dateValidationZone') &&
              input['dateValidationZone'] != snapshot['dateValidationZone'])) {
        throw const RuleException(
          'Esta cadena conserva su identificación técnica; utiliza los mismos datos para continuar el ensayo',
        );
      }
      preparation = cloneMap(
        Map<String, dynamic>.from(snapshot['preparation']),
      );
      zone = snapshot['dateValidationZone'];
    } else {
      preparation = cloneMap(
        Map<String, dynamic>.from(state.settings['fiscalProfile']),
      );
      zone =
          input['dateValidationZone'] ??
          (preparation['territory'] == 'canary'
              ? 'Atlantic/Canary'
              : 'Europe/Madrid');
    }
    issuer = VerifactuParty(
      name: input['issuerName'],
      nif: target['issuer_nif'],
    );
    system = VerifactuSystem(
      manufacturer: VerifactuParty(
        name: input['manufacturerName'],
        nif: input['manufacturerNif'],
      ),
      name: input['name'],
      id: input['id'],
      version: input['version'],
      installation: input['installation'],
      onlyVerifactu: input['onlyVerifactu'],
      canHaveMultipleTaxpayers: input['canHaveMultipleTaxpayers'],
      hasMultipleTaxpayers: input['hasMultipleTaxpayers'],
    );
    final chainRecords =
        records
            .where(
              (r) =>
                  r['issuer_nif'] == target['issuer_nif'] &&
                  r['installation'] == target['installation'],
            )
            .toList()
          ..sort((a, b) => (a['sequence'] as int).compareTo(b['sequence']));
    final chain = await FiscalDraftXmlChain.generateGeneralRegime(
      confirmedRecords: chainRecords,
      preparation: preparation,
      issuer: issuer,
      system: system,
      dateValidationZone: zone,
    );
    final next = _fiscalDraftXmlArtifacts.toList();
    for (final artifact in chain.artifacts) {
      final saved = next
          .where((a) => a['recordId'] == artifact.recordId)
          .firstOrNull;
      final value = artifact.toJson();
      if (saved != null) {
        if (!fiscalDraftSame(saved, value)) {
          throw const RuleException(
            'La proyección nueva no coincide con el XML original conservado',
          );
        }
      } else {
        next.add(value);
      }
    }
    final before = _fiscalDraftXmlArtifacts;
    _fiscalDraftXmlArtifacts = next;
    try {
      await _persist();
    } catch (_) {
      _fiscalDraftXmlArtifacts = before;
      rethrow;
    }
    notifyListeners();
    return cloneMap(next.firstWhere((a) => a['recordId'] == recordId));
  });

  Map<String, dynamic> _fiscalReceipt(Map<String, dynamic> record) => {
    'saved': true,
    'id': record['id'],
    'sequence': record['sequence'],
    'prefix': record['prefix'],
    'number': record['number'],
    'ledgerHash': record['ledger_hash'],
    'emissionEnabled': false,
    'transmissionEnabled': false,
  };

  Future<void> refreshFiscalDrafts() => _locked(() async {
    _requireFiscalAdmin();
    _checkOnline();
    await _refresh();
    _requireFiscalAdmin();
    await _refreshFiscalDraftLedger();
    notifyListeners();
  });

  Future<void> _refreshFiscalDraftLedger() async {
    _requireFiscalAdmin();
    late Map<String, dynamic> raw;
    try {
      raw = await remote!.fiscalDrafts();
    } on PostgrestException catch (e) {
      if (['42501', 'PGRST301', 'PGRST302', 'PGRST303'].contains(e.code)) {
        await _revokeAccess();
      }
      rethrow;
    }
    final ledger = await validateFiscalDraftLedger(raw, state.workshopId);
    final beforeLedger = _fiscalDraftLedger,
        beforeQueue = _fiscalDraftQueue,
        beforeLoaded = _fiscalDraftsLoaded;
    final next = WorkshopController._maps(
      cloneMap({'rows': _fiscalDraftQueue})['rows'],
    );
    final records = fiscalDraftRows(ledger['records']);
    for (final request in next.where((r) => r['status'] == 'pending')) {
      final record = records.where((r) => r['id'] == request['id']).firstOrNull;
      if (record != null) {
        if (!fiscalDraftRecordMatchesCommand(record, request)) {
          request['status'] = 'conflict';
          request['error'] =
              'El identificador tiene otro contenido en el servidor. Conserva ambos originales para revisión.';
        } else {
          request['status'] = 'confirmed';
          request['result'] = _fiscalReceipt(record);
          request.remove('error');
        }
      }
    }
    // Never accept a server view that silently drops an already confirmed original.
    for (final request in next.where((r) => r['status'] == 'confirmed')) {
      final original = records
          .where((r) => r['id'] == request['id'])
          .firstOrNull;
      if (original == null ||
          !fiscalDraftRecordMatchesCommand(original, request)) {
        throw const RuleException(
          'El servidor no conserva un ensayo confirmado de este equipo; revisa la recuperación',
        );
      }
    }
    for (final artifact in _fiscalDraftXmlArtifacts) {
      final original = records
          .where((r) => r['id'] == artifact['recordId'])
          .firstOrNull;
      if (original == null) {
        throw const RuleException(
          'El servidor no conserva el original de un XML de ensayo; revisa la recuperación',
        );
      }
      await validateFiscalDraftXmlStoredArtifact(
        artifact,
        confirmedRecord: original,
      );
    }
    _fiscalDraftLedger = ledger;
    _fiscalDraftQueue = next;
    _fiscalDraftsLoaded = true;
    try {
      await _persist();
    } catch (_) {
      _fiscalDraftLedger = beforeLedger;
      _fiscalDraftQueue = beforeQueue;
      _fiscalDraftsLoaded = beforeLoaded;
      rethrow;
    }
  }

  Future<void> prepareFiscalDraft(
    Map<String, dynamic> payload,
  ) => _locked(() async {
    _requireFiscalAdmin();
    final profile = state.settings['fiscalProfile'];
    if (profile is! Map ||
        profile['sii'] != 'no' ||
        !{
          'common',
          'canary',
          'ceuta',
          'melilla',
        }.contains(profile['territory'])) {
      throw const RuleException(
        'Revisa la preparación fiscal: este ensayo no cubre SII ni territorios forales o desconocidos',
      );
    }
    final p = normalizeFiscalDraftPayload(
      'fiscal_draft_append',
      payload,
      withExpectation: false,
    );
    await _enqueueFiscalDraft('fiscal_draft_append', p);
  });

  Future<void> withdrawFiscalDraft(String recordId, String reason) => _locked(
    () async {
      _requireFiscalAdmin();
      final records = fiscalDraftRows(_fiscalDraftLedger['records']);
      final original = records
          .where((r) => r['id'] == recordId && r['kind'] == 'draft')
          .firstOrNull;
      if (original == null || records.any((r) => r['target_id'] == recordId)) {
        throw const RuleException(
          'Selecciona un ensayo confirmado que no esté retirado',
        );
      }
      final p = normalizeFiscalDraftPayload('fiscal_draft_withdraw', {
        'issuerNif': original['issuer_nif'],
        'installation': original['installation'],
        'targetId': recordId,
        'reason': reason,
      }, withExpectation: false);
      await _enqueueFiscalDraft('fiscal_draft_withdraw', p);
    },
  );

  Future<void> _enqueueFiscalDraft(
    String action,
    Map<String, dynamic> input,
  ) async {
    if (!demo && !_fiscalDraftsLoaded) {
      throw const RuleException(
        'Actualiza el registro una vez antes de preparar un ensayo sin conexión',
      );
    }
    bool sameChain(Map r) =>
        r['issuer_nif'] == input['issuerNif'] &&
        r['installation'] == input['installation'];
    final head = fiscalDraftRows(
      _fiscalDraftLedger['heads'],
    ).where(sameChain).firstOrNull;
    if (head?['restored'] == true) {
      throw const RuleException(
        'La instalación recuperada está congelada. Prepara una nueva instalación de ensayo',
      );
    }
    if (_fiscalDraftQueue.any(
      (r) =>
          {'pending', 'conflict', 'rejected'}.contains(r['status']) &&
          r['payload']['issuerNif'] == input['issuerNif'] &&
          r['payload']['installation'] == input['installation'],
    )) {
      throw const RuleException(
        'Reconcilia el ensayo pendiente de esta instalación antes de preparar otro',
      );
    }
    final payload = normalizeFiscalDraftPayload(action, {
      ...input,
      'expectedSequence': head?['last_sequence'] ?? 0,
      'expectedHash': head?['last_hash'] ?? '',
    });
    final request = {
      'id': const Uuid().v4(),
      'actorId': actor.id,
      'deviceId': deviceId,
      'action': action,
      'payload': payload,
      'createdAt': clock().toUtc().toIso8601String(),
      'status': 'pending',
    };
    _fiscalDraftQueue.add(request);
    try {
      await _persist();
    } catch (_) {
      _fiscalDraftQueue.remove(request);
      rethrow;
    }
    notifyListeners();
    if (!demo && !offline) {
      try {
        await _drainFiscalDrafts();
      } finally {
        notifyListeners();
      }
    }
  }

  Future<void> retryFiscalDraft(String id) => _locked(() async {
    _requireFiscalAdmin();
    _checkOnline();
    final request = _fiscalDraftQueue.where((r) => r['id'] == id).firstOrNull;
    if (request == null || request['status'] != 'pending') {
      throw const RuleException(
        'Solo se reconcilia una solicitud pendiente sin cambiar su contenido',
      );
    }
    try {
      await _drainFiscalDrafts();
    } finally {
      notifyListeners();
    }
  });

  Future<void> reviewFiscalDraft(String id, String reason) => _locked(() async {
    _requireFiscalAdmin();
    final request = _fiscalDraftQueue.where((r) => r['id'] == id).firstOrNull;
    if (request == null ||
        !{'conflict', 'rejected'}.contains(request['status'])) {
      throw const RuleException(
        'Reconcilia primero cualquier respuesta incierta. Solo se archivan rechazos o conflictos',
      );
    }
    if (reason.trim().isEmpty || reason.length > 2000) {
      throw const RuleException('Indica el motivo de la revisión');
    }
    await _changeFiscalRequest(id, {
      'status': 'reviewed',
      'reviewReason': reason.trim(),
      'reviewedAt': clock().toUtc().toIso8601String(),
      'previousStatus': request['status'],
    });
    notifyListeners();
  });

  Future<void> _changeFiscalRequest(
    String id,
    Map<String, dynamic> update,
  ) async {
    final old = _fiscalDraftQueue;
    final next = WorkshopController._maps(cloneMap({'rows': old})['rows']);
    next.firstWhere((r) => r['id'] == id).addAll(update);
    _fiscalDraftQueue = next;
    try {
      await _persist();
    } catch (_) {
      _fiscalDraftQueue = old;
      rethrow;
    }
  }

  Future<void> _drainFiscalDrafts() async {
    if (demo ||
        offline ||
        actor.role != Role.admin ||
        !hasPendingFiscalDrafts) {
      return;
    }
    _requireFiscalAdmin();
    // Pull first: a lost committed reply can be recovered without replaying it.
    await _refreshFiscalDraftLedger();
    for (final request
        in _fiscalDraftQueue.where((r) => r['status'] == 'pending').toList()) {
      if (request['deviceId'] != deviceId) {
        await _changeFiscalRequest(request['id'], {
          'status': 'conflict',
          'error':
              'Solicitud del dispositivo original recuperado. No se reenvía con una identidad nueva; administración debe contrastar el original.',
        });
        continue;
      }
      var acknowledged = false;
      try {
        final result = await remote!.command(
          request['id'],
          request['action'],
          cloneMap(Map<String, dynamic>.from(request['payload'])),
        );
        acknowledged = true;
        if (result['saved'] != true ||
            result['id'] != request['id'] ||
            result['emissionEnabled'] != false ||
            result['transmissionEnabled'] != false) {
          throw const RuleException(
            'Respuesta de ensayo incompleta: conserva y reconcilia la solicitud',
          );
        }
        await _refreshFiscalDraftLedger();
        final stored = _fiscalDraftQueue.firstWhere(
          (r) => r['id'] == request['id'],
        );
        if (stored['status'] != 'confirmed' ||
            !fiscalDraftSame(stored['result'], result)) {
          throw const RuleException(
            'La respuesta no coincide con el registro confirmado',
          );
        }
      } on PostgrestException catch (e) {
        if (['42501', 'PGRST301', 'PGRST302', 'PGRST303'].contains(e.code)) {
          await _changeFiscalRequest(request['id'], {
            'error':
                'Acceso no validado. Solicitud original conservada: ${e.message}',
          });
          await _revokeAccess();
          rethrow;
        }
        // Transport/gateway errors are uncertain. Only an atomic business or
        // input error from the command, before an acknowledgement, is final.
        if (!acknowledged &&
            (e.code == 'P0001' ||
                e.code?.startsWith('22') == true ||
                e.code?.startsWith('23') == true)) {
          final conflict =
              e.message.toLowerCase().contains('conflict') ||
              e.message.toLowerCase().contains('frozen') ||
              e.message.toLowerCase().contains('reused');
          await _changeFiscalRequest(request['id'], {
            'status': conflict ? 'conflict' : 'rejected',
            'error': e.message,
          });
          continue;
        }
        await _changeFiscalRequest(request['id'], {
          'error':
              'Respuesta incierta; reintenta la misma solicitud. ${e.message}',
        });
        rethrow;
      } catch (e) {
        // Failed local persistence after a commit leaves the saved original
        // pending, so restart and reconciliation recover exactly one result.
        await _changeFiscalRequest(request['id'], {
          'error': 'Confirmación pendiente de recuperar. $e',
        });
        rethrow;
      }
    }
  }
}
