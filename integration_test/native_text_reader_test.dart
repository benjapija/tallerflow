import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tallerflow/data/text_capture.dart';
import 'package:tallerflow/data/photo_temp.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native OCR reads fictional images, orientation and private scope',
    (tester) async {
      expect(Platform.isIOS || Platform.isAndroid, isTrue);
      await tester.runAsync(() async {
        final root = await getTemporaryDirectory();
        final folder = await Directory(
          '${root.path}/tallerflow-ocr-fixture',
        ).create(recursive: true);
        final files = <File>[];
        final checks = <String>[];
        Future<File> save(img.Image image, String name) async {
          final file = File('${folder.path}/$name.jpg');
          files.add(file);
          await file.writeAsBytes(
            img.encodeJpg(image, quality: 95),
            flush: true,
          );
          return file;
        }

        try {
          final image = img.Image(width: 900, height: 300);
          img.fill(image, color: img.ColorRgb8(255, 255, 255));
          img.drawString(
            image,
            'P0300',
            font: img.arial48,
            x: 80,
            y: 60,
            color: img.ColorRgb8(0, 0, 0),
          );
          img.drawString(
            image,
            'ABC123',
            font: img.arial48,
            x: 80,
            y: 150,
            color: img.ColorRgb8(0, 0, 0),
          );
          final upright = await save(image, 'upright');
          expect(await privatePhotoSource(upright.path), isNotNull);
          final reader = LocalTextReader();
          final words = await reader.read(upright.path);
          expect(words, contains('P0300'));
          expect(words, contains('ABC123'));
          checks.add('upright fictional DTC and reference preserved');
          if (Platform.isIOS) {
            final cameraTemp = File(
              '${Directory.systemTemp.path}/tallerflow-ocr-camera-fixture.jpg',
            );
            files.add(cameraTemp);
            await cameraTemp.writeAsBytes(
              await upright.readAsBytes(),
              flush: true,
            );
            expect(await privatePhotoSource(cameraTemp.path), isNotNull);
            expect(await reader.read(cameraTemp.path), contains('P0300'));
            checks.add('iOS private camera temporary directory accepted');
          }

          final rotated = img.copyRotate(image, angle: 90);
          rotated.exif.imageIfd.orientation = 8;
          final oriented = await save(rotated, 'exif-left');
          expect(
            img
                .decodeJpg(await oriented.readAsBytes())!
                .exif
                .imageIfd
                .orientation,
            8,
          );
          final orientedWords = await reader.read(oriented.path);
          expect(orientedWords, contains('P0300'));
          expect(orientedWords, contains('ABC123'));
          checks.add('EXIF orientation restored before native OCR');

          final blank = img.Image(width: 900, height: 300);
          img.fill(blank, color: img.ColorRgb8(255, 255, 255));
          expect(
            (await reader.read((await save(blank, 'blank')).path)).trim(),
            isEmpty,
          );
          checks.add('blank image does not fabricate observations');

          final documents = await getApplicationDocumentsDirectory();
          final outside = File('${documents.path}/fictional-original-ocr.jpg');
          files.add(outside);
          await outside.writeAsBytes(await upright.readAsBytes(), flush: true);
          await expectLater(reader.read(outside.path), throwsFormatException);
          expect(await privatePhotoSource(outside.path), isNull);
          expect(await outside.exists(), isTrue);
          checks.add(
            'file outside private cache refused and original retained',
          );

          await expectLater(
            reader.read('${folder.path}/absent.jpg'),
            throwsFormatException,
          );
          checks.add('missing image is recoverable without technical details');
          final evidence = await Directory(
            '${documents.path}/native-test-evidence',
          ).create(recursive: true);
          await File('${evidence.path}/ocr.json').writeAsString(
            jsonEncode({
              'checkedAt': DateTime.now().toUtc().toIso8601String(),
              'platform': Platform.operatingSystem,
              'engine': Platform.isIOS
                  ? 'Apple Vision'
                  : 'Bundled ML Kit Latin',
              'checks': checks,
              'passed': checks.length,
              'physicalCameraValidated': false,
              'microphoneUsed': false,
              'hostedAuthValidated': false,
            }),
            flush: true,
          );
        } finally {
          for (final file in files) {
            if (await file.exists()) await file.delete();
          }
          if (await folder.exists()) await folder.delete();
        }
      });
      expect(tester.takeException(), isNull);
    },
  );
}
