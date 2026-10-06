import 'dart:io';
import 'package:image/image.dart' as image;

void main(List<String> arguments) {
  final picture = image.Image(width: 16, height: 12);
  image.fill(picture, color: image.ColorRgb8(40, 130, 105));
  File(
    arguments.single,
  ).writeAsBytesSync(image.encodeJpg(picture, quality: 80));
}
