import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Never delete or reopen a user-selected original outside this app's cache.
Future<String?> privatePhotoSource(String path) async {
  try {
    final root = await (await getTemporaryDirectory()).resolveSymbolicLinks();
    final source = await File(path).resolveSymbolicLinks();
    return p.isWithin(root, source) ? source : null;
  } on FileSystemException {
    return null;
  }
}

Future<void> removeTemporaryPhoto(String path) async {
  final source = await privatePhotoSource(path);
  if (source != null) await File(source).delete();
}
