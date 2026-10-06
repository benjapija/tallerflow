import '../domain/engine.dart';
import '../domain/models.dart';

/// Offline privileges last at most 24 hours since server validation.
/// A rollback over two minutes invalidates the lease; pending evidence is retained.
class LocalSessionPolicy {
  static const validity = Duration(hours: 24);
  static bool valid(
    DateTime? validatedAt,
    DateTime now, {
    bool revoked = false,
  }) =>
      !revoked &&
      validatedAt != null &&
      !now.isBefore(validatedAt.subtract(const Duration(minutes: 2))) &&
      now.isBefore(validatedAt.add(validity));

  static Actor cachedActor(
    Map<String, dynamic> saved,
    String userId,
    DateTime now,
  ) {
    final actor = Actor.fromJson(Map<String, dynamic>.from(saved['actor']));
    final stamp = DateTime.tryParse(saved['validatedAt'] ?? '');
    if (actor.id != userId ||
        !valid(stamp, now, revoked: saved['accessRevoked'] == true)) {
      throw const RuleException(
        'Conecta para revalidar tu cuenta. Los registros pendientes se conservan.',
      );
    }
    return actor;
  }
}
