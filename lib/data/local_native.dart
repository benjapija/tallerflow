import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'vault.dart';

class AtomicFileStore implements StringStore {
  final File file;
  AtomicFileStore(this.file);
  @override
  Future<String?> read() async {
    if (await file.exists()) return file.readAsString();
    final next = File('${file.path}.next');
    if (await next.exists()) return next.readAsString();
    final backup = File('${file.path}.previous');
    // Recovery of a interrupted rotation; no empty-store fallback on corrupt data.
    if (await backup.exists()) return backup.readAsString();
    return null;
  }

  @override
  Future<void> write(String value) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.next');
    await temporary.writeAsString(value, flush: true);
    final previous = File('${file.path}.previous');
    if (await previous.exists()) await previous.delete();
    if (await file.exists()) await file.rename(previous.path);
    await temporary.rename(file.path);
  }
}

Future<Vault> openVault(String scope) async {
  const secure = FlutterSecureStorage();
  final folder = await getApplicationSupportDirectory();
  final file = File('${folder.path}/$scope.vault');
  final keyName = 'tallerflow-key-$scope';
  var encoded = await secure.read(key: keyName);
  if (encoded == null) {
    if (await file.exists() ||
        await File('${file.path}.previous').exists() ||
        await File('${file.path}.next').exists()) {
      throw StateError(
        'Falta la clave del almacén local. No se sobrescribirán los registros.',
      );
    }
    encoded = base64Encode(
      await AesGcm.with256bits().newSecretKey().then((k) => k.extractBytes()),
    );
    await secure.write(key: keyName, value: encoded);
  }
  return Vault(AtomicFileStore(file), SecretKey(base64Decode(encoded)));
}
