import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/text_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(LocalTextReader.channel, null),
  );

  test(
    'Local reader preserves observations without interpreting them',
    () async {
      messenger.setMockMethodCallHandler(LocalTextReader.channel, (call) async {
        expect(call.method, 'read');
        expect(call.arguments, {'path': '/private/cache/fictional.jpg'});
        return 'P0300\nReferencia ABC-123 · comprobar';
      });
      expect(
        await LocalTextReader().read('/private/cache/fictional.jpg'),
        'P0300\nReferencia ABC-123 · comprobar',
      );
    },
  );

  test(
    'Reader rejects absent or oversized results without truncation',
    () async {
      for (final reply in [null, 'x' * 4001]) {
        messenger.setMockMethodCallHandler(
          LocalTextReader.channel,
          (_) async => reply,
        );
        await expectLater(
          LocalTextReader().read('/private/cache/f.jpg'),
          throwsFormatException,
        );
      }
      messenger.setMockMethodCallHandler(
        LocalTextReader.channel,
        (_) async => '',
      );
      expect(await LocalTextReader().read('/private/cache/f.jpg'), '');
    },
  );

  test(
    'Reader makes native failure recoverable and hides private paths',
    () async {
      messenger.setMockMethodCallHandler(LocalTextReader.channel, (_) async {
        throw PlatformException(
          code: 'IMAGE_INVALID',
          message: '/private/cache/secret.jpg',
        );
      });
      await expectLater(
        LocalTextReader().read('/private/cache/f.jpg'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            isNot(contains('secret.jpg')),
          ),
        ),
      );
      await expectLater(LocalTextReader().read(''), throwsFormatException);
    },
  );
}
