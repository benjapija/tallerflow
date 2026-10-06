import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/engine.dart';
import '../domain/models.dart';

class SecureSessionStorage extends LocalStorage {
  const SecureSessionStorage();
  static const _storage = FlutterSecureStorage();
  static const _key = 'tallerflow-session-v1';
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => await _storage.containsKey(key: _key);
  @override
  Future<String?> accessToken() => _storage.read(key: _key);
  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);
  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}

abstract class Remote {
  Future<Map<String, dynamic>> createMember(
    String id,
    Map<String, dynamic> preferences,
    String password,
  ) => throw UnsupportedError(
    'La creación de cuentas requiere el servicio conectado',
  );
  Future<Map<String, dynamic>> snapshot();
  Future<Map<String, dynamic>> push(Operation operation, String deviceId);
  bool get requiresLease => false;
  void bindDevice(String id) {}
  Future<Map<String, dynamic>> exportWorkshop() =>
      throw UnsupportedError('Este servidor no admite exportación completa');
  Future<Map<String, dynamic>> restoreWorkshop(
    String id,
    Map<String, dynamic> archive,
  ) => throw UnsupportedError('Este servidor no admite restauración completa');
  Future<void> reauthenticateReplacement(
    String email,
    String password,
    String expectedActor,
  ) => throw UnsupportedError(
    'Inicia sesión de nuevo para sustituir el dispositivo',
  );
  Future<Map<String, dynamic>> command(
    String id,
    String action,
    Map<String, dynamic> payload,
  ) => throw UnsupportedError(
    'Este servidor no implementa el protocolo de cierre',
  );
}

class SupabaseRemote extends Remote {
  final SupabaseClient client;
  final String workshopId;
  SupabaseRemote(this.client, this.workshopId);
  late String deviceId;
  @override
  bool get requiresLease => true;
  @override
  void bindDevice(String id) => deviceId = id;
  @override
  Future<Map<String, dynamic>> createMember(
    String id,
    Map<String, dynamic> preferences,
    String password,
  ) async {
    final response = await client.functions
        .invoke(
          'workshop-members',
          body: {
            'workshopId': workshopId,
            'deviceId': deviceId,
            'requestId': id,
            'payload': preferences,
            'password': password,
          },
        )
        .timeout(const Duration(seconds: 30));
    return Map<String, dynamic>.from(response.data);
  }

  @override
  Future<Map<String, dynamic>> exportWorkshop() async =>
      Map<String, dynamic>.from(
        await client
            .rpc(
              'export_workshop',
              params: {'workshop_id': workshopId, 'device_id': deviceId},
            )
            .timeout(const Duration(seconds: 30)),
      );
  @override
  Future<Map<String, dynamic>> restoreWorkshop(
    String id,
    Map<String, dynamic> archive,
  ) async => Map<String, dynamic>.from(
    await client
        .rpc(
          'restore_workshop',
          params: {
            'workshop_id': workshopId,
            'device_id': deviceId,
            'restore_id': id,
            'archive': archive,
          },
        )
        .timeout(const Duration(seconds: 30)),
  );
  @override
  Future<void> reauthenticateReplacement(
    String email,
    String password,
    String expectedActor,
  ) async {
    final response = await client.auth
        .signInWithPassword(email: email, password: password)
        .timeout(const Duration(seconds: 12));
    if (response.user?.id != expectedActor) {
      await client.auth.signOut(scope: SignOutScope.local);
      throw StateError(
        'Usa la misma cuenta para recuperar y sustituir este dispositivo',
      );
    }
  }

  @override
  Future<Map<String, dynamic>> snapshot() async => Map<String, dynamic>.from(
    await client
        .rpc(
          'device_snapshot',
          params: {'workshop_id': workshopId, 'device_id': deviceId},
        )
        .timeout(const Duration(seconds: 12)),
  );
  @override
  Future<Map<String, dynamic>> command(
    String id,
    String action,
    Map<String, dynamic> payload,
  ) async => Map<String, dynamic>.from(
    await client
        .rpc(
          [
                'settings_save',
                'member_save',
                'catalog_save',
                'template_save',
              ].contains(action)
              ? 'management_command'
              : 'reliability_command',
          params: {
            'workshop_id': workshopId,
            'device_id': deviceId,
            'command_id': id,
            'action': action,
            'payload': payload,
          },
        )
        .timeout(const Duration(seconds: 12)),
  );
  @override
  Future<Map<String, dynamic>> push(
    Operation operation,
    String deviceId,
  ) async {
    return Map<String, dynamic>.from(
      await client
          .rpc(
            'apply_operation',
            params: {
              'workshop_id': workshopId,
              'device_id': deviceId,
              'operation': operation.toJson(),
            },
          )
          .timeout(const Duration(seconds: 12)),
    );
  }

  Future<Actor> actor() async {
    final response = await client.rpc(
      'my_membership',
      params: {'workshop_id': workshopId},
    );
    return Actor.fromJson(Map<String, dynamic>.from(response));
  }
}
