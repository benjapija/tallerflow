import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'photo_temp.dart';

/// Readers return observations only; a person reviews them in the dialog.
class LocalTextReader {
  static const channel = MethodChannel('es.tallerflow/local_text');

  Future<String> read(String privatePath) async {
    if (privatePath.isEmpty) {
      throw const FormatException('No se ha podido abrir la imagen capturada.');
    }
    try {
      final text = await channel.invokeMethod<String>('read', {
        'path': privatePath,
      });
      if (text == null || text.length > 4000) {
        throw const FormatException(
          'La captura no contiene un texto válido de hasta 4.000 caracteres. Acércate a la zona necesaria y repite la captura.',
        );
      }
      return text;
    } on PlatformException {
      throw const FormatException(
        'No se ha podido leer la imagen. Repite la captura o escribe el texto.',
      );
    } on MissingPluginException {
      throw const FormatException(
        'La lectura de texto requiere la aplicación móvil actualizada.',
      );
    }
  }
}

abstract class TextCaptureBackend {
  bool get cameraAvailable;
  Future<void> startVoice({
    required void Function(String) words,
    required void Function(bool) listening,
    required void Function(String) error,
  });
  Future<void> stopVoice();
  Future<void> cancelVoice();
  Future<String?> cameraText();
}

class DeviceTextCapture implements TextCaptureBackend {
  static final instance = DeviceTextCapture._();
  DeviceTextCapture._();
  final _speech = SpeechToText();
  void Function(bool)? _listening;
  void Function(String)? _error;
  @override
  bool get cameraAvailable =>
      !kIsWeb &&
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ].contains(defaultTargetPlatform);
  @override
  Future<void> startVoice({
    required void Function(String) words,
    required void Function(bool) listening,
    required void Function(String) error,
  }) async {
    _listening = listening;
    _error = error;
    final available = await _speech.initialize(
      onStatus: (s) => _listening?.call(s == 'listening'),
      onError: (_) => _error?.call(
        'No se ha podido reconocer la voz. Revisa el borrador o escribe el texto.',
      ),
    );
    if (!available) {
      throw const FormatException(
        'El reconocimiento de voz no está disponible o no tiene permiso. Puedes escribir el texto.',
      );
    }
    final locales = await _speech.locales();
    final spanish =
        locales
            .where(
              (l) => l.localeId.toLowerCase().replaceAll('-', '_') == 'es_es',
            )
            .firstOrNull ??
        locales
            .where((l) => l.localeId.toLowerCase().startsWith('es'))
            .firstOrNull;
    if (spanish == null) {
      throw const FormatException(
        'Activa el reconocimiento en español en el equipo o escribe el texto.',
      );
    }
    await _speech.listen(
      onResult: (r) => words(r.recognizedWords),
      listenOptions: SpeechListenOptions(
        localeId: spanish.localeId,
        listenFor: const Duration(seconds: 45),
        pauseFor: const Duration(seconds: 4),
        onDevice: true,
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
    );
    listening(_speech.isListening);
  }

  @override
  Future<void> stopVoice() => _speech.stop();
  @override
  Future<void> cancelVoice() async {
    if (_speech.isListening) await _speech.cancel();
    _listening = null;
    _error = null;
  }

  @override
  Future<String?> cameraText() async {
    if (!cameraAvailable) {
      throw const FormatException(
        'La lectura por cámara está disponible en Android e iPhone. Puedes escribir el texto.',
      );
    }
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 95,
      requestFullMetadata: false,
    );
    if (photo == null) return null;
    try {
      final path = await privatePhotoSource(photo.path);
      if (path == null) {
        throw const FormatException(
          'La imagen debe estar en la caché privada.',
        );
      }
      return await LocalTextReader().read(path);
    } finally {
      await removeTemporaryPhoto(photo.path);
    }
  }
}
