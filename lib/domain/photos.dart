import 'dart:typed_data';
import 'package:image/image.dart' as img;

const maxPhotoBytes = 4 * 1024 * 1024;

/// Re-encode into a fresh image to remove location, EXIF and original filenames.
Uint8List prepareTechnicalPhoto(Uint8List input) {
  if (input.length > 16 * 1024 * 1024 || input.length < 8) {
    throw const FormatException('Usa una fotografía JPG o PNG de hasta 16 MB');
  }
  final png =
      input[0] == 137 && input[1] == 80 && input[2] == 78 && input[3] == 71;
  final jpeg = input[0] == 255 && input[1] == 216 && input[2] == 255;
  if (!png && !jpeg) {
    throw const FormatException('Selecciona una fotografía JPG o PNG');
  }
  final decoder = img.findDecoderForData(input);
  final info = decoder?.startDecode(input);
  if (info == null ||
      info.width <= 0 ||
      info.height <= 0 ||
      info.width * info.height > 20000000 ||
      info.numFrames != 1) {
    throw const FormatException(
      'Fotografía no admitida: máximo 20 megapíxeles y una imagen',
    );
  }
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) {
    throw const FormatException('No se puede leer la fotografía');
  }
  var oriented = img.bakeOrientation(decoded);
  if (oriented.width > 1920 || oriented.height > 1920) {
    oriented = oriented.width >= oriented.height
        ? img.copyResize(oriented, width: 1920)
        : img.copyResize(oriented, height: 1920);
  }
  final clean = img.Image(
    width: oriented.width,
    height: oriented.height,
    numChannels: 3,
  );
  img.fill(clean, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(clean, oriented);
  final bytes = Uint8List.fromList(img.encodeJpg(clean, quality: 82));
  if (bytes.length > maxPhotoBytes) {
    throw const FormatException('La fotografía es demasiado grande');
  }
  return bytes;
}

Map<String, dynamic> photoUploadPayload(Map<String, dynamic> p) => {
  for (final k in [
    'id',
    'orderId',
    'sha256',
    'size',
    'mime',
    'caption',
    'capturedAt',
    'originalDeviceId',
  ])
    k: p[k],
};
