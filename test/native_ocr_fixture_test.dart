import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test(
    'OCR fixture retains raw EXIF before decoding normalizes its pixels',
    () {
      final upright = img.Image(width: 900, height: 300);
      final rotated = img.copyRotate(upright, angle: 90);
      rotated.exif.imageIfd.orientation = 8;
      final bytes = img.encodeJpg(rotated, quality: 95);

      expect(img.decodeJpgExif(bytes)!.imageIfd.orientation, 8);
      final normalized = img.decodeJpg(bytes)!;
      expect(normalized.width, upright.width);
      expect(normalized.height, upright.height);
      expect(normalized.exif.imageIfd.orientation, isNull);
    },
  );
}
