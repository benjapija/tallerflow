import 'package:cryptography/cryptography.dart';
import 'vault.dart';

// Web is an ephemeral, synthetic-data preview. Native apps own the offline cache.
Future<Vault> openVault(String scope) async =>
    Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey());
