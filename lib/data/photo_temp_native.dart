import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Never delete or reopen a user-selected original outside this app's cache.
Future<String?> privatePhotoSource(String path) async {
  try {
    final root = await (await getTemporaryDirectory()).resolveSymbolicLinks();
    final source = await File(path).resolveSymbolicLinks();
    final roots = [root];
    if (Platform.isIOS) {
      // image_picker saves camera images in the app's tmp directory, while
      // path_provider exposes Library/Caches. Never accept a shared OS tmp.
      final appContainer = Directory(root).parent.parent.path;
      final temporary = await Directory.systemTemp.resolveSymbolicLinks();
      if (p.isWithin(appContainer, temporary)) roots.add(temporary);
    }
    return roots.any((r) => p.isWithin(r, source)) ? source : null;
  } on FileSystemException {
    return null;
  }
}

Future<void> removeTemporaryPhoto(String path) async {
  final source = await privatePhotoSource(path);
  if (source != null) await File(source).delete();
}
