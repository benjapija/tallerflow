import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../domain/models.dart';
import '../domain/engine.dart';
import '../domain/purchases.dart';
import '../domain/case_library.dart';
import '../domain/portal.dart';
import '../domain/planning.dart';
import '../domain/maintenance.dart';
import '../domain/fleets.dart';
import 'cloud.dart';
import 'demo.dart';
import 'vault.dart';
import 'session_policy.dart';
import 'account_creation.dart';
import '../domain/vehicles.dart';
import '../domain/photos.dart';
import '../domain/csv_import.dart';
import 'photo_blobs.dart';
part 'controller_photos.dart';
part 'controller_photo_backup.dart';

class WorkshopController extends ChangeNotifier {
  final Vault vault;
  final Remote? remote;
  final DateTime Function() clock;
  late WorkshopState state;
  Actor actor;
  String deviceId = const Uuid().v4();
  List<Operation> outbox = [];
  Map<String, String> failures = {};
  Set<String> serverConflicts = {};
  Map<String, dynamic> closeLocks = {};
  List<Map<String, dynamic>> closures = [],
      devices = [],
      pendingCommands = [],
      commandHistory = [];
  DateTime? validatedAt, lastObservedAt;
  List<Map<String, dynamic>> retiredTimers = [];
  Map<String, dynamic>? replacement;
  Map<String, dynamic>? restoredArchive;
  Map<String, dynamic>? pendingAccountCreation;
  List<Map<String, dynamic>> accountCreationHistory = [];
  List<Map<String, dynamic>> photoQueue = [], photoHistory = [];
  Set<String> cachedPhotoHashes = {};
  Map<String, dynamic>? captureTicket;
  bool accessRevoked = false;
  bool _disposed = false;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  bool offline = false, syncing = false;
  String? syncError;
  Future<void> _serial = Future.value();
  WorkshopController(
    this.vault, {
    this.remote,
    this.actor = const Actor(
      'office',
      'Marta Ruiz',
      Role.office,
      seePrices: true,
    ),
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  bool get demo => remote == null;
  bool get accessAllowed =>
      demo ||
      remote?.requiresLease != true ||
      LocalSessionPolicy.valid(
        validatedAt,
        clock().toUtc(),
        revoked:
            accessRevoked ||
            (lastObservedAt != null &&
                clock().toUtc().isBefore(
                  lastObservedAt!.subtract(const Duration(minutes: 2)),
                )),
      );
  bool get prices => actor.isOffice || actor.seePrices;
  bool get costs => actor.role == Role.admin || actor.seeCosts;
  Future<void> changeVehicle(Map<String, dynamic> payload) => _locked(() async {
    _checkAccess();
    if (!actor.isOffice || outbox.isNotEmpty || pendingCommands.isNotEmpty) {
      throw const RuleException(
        'Conecta como oficina y sincroniza los pendientes',
      );
    }
    if (demo) {
      final before = state;
      final next = state.copy();
      applyVehicleChange(
        next,
        const Uuid().v4(),
        payload,
        actor,
        clock().toUtc(),
      );
      state = next;
      try {
        await _persist();
      } catch (_) {
        state = before;
        rethrow;
      }
      notifyListeners();
    } else {
      _checkOnline();
      await _command('vehicle_change', payload);
    }
  });
  Future<void> createMember(
    Map<String, dynamic> input,
    String password,
  ) => _locked(() async {
    _checkAccess();
    _checkOnline();
    if (actor.role != Role.admin ||
        outbox.isNotEmpty ||
        pendingCommands.isNotEmpty) {
      throw const RuleException(
        'Conecta como administrador y sincroniza los registros',
      );
    }
    if (password.length < 12 || password.length > 1024) {
      throw const RuleException(
        'La contraseña debe tener entre 12 y 1024 caracteres',
      );
    }
    final preferences = accountPreferences(input);
    if (pendingAccountCreation != null &&
        !mapEquals(pendingAccountCreation!['payload'], preferences)) {
      throw const RuleException(
        'Reintenta la solicitud pendiente o archívala antes de cambiar los datos',
      );
    }
    if (pendingAccountCreation == null) {
      // Reuse an uncertain archived attempt instead of duplicating its identity.
      final prior = accountCreationHistory
          .where(
            (r) =>
                r['status'] == 'archived' &&
                mapEquals(r['payload'], preferences),
          )
          .lastOrNull;
      pendingAccountCreation =
          prior == null
                ? {
                    'id': const Uuid().v4(),
                    'deviceId': deviceId,
                    'payload': preferences,
                    'createdAt': clock().toUtc().toIso8601String(),
                  }
                : cloneMap(prior)
            ..remove('status');
      try {
        await _persist();
      } catch (_) {
        pendingAccountCreation = null;
        rethrow;
      }
    }
    if (pendingAccountCreation!['deviceId'] != deviceId) {
      throw const RuleException(
        'Esta solicitud pertenece al dispositivo original; requiere revisión de administración',
      );
    }
    final request = cloneMap(pendingAccountCreation!);
    final result = await remote!.createMember(
      request['id'],
      preferences,
      password,
    );
    if (result['created'] != true || result['userId'] is! String) {
      throw const RuleException(
        'Respuesta de creación incompleta; conserva la solicitud y reintenta',
      );
    }
    await _refresh();
    final previousHistory = accountCreationHistory.toList();
    accountCreationHistory.add({
      ...request,
      'status': 'created',
      'userId': result['userId'],
    });
    pendingAccountCreation = null;
    try {
      await _persist();
    } catch (_) {
      pendingAccountCreation = request;
      accountCreationHistory = previousHistory;
      rethrow;
    }
    notifyListeners();
  });

  Future<void> archiveAccountCreation(String reason) => _locked(() async {
    _checkAccess();
    if (actor.role != Role.admin || pendingAccountCreation == null) return;
    final request = pendingAccountCreation!,
        old = accountCreationHistory.toList();
    if (reason.trim().isEmpty || reason.length > 2000) {
      throw const RuleException('Indica el motivo de la revisión');
    }
    accountCreationHistory.add({
      ...request,
      'status': 'archived',
      'archiveReason': reason.trim(),
    });
    pendingAccountCreation = null;
    try {
      await _persist();
    } catch (_) {
      pendingAccountCreation = request;
      accountCreationHistory = old;
      rethrow;
    }
    notifyListeners();
  });
  Future<void> manage(String action, Map<String, dynamic> payload) =>
      _locked(() async {
        _checkAccess();
        if (actor.role != Role.admin) {
          throw const RuleException('Se requiere administrador');
        }
        final p = {...payload, 'revision': state.managementRevision};
        if (demo) {
          final before = state;
          final next = state.copy();
          next.manage(const Uuid().v4(), action, p, actor, clock().toUtc());
          state = next;
          try {
            await _persist();
          } catch (_) {
            state = before;
            rethrow;
          }
          actor = state.members.firstWhere((m) => m.id == actor.id);
          notifyListeners();
        } else {
          if (outbox.isNotEmpty || pendingCommands.isNotEmpty) {
            throw const RuleException(
              'Sincroniza los registros antes de administrar',
            );
          }
          await _command(action, p);
        }
      });
  Future<void> portal(String action, Map<String, dynamic> payload) =>
      _locked(() async {
        _checkAccess();
        if (!actor.isOffice ||
            (action == 'portal_configure' && actor.role != Role.admin)) {
          throw const RuleException(
            'Se requiere el perfil autorizado de oficina o administración',
          );
        }
        if (outbox.isNotEmpty || pendingCommands.isNotEmpty || offline) {
          throw const RuleException(
            'Conecta y sincroniza los pendientes antes de gestionar accesos',
          );
        }
        if (demo) {
          if (action != 'portal_configure') {
            throw const RuleException(
              'Los accesos de cliente requieren un taller conectado',
            );
          }
          validatePortalUrl(payload['url']);
          final before = state;
          state = state.copy();
          state.configuration['settings'] = {
            ...state.settings,
            'portalBaseUrl': payload['url'],
          };
          try {
            await _persist();
          } catch (_) {
            state = before;
            rethrow;
          }
          notifyListeners();
          return;
        }
        await _command(action, payload);
      });
  Future<PortalCredentials> createPortal(Map<String, dynamic> payload) async {
    final credentials = PortalCredentials.generate();
    final hashes = await credentials.hashes();
    await portal('portal_create', {
      ...payload,
      'id': credentials.id,
      ...hashes,
    });
    return credentials;
  }

  Future<void> planning(String action, Map<String, dynamic> payload) =>
      _locked(() async {
        _checkAccess();
        if (outbox.isNotEmpty || pendingCommands.isNotEmpty) {
          throw const RuleException(
            'Sincroniza y revisa los pendientes antes de reservar',
          );
        }
        final p = {
          ...payload,
          'revision':
              payload['revision'] ??
              PlanningLedger(state.configuration['planning']).revision,
        };
        final next = state.copy();
        applyPlanningCommand(
          next,
          const Uuid().v4(),
          action,
          p,
          actor,
          clock().toUtc(),
        );
        if (demo) {
          final before = state;
          state = next;
          try {
            await _persist();
          } catch (_) {
            state = before;
            rethrow;
          }
          notifyListeners();
        } else {
          try {
            await _command(action, p, allowOffline: true);
          } on RuleException {
            if (!offline && !accessRevoked && pendingCommands.isEmpty) {
              await _refresh();
              notifyListeners();
            }
            rethrow;
          }
        }
      });

  Future<void> fleet(String action, Map<String, dynamic> payload) =>
      _locked(() async {
        _checkAccess();
        if (outbox.isNotEmpty || pendingCommands.isNotEmpty) {
          throw const RuleException(
            'Sincroniza y revisa los pendientes antes de registrar flotas',
          );
        }
        final p = {
          ...payload,
          'revision':
              payload['revision'] ??
              FleetLedger(state.configuration['fleets']).revision,
        };
        final next = state.copy();
        applyFleetCommand(
          next,
          const Uuid().v4(),
          action,
          p,
          actor,
          clock().toUtc(),
        );
        if (demo) {
          final before = state;
          state = next;
          try {
            await _persist();
          } catch (_) {
            state = before;
            rethrow;
          }
          notifyListeners();
        } else {
          try {
            await _command(action, p, allowOffline: true);
          } on RuleException {
            if (!offline && !accessRevoked && pendingCommands.isEmpty) {
              await _refresh();
              notifyListeners();
            }
            rethrow;
          }
        }
      });

  Future<void> maintenance(
    String action,
    Map<String, dynamic> payload,
  ) => _locked(() async {
    _checkAccess();
    if (outbox.isNotEmpty || pendingCommands.isNotEmpty) {
      throw const RuleException(
        'Sincroniza y revisa los pendientes antes de registrar mantenimiento',
      );
    }
    final p = {
      ...payload,
      'revision':
          payload['revision'] ??
          MaintenanceLedger(state.configuration['maintenance']).revision,
    };
    final next = state.copy();
    applyMaintenanceCommand(
      next,
      const Uuid().v4(),
      action,
      p,
      actor,
      clock().toUtc(),
    );
    if (demo) {
      final before = state;
      state = next;
      try {
        await _persist();
      } catch (_) {
        state = before;
        rethrow;
      }
      notifyListeners();
    } else {
      try {
        await _command(action, p, allowOffline: true);
      } on RuleException {
        if (!offline && !accessRevoked && pendingCommands.isEmpty) {
          await _refresh();
          notifyListeners();
        }
        rethrow;
      }
    }
  });

  Future<void> library(String action, Map<String, dynamic> payload) =>
      _locked(() async {
        _checkAccess();
        if (outbox.isNotEmpty || pendingCommands.isNotEmpty) {
          throw const RuleException(
            'Sincroniza los pendientes antes de revisar la biblioteca',
          );
        }
        final c = libraryCases(
          state,
        ).where((c) => c['id'] == payload['id']).firstOrNull;
        final p = {
          ...payload,
          'revision': payload['revision'] ?? c?['revision'] ?? 0,
        };
        final next = state.copy();
        applyCaseCommand(
          next,
          const Uuid().v4(),
          action,
          p,
          actor,
          clock().toUtc(),
        );
        if (demo) {
          final before = state;
          state = next;
          try {
            await _persist();
          } catch (_) {
            state = before;
            rethrow;
          }
          notifyListeners();
        } else {
          await _command(action, p, allowOffline: true);
        }
      });
  Future<void> inventory(
    String action,
    Map<String, dynamic> payload,
  ) => _locked(() async {
    _checkAccess();
    if (!actor.isOffice || (actor.role != Role.admin && !actor.seeCosts)) {
      throw const RuleException(
        'Se requiere permiso de oficina para gestionar costes',
      );
    }
    if (outbox.isNotEmpty || pendingCommands.isNotEmpty) {
      throw const RuleException(
        'Revisa y sincroniza los pendientes antes de registrar otro movimiento',
      );
    }
    final p = {
      ...payload,
      'revision': PurchaseLedger(
        state.configuration['purchaseLedger'],
      ).revision,
      'at': clock().toUtc().toIso8601String(),
    };
    if (demo) {
      final before = state, next = state.copy();
      applyPurchaseCommand(
        next,
        const Uuid().v4(),
        action,
        p,
        actor,
        clock().toUtc(),
      );
      state = next;
      try {
        await _persist();
      } catch (_) {
        state = before;
        rethrow;
      }
      notifyListeners();
    } else {
      await _command(action, p, allowOffline: true);
    }
  });
  Future<Map<String, dynamic>> previewImport(ImportPreview preview) =>
      _locked(() async {
        _checkAccess();
        final payload = preview.payload('Vista previa de importación CSV');
        if (payload['rows'].isEmpty) {
          return {'rows': [], 'created': 0};
        }
        if (demo) {
          return applyDemoImport(
            state.copy(),
            preview.id,
            payload,
            actor,
            clock(),
            writing: false,
          );
        }
        _checkOnline();
        return remote!.command(const Uuid().v4(), 'import_preview', payload);
      });
  Future<Map<String, dynamic>> commitImport(
    ImportPreview preview,
    String reason,
  ) => _locked(() async {
    _checkAccess();
    if (reason.trim().isEmpty || reason.length > 2000) {
      throw const RuleException('Indica el motivo de la importación');
    }
    if (outbox.isNotEmpty || pendingCommands.isNotEmpty || hasPendingPhotos) {
      throw const RuleException(
        'Sincroniza todos los pendientes antes de importar',
      );
    }
    final payload = preview.payload(reason.trim());
    final existing = commandHistory
        .where((h) => h['id'] == preview.id)
        .firstOrNull;
    if (existing != null && existing['status'] == 'accepted') {
      if (jsonEncode(existing['payload']) != jsonEncode(payload)) {
        throw const RuleException(
          'La importación ya registrada conserva sus datos y motivo originales',
        );
      }
      return Map<String, dynamic>.from(existing['result']);
    }
    if (demo) {
      final next = state.copy(), old = state;
      final oldHistory = commandHistory.toList();
      final result = applyDemoImport(next, preview.id, payload, actor, clock());
      state = next;
      commandHistory.add({
        'id': preview.id,
        'action': 'import_commit',
        'payload': payload,
        'status': 'accepted',
        'result': result,
      });
      try {
        await _persist();
      } catch (_) {
        state = old;
        commandHistory = oldHistory;
        rethrow;
      }
      notifyListeners();
      return result;
    }
    _checkOnline();
    await _command('import_commit', payload, commandId: preview.id);
    return Map<String, dynamic>.from(
      commandHistory.lastWhere((h) => h['id'] == preview.id)['result'],
    );
  });
  List<WorkOrder> get visibleOrders => !accessAllowed
      ? []
      : state.orders.values
            .where((o) => actor.isOffice || o.assigned(actor.id))
            .toList();
  Map<String, dynamic>? closure(String orderId) => closures
      .where((c) => c['orderId'] == orderId && c['status'] == 'active')
      .firstOrNull;
  bool frozen(String orderId) => closeLocks.containsKey(orderId);

  Future<void> load() async {
    final saved = await vault.read();
    if (saved != null) {
      if (![1, 2].contains(saved['schema'])) {
        throw StateError('Versión de datos no compatible');
      }
      if (!demo && saved['actor']['id'] != actor.id) {
        throw const RuleException('Almacén de otra cuenta');
      }
      state = WorkshopState.fromJson(saved['state']);
      deviceId = saved['deviceId'];
      outbox = (saved['outbox'] as List)
          .map((j) => Operation.fromJson(Map<String, dynamic>.from(j)))
          .toList();
      failures = Map<String, String>.from(saved['failures'] ?? {});
      serverConflicts =
          (saved['serverConflicts'] as List? ?? failures.keys.toList())
              .cast<String>()
              .toSet();
      closeLocks = Map<String, dynamic>.from(saved['closeLocks'] ?? {});
      closures = _maps(saved['closures']);
      devices = _maps(saved['devices']);
      retiredTimers = _maps(saved['retiredTimers']);
      pendingCommands = _maps(saved['pendingCommands']);
      commandHistory = _maps(saved['commandHistory']);
      pendingAccountCreation = saved['pendingAccountCreation'] == null
          ? null
          : Map<String, dynamic>.from(saved['pendingAccountCreation']);
      accountCreationHistory = _maps(saved['accountCreationHistory']);
      photoQueue = _maps(saved['photoQueue']);
      photoHistory = _maps(saved['photoHistory']);
      cachedPhotoHashes = (saved['cachedPhotoHashes'] as List? ?? [])
          .cast<String>()
          .toSet();
      captureTicket = saved['captureTicket'] == null
          ? null
          : cloneMap(Map<String, dynamic>.from(saved['captureTicket']));
      validatedAt = DateTime.tryParse(saved['validatedAt'] ?? '');
      lastObservedAt = DateTime.tryParse(saved['lastObservedAt'] ?? '');
      accessRevoked = saved['accessRevoked'] == true;
      replacement = saved['replacement'] == null
          ? null
          : Map<String, dynamic>.from(saved['replacement']);
      restoredArchive = saved['restoredArchive'] == null
          ? null
          : Map<String, dynamic>.from(saved['restoredArchive']);
      remote?.bindDevice(deviceId);
      // No network is required to open a previously validated encrypted cache.
      // An expired or revoked cache opens only the locked recovery screen.
    } else if (demo) {
      state = demoState();
      await _persist();
    } else {
      remote!.bindDevice(deviceId);
      await _refresh();
    }
  }

  static List<Map<String, dynamic>> _maps(dynamic values) =>
      (values as List? ?? []).map((v) => Map<String, dynamic>.from(v)).toList();
  Future<void> _persist() {
    final now = clock().toUtc();
    if (lastObservedAt == null || now.isAfter(lastObservedAt!)) {
      lastObservedAt = now;
    }
    return vault.write(localArchive());
  }

  Map<String, dynamic> localArchive() => {
    'actor': actor.toJson(),
    'schema': 2,
    'state': state.toJson(),
    'deviceId': deviceId,
    'outbox': outbox.map((o) => o.toJson()).toList(),
    'failures': failures,
    'serverConflicts': serverConflicts.toList(),
    'closeLocks': closeLocks,
    'closures': closures,
    'devices': devices,
    'retiredTimers': retiredTimers,
    'validatedAt': validatedAt?.toUtc().toIso8601String(),
    'lastObservedAt': lastObservedAt?.toUtc().toIso8601String(),
    'accessRevoked': accessRevoked,
    'pendingCommands': pendingCommands,
    'commandHistory': commandHistory,
    'replacement': replacement,
    'restoredArchive': restoredArchive,
    'pendingAccountCreation': pendingAccountCreation,
    'accountCreationHistory': accountCreationHistory,
    'photoQueue': photoQueue,
    'photoHistory': photoHistory,
    'cachedPhotoHashes': cachedPhotoHashes.toList(),
    'captureTicket': captureTicket,
  };

  Future<Map<String, dynamic>> exportBackup({
    bool complete = false,
    bool splitFiles = false,
  }) => _locked(() async {
    _checkAccess();
    if (complete && (actor.role != Role.admin || demo || offline)) {
      throw const RuleException(
        'Conecta como administrador para copiar el servidor',
      );
    }
    final server = complete ? await remote!.exportWorkshop() : null;
    final files = await _exportPhotoFiles(server, splitFiles: splitFiles);
    return {
      'kind': 'TallerFlow',
      'version': 1,
      'archiveId': const Uuid().v4(),
      'createdAt': clock().toUtc().toIso8601String(),
      'workshopId': state.workshopId,
      'actorId': actor.id,
      'scope': complete ? 'workshop-and-device' : 'device',
      'local': _portableLocal(),
      'photoFiles': files,
      'server': ?server,
    };
  });

  Future<void> restoreLocalBackup(
    Map<String, dynamic> archive, {
    Future<Uint8List?> Function(String)? readPhoto,
  }) => _locked(() async {
    if (archive['kind'] != 'TallerFlow' ||
        archive['version'] != 1 ||
        archive['workshopId'] != state.workshopId ||
        archive['actorId'] != actor.id) {
      throw const RuleException(
        'La copia no corresponde a este taller y cuenta',
      );
    }
    if (outbox.isNotEmpty ||
        pendingCommands.isNotEmpty ||
        pendingAccountCreation != null ||
        hasPendingPhotos) {
      throw const RuleException(
        'Conserva y reconcilia los pendientes de este equipo antes de restaurar otra copia',
      );
    }
    final local = cloneMap(Map<String, dynamic>.from(archive['local']));
    if (![1, 2].contains(local['schema']) ||
        local['actor']['id'] != actor.id ||
        local['state']['workshopId'] != state.workshopId) {
      throw const RuleException('Contenido de copia incompatible');
    }
    final files = await _validatePhotoFiles(archive, readPhoto: readPhoto);
    _validatePhotoLocal(local, files);
    if (local['captureTicket'] is Map) {
      local['captureTicket'].remove('sourcePath');
    }
    // Parse before writing. The imported lease never grants permission.
    WorkshopState.fromJson(Map<String, dynamic>.from(local['state']));
    Actor.fromJson(Map<String, dynamic>.from(local['actor']));
    if (local['deviceId'] is! String || (local['deviceId'] as String).isEmpty) {
      throw const RuleException('La copia no identifica el dispositivo');
    }
    Map<String, String>.from(local['failures'] ?? {});
    (local['serverConflicts'] as List? ?? []).cast<String>().toList();
    for (final key in [
      'closures',
      'devices',
      'retiredTimers',
      'commandHistory',
    ]) {
      _maps(local[key]);
    }
    final commands = _maps(local['pendingCommands']);
    final accounts = _maps(local['accountCreationHistory']);
    if (local['pendingAccountCreation'] != null) {
      accounts.add(Map<String, dynamic>.from(local['pendingAccountCreation']));
    }
    for (final request in accounts) {
      if (request['id'] is! String ||
          request['deviceId'] is! String ||
          request['payload'] is! Map ||
          !mapEquals(
            request['payload'],
            accountPreferences(Map<String, dynamic>.from(request['payload'])),
          ) ||
          request.containsKey('password')) {
        throw const RuleException(
          'Solicitud de cuenta incompatible en la copia',
        );
      }
    }
    final commandIds = <String>{};
    for (final cmd in commands) {
      if (cmd['id'] is! String ||
          cmd['action'] is! String ||
          cmd['payload'] is! Map ||
          !commandIds.add(cmd['id'])) {
        throw const RuleException('Comando pendiente incompatible en la copia');
      }
    }
    final locks = Map<String, dynamic>.from(local['closeLocks'] ?? {});
    for (final value in locks.values) {
      Map<String, dynamic>.from(value);
    }
    if (local['replacement'] != null) {
      Map<String, dynamic>.from(local['replacement']);
    }
    final operationIds = <String>{};
    for (final op in local['outbox'] as List) {
      final parsed = Operation.fromJson(Map<String, dynamic>.from(op));
      if (parsed.actorId != actor.id || !operationIds.add(parsed.id)) {
        throw const RuleException('Pendiente de otra cuenta');
      }
    }
    local['validatedAt'] = null;
    local['lastObservedAt'] = clock().toUtc().toIso8601String();
    local['accessRevoked'] = !demo;
    local['restoredArchive'] = {
      'archiveId': archive['archiveId'],
      'createdAt': archive['createdAt'],
      'restoredAt': clock().toUtc().toIso8601String(),
      'sourceDeviceId': local['deviceId'],
      'previousLocal': cloneMap(localArchive())..remove('restoredArchive'),
      'originalLocal': cloneMap(Map<String, dynamic>.from(archive['local']))
        ..remove('restoredArchive'),
    };
    // Immutable encrypted blobs complete first. An interrupted metadata write
    // leaves only harmless unreferenced files, never a dangling queue.
    local['cachedPhotoHashes'] = files.keys.toList();
    // Atomic encrypted write completes before replacing in-memory state.
    await vault.write(local);
    await load();
    notifyListeners();
  });

  Future<Map<String, dynamic>> restoreServerBackup(
    Map<String, dynamic> archive, {
    Future<Uint8List?> Function(String)? readPhoto,
  }) => _locked(() async {
    _checkAccess();
    _checkOnline();
    if (actor.role != Role.admin ||
        archive['workshopId'] != state.workshopId ||
        archive['server'] == null ||
        outbox.isNotEmpty ||
        pendingCommands.isNotEmpty ||
        hasPendingPhotos) {
      throw const RuleException(
        'Restauración completa: administrador, taller correcto y equipo sin pendientes',
      );
    }
    final files = await _validatePhotoFiles(archive, readPhoto: readPhoto);
    final server = Map<String, dynamic>.from(archive['server']);
    final expected = WorkshopController._maps(server['photoFiles']);
    for (final photo in expected.where((p) => p['filePresent'] == true)) {
      final size = files[photo['sha256']];
      if (size == null || size != photo['size']) {
        throw const RuleException(
          'La copia no contiene todos los archivos originales',
        );
      }
    }
    final result = await remote!.restoreWorkshop(archive['archiveId'], server);
    for (final photo in expected.where((p) => p['filePresent'] == true)) {
      final info = await remote!.restoredPhotoInfo(photo['id']);
      if (info['id'] != photo['id'] ||
          info['orderId'] != photo['orderId'] ||
          info['sha256'] != photo['sha256'] ||
          info['size'] != photo['size']) {
        throw const RuleException(
          'El servidor no coincide con el manifiesto de recuperación',
        );
      }
      final bytes = await vault.photos.read(photo['sha256']);
      if (bytes == null || bytes.length != photo['size']) {
        throw const RuleException('Falta un archivo de recuperación');
      }
      await remote!.uploadPhoto(info, bytes);
      await remote!.finalizePhoto(photo['id']);
    }
    await _refresh();
    notifyListeners();
    return result;
  });

  Future<T> _locked<T>(Future<T> Function() body) {
    final result = _serial.then((_) => body());
    _serial = result.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return result;
  }

  void _checkOnline() {
    if (demo || offline) {
      throw const RuleException('Conecta al servidor para esta acción.');
    }
  }

  void _checkAccess() {
    if (!accessAllowed) {
      throw const RuleException(
        'Conecta para revalidar tu cuenta. Tus registros se conservan.',
      );
    }
  }

  Future<void> execute(
    String orderId,
    String kind,
    Map<String, dynamic> payload, {
    DateTime? at,
    int? expectedRevision,
  }) {
    if (kind == 'issue' && !demo) return issue(orderId);
    return _locked(() async {
      _checkAccess();
      if (expectedRevision != null &&
          state.orders[orderId]?.revision != expectedRevision) {
        throw const RuleException(
          'La orden cambió mientras revisabas los datos. Ábrela de nuevo',
        );
      }
      if (frozen(orderId)) {
        throw const RuleException(
          'Orden bloqueada en este dispositivo para el cierre. Sincroniza para conocer su resultado.',
        );
      }
      if (failures.isNotEmpty &&
          [
            'billable',
            'authorize',
            'pricing_review',
            'quote_draft',
            'quote_decision',
            'payment_record',
            'payment_reverse',
            'deliver',
          ].contains(kind)) {
        throw const RuleException(
          'Resuelve los conflictos antes de revisar importes',
        );
      }
      final op = Operation(
        id: const Uuid().v4(),
        orderId: orderId,
        kind: kind,
        actorId: actor.id,
        baseRevision: state.orders[orderId]?.revision ?? 0,
        at: at ?? clock().toUtc(),
        payload: payload,
      );
      final next = state.copy();
      next.apply(op, actor);
      final previous = state;
      state = next;
      if (!demo) outbox.add(op);
      try {
        await _persist();
      } catch (_) {
        state = previous;
        outbox.removeWhere((o) => o.id == op.id);
        rethrow;
      }
      notifyListeners();
    });
  }

  Future<void> _refresh() async {
    late Map<String, dynamic> data;
    try {
      data = await remote!.snapshot();
    } on PostgrestException catch (e) {
      if (['42501', 'PGRST301', 'PGRST302', 'PGRST303'].contains(e.code)) {
        await _revokeAccess();
      }
      rethrow;
    }
    final nextActor = data['actor'] == null
        ? actor
        : Actor.fromJson(Map<String, dynamic>.from(data['actor']));
    if (nextActor.id != actor.id) {
      throw const RuleException('Respuesta de otra cuenta');
    }
    final stamp = data['serverTime'] == null
        ? clock().toUtc()
        : DateTime.parse(data['serverTime']);
    if (remote!.requiresLease &&
        (data['actor'] == null ||
            data['serverTime'] == null ||
            clock().toUtc().difference(stamp).abs() >
                const Duration(minutes: 2))) {
      throw const RuleException(
        'Comprueba el reloj del dispositivo antes de validar la sesión.',
      );
    }
    final next = WorkshopState.fromJson(data);
    final receipts = {
      for (final r in _maps(data['receipts'])) r['id'] as String: r,
    };
    final remaining = <Operation>[];
    final nextFailures = <String, String>{};
    final nextServerConflicts = <String>{};
    for (final op in outbox) {
      final r = receipts[op.id];
      if (next.applied.contains(op.id) ||
          r?['resolved'] == true ||
          ['accepted', 'late'].contains(r?['status'])) {
        continue;
      }
      remaining.add(op);
      if (r?['status'] == 'conflict') {
        nextFailures[op.id] = r?['reason'] ?? 'Conflicto para oficina';
        nextServerConflicts.add(op.id);
      } else if (failures.containsKey(op.id)) {
        nextFailures[op.id] = failures[op.id]!;
        if (serverConflicts.contains(op.id)) nextServerConflicts.add(op.id);
      }
      try {
        // Replay on a fresh server base, never on a previously optimistic projection.
        final projected = next.copy();
        projected.apply(op, nextActor, replay: true);
        next.orders.clear();
        next.orders.addAll(projected.orders);
        next.applied.addAll(projected.applied);
        next.audit.clear();
        next.audit.addAll(projected.audit);
        next.incidents.clear();
        next.incidents.addAll(projected.incidents);
      } catch (e) {
        nextFailures[op.id] = 'Registro local conservado: $e';
      }
    }
    final nextClosures = _maps(data['closures']);
    final nextLocks = Map<String, dynamic>.from(closeLocks);
    for (final id in closeLocks.keys) {
      final lock = closeLocks[id];
      final request = nextClosures
          .where((c) => c['id'] == lock['requestId'])
          .firstOrNull;
      // A missing request does NOT prove cancellation. Keep the lock fail-closed.
      if (request != null && request['status'] == 'invalidated') {
        nextLocks.remove(id);
      }
    }
    // Persist all reconciliation changes together; restore memory on a failed write.
    final previousState = stateOrNull;
    final oldActor = actor,
        oldOutbox = outbox,
        oldFailures = failures,
        oldClosures = closures,
        oldDevices = devices,
        oldLocks = closeLocks,
        oldStamp = validatedAt,
        oldRevoked = accessRevoked,
        oldObserved = lastObservedAt,
        oldRetiredTimers = retiredTimers,
        oldServerConflicts = serverConflicts,
        oldPhotoQueue = photoQueue.toList(),
        oldPhotoHistory = photoHistory.toList();
    state = next;
    actor = nextActor;
    outbox = remaining;
    failures = nextFailures;
    serverConflicts = nextServerConflicts;
    closures = nextClosures;
    devices = _maps(data['devices']);
    retiredTimers = _maps(data['retiredTimers']);
    closeLocks = nextLocks;
    validatedAt = stamp;
    lastObservedAt = stamp;
    accessRevoked = false;
    _reconcilePhotos();
    try {
      await _persist();
    } catch (_) {
      if (previousState != null) state = previousState;
      actor = oldActor;
      outbox = oldOutbox;
      failures = oldFailures;
      closures = oldClosures;
      devices = oldDevices;
      closeLocks = oldLocks;
      validatedAt = oldStamp;
      accessRevoked = oldRevoked;
      lastObservedAt = oldObserved;
      retiredTimers = oldRetiredTimers;
      serverConflicts = oldServerConflicts;
      photoQueue = oldPhotoQueue;
      photoHistory = oldPhotoHistory;
      rethrow;
    }
  }

  WorkshopState? get stateOrNull {
    try {
      return state;
    } on Error {
      return null;
    }
  }

  Future<void> synchronize() => _locked(() async {
    if (demo || offline || syncing) return;
    syncing = true;
    syncError = null;
    notifyListeners();
    try {
      await _refresh(); // Pull even while there is an unresolved local queue.
      await _drainCommands();
      for (final op in outbox.toList()) {
        if (serverConflicts.contains(op.id)) {
          continue; // Independent records can still reach office.
        }
        final receipt = await remote!.push(op, deviceId);
        if (receipt['status'] == 'conflict') {
          failures[op.id] = receipt['reason'] ?? 'Conflicto';
          serverConflicts.add(op.id);
          await _persist();
          continue;
        }
        if (!['accepted', 'late'].contains(receipt['status'])) {
          throw StateError('Respuesta desconocida');
        }
        // Do not remove evidence until a server snapshot confirms it and is saved.
      }
      await _refresh();
      await _uploadPhotos();
      await _refresh();
      if (failures.isNotEmpty) {
        syncError = 'Registros conservados para revisión de oficina.';
      }
    } catch (e) {
      if (e is PostgrestException &&
          ['42501', 'PGRST301', 'PGRST302', 'PGRST303'].contains(e.code)) {
        await _revokeAccess();
      }
      syncError ??= accessRevoked
          ? 'Acceso revocado o dispositivo retirado. Los registros pendientes se conservan.'
          : 'No se pudo completar la sincronización. Los registros siguen guardados. $e';
    } finally {
      syncing = false;
      notifyListeners();
    }
  });

  Future<void> _drainCommands() async {
    for (final cmd in pendingCommands.toList()) {
      try {
        final result = await remote!.command(
          cmd['id'],
          cmd['action'],
          Map<String, dynamic>.from(cmd['payload']),
        );
        await _recordCommandResult(cmd, {
          'status': 'accepted',
          'result': result,
        });
      } on PostgrestException catch (e) {
        if (['42501', 'PGRST301', 'PGRST302', 'PGRST303'].contains(e.code)) {
          await _revokeAccess();
          rethrow;
        }
        await _recordCommandResult(cmd, {
          'status': 'rejected',
          'reason': e.message,
        });
        throw RuleException(e.message);
      }
    }
  }

  Future<void> _revokeAccess() async {
    accessRevoked = true;
    try {
      await _persist();
    } catch (_) {
      syncError =
          'Acceso bloqueado. No se pudo guardar la revocación en el dispositivo; recupera los registros antes de volver a utilizarlo.';
    }
    notifyListeners();
  }

  Future<void> reauthenticate(String email, String password) async {
    await remote!.reauthenticateReplacement(email, password, actor.id);
    await synchronize();
  }

  Future<void> _recordCommandResult(
    Map<String, dynamic> cmd,
    Map<String, dynamic> result,
  ) async {
    final previousPending = pendingCommands.toList();
    final previousHistory = commandHistory.toList();
    commandHistory.add({...cmd, ...result});
    pendingCommands.removeWhere((v) => v['id'] == cmd['id']);
    try {
      await _persist();
    } catch (_) {
      pendingCommands = previousPending;
      commandHistory = previousHistory;
      rethrow;
    }
  }

  Future<void> _command(
    String action,
    Map<String, dynamic> payload, {
    String? commandId,
    bool allowOffline = false,
  }) async {
    _checkAccess();
    if (demo || (offline && !allowOffline)) {
      throw const RuleException(
        'Esta acción requiere el servidor de pruebas conectado.',
      );
    }
    final cmd = {
      'id': commandId ?? const Uuid().v4(),
      'action': action,
      'payload': payload,
    };
    pendingCommands.add(cmd);
    try {
      await _persist();
    } catch (_) {
      pendingCommands.remove(cmd);
      rethrow;
    }
    if (offline) {
      notifyListeners();
      return;
    }
    await _drainCommands();
    await _refresh();
    notifyListeners();
  }

  Future<void> requestClose(
    String id, {
    String? exceptionReason,
  }) => _locked(() async {
    _checkOnline();
    await _refresh();
    if (outbox.isNotEmpty || pendingCommands.isNotEmpty || hasPendingPhotos) {
      throw const RuleException(
        'Sincroniza los registros y comandos locales antes de solicitar cierre.',
      );
    }
    await _command('request_close', {
      'orderId': id,
      'revision': state.orders[id]!.revision,
      'exceptionReason': exceptionReason,
    });
  });
  Future<void> confirmClose(String id) => _locked(() async {
    _checkOnline();
    await _refresh();
    _checkAccess();
    if (outbox.isNotEmpty || pendingCommands.isNotEmpty || hasPendingPhotos) {
      throw const RuleException(
        'Sincroniza todos los registros de este dispositivo antes de confirmar.',
      );
    }
    final order = state.orders[id]!;
    if (order.times.any((t) => t['actorId'] == actor.id && t['end'] == null)) {
      throw const RuleException(
        'Pausa tu cronómetro y solicita un nuevo cierre.',
      );
    }
    final request = closure(id);
    if (request == null) {
      throw const RuleException(
        'Oficina debe solicitar el cierre sobre la revisión actual.',
      );
    }
    final payload = {
      'orderId': id,
      'requestId': request['id'],
      'revision': request['revision'],
      'locallyFrozen': true,
    };
    final previous = closeLocks[id];
    closeLocks[id] = payload;
    try {
      await _persist();
    } catch (_) {
      if (previous == null) {
        closeLocks.remove(id);
      } else {
        closeLocks[id] = previous;
      }
      rethrow;
    }
    await _command('ack_close', payload);
  });
  Future<void> issue(String id) => _locked(() async {
    _checkOnline();
    await _refresh();
    if (!actor.isOffice) throw const RuleException('Solo oficina puede emitir');
    if (outbox.isNotEmpty || pendingCommands.isNotEmpty || hasPendingPhotos) {
      throw const RuleException('Sincroniza antes de emitir');
    }
    final request = closure(id);
    if (request == null || !frozen(id)) {
      throw const RuleException(
        'Solicita el cierre y confirma este dispositivo antes de emitir.',
      );
    }
    await _command('issue', {'orderId': id, 'requestId': request['id']});
  });
  Future<void> resolve(
    Map<String, dynamic> incident,
    String outcome,
    String reason,
  ) => _locked(() async {
    _checkOnline();
    await _refresh();
    if (!actor.isOffice) throw const RuleException('Se requiere oficina');
    final original = incident['operation'];
    await _command('resolve', {
      'operationId': original['id'],
      'orderId': original['orderId'],
      'revision': state.orders[original['orderId']]?.revision,
      'outcome': outcome,
      'reason': reason,
    });
  });
  Future<void> retireDevice(String id, String reason) => _locked(() async {
    await _command('retire_device', {'deviceId': id, 'reason': reason});
  });
  Future<void> endRetiredTimer(String sessionId, DateTime end, String reason) =>
      _locked(() async {
        await _command('end_retired_timer', {
          'sessionId': sessionId,
          'end': end.toUtc().toIso8601String(),
          'reason': reason,
        });
      });
  Future<void> recoverRetiredRecords() => _locked(() async {
    // Recovery grants no editing authority and never changes the server document.
    for (final op in outbox.toList()) {
      final r = await remote!.push(op, deviceId);
      if (!['late', 'accepted', 'conflict'].contains(r['status'])) {
        throw const RuleException(
          'Registro conservado para revisión; recuperación incompleta',
        );
      }
      commandHistory.add({
        'action': 'recover_retired',
        'operation': op.toJson(),
        'receipt': r,
      });
      outbox.removeWhere((v) => v.id == op.id);
      try {
        await _persist();
      } catch (_) {
        outbox.add(op);
        rethrow;
      }
    }
    notifyListeners();
  });
  Future<void> replaceRetiredDevice({
    String? email,
    String? password,
  }) => _locked(() async {
    _checkOnline();
    if (replacement != null && replacement!['oldDeviceId'] != deviceId) {
      remote!.bindDevice(deviceId);
      await _refresh();
      replacement = null;
      await _persist();
      notifyListeners();
      return;
    }
    if (outbox.isNotEmpty) {
      throw const RuleException(
        'Recupera los registros pendientes antes de registrar el dispositivo sustituto.',
      );
    }
    if (replacement == null && remote!.requiresLease) {
      if (email == null || password == null) {
        throw const RuleException(
          'Inicia sesión de nuevo para sustituir el dispositivo.',
        );
      }
      await remote!.reauthenticateReplacement(email, password, actor.id);
    }
    replacement ??= {
      'id': const Uuid().v4(),
      'oldDeviceId': deviceId,
      'newDeviceId': const Uuid().v4(),
    };
    await _persist();
    final result = await remote!.command(replacement!['id'], 'replace_device', {
      'newDeviceId': replacement!['newDeviceId'],
    });
    final previous = {
      for (final r in _maps(result['previousCommands'])) r['id']: r,
    };
    final oldDevice = deviceId,
        oldCommands = pendingCommands.toList(),
        oldHistory = commandHistory.toList();
    for (final cmd in pendingCommands) {
      commandHistory.add({
        ...cmd,
        'deviceId': oldDevice,
        'status': previous.containsKey(cmd['id'])
            ? 'accepted'
            : 'abandoned_after_retirement',
        'result': previous[cmd['id']]?['result'],
        'reason':
            'Identidad retirada; comando original conservado, no reenviado con otro dispositivo',
      });
    }
    pendingCommands = [];
    deviceId = replacement!['newDeviceId'];
    try {
      await _persist();
    } catch (_) {
      deviceId = oldDevice;
      pendingCommands = oldCommands;
      commandHistory = oldHistory;
      rethrow;
    }
    remote!.bindDevice(deviceId);
    await _refresh();
    replacement = null;
    await _persist();
    notifyListeners();
  });
  void changeDemoActor(Actor value) {
    if (demo) {
      actor = value;
      notifyListeners();
    }
  }

  void toggleOffline() {
    offline = !offline;
    notifyListeners();
    if (!offline && !demo) unawaited(synchronize());
  }

  List<String> issues(WorkOrder o) {
    final values = closeIssues(
      o,
      pending: outbox.where((p) => p.orderId == o.id).length,
      connected: !offline && accessAllowed,
      conflict:
          failures.isNotEmpty ||
          state.catalog.any((c) => state.stock(c.id) < 0) ||
          state.incidents.any(
            (i) =>
                i['operation']?['orderId'] == o.id && i['resolution'] == null,
          ),
    );
    if (!demo) {
      if (photoQueue.any((p) => p['orderId'] == o.id) ||
          captureTicket?['orderId'] == o.id) {
        values.add(
          'Hay fotografías locales pendientes de guardar o sincronizar',
        );
      }
      if (photoManifest.any(
        (p) =>
            p['orderId'] == o.id && ['pending', 'review'].contains(p['status']),
      )) {
        values.add(
          'Hay fotografías pendientes de subida o revisión de oficina',
        );
      }
      if (state.configuration['restoreFilesPending'] == true) {
        values.add('Completa la recuperación de los archivos originales');
      }
      final request = closure(o.id);
      if (request == null) {
        values.add('Oficina debe solicitar el cierre entre dispositivos');
      } else {
        final required = (request['requiredDevices'] as List? ?? []);
        final confirmed = (request['confirmedDevices'] as List? ?? []);
        final missing = required.where((d) => !confirmed.contains(d)).length;
        if (missing > 0) {
          values.add('$missing dispositivos pendientes de confirmar el cierre');
        }
      }
    }
    return values;
  }
}
