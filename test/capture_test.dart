import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/domain/capture_draft.dart';

void main() {
  test(
    'Plate proposals retain ambiguity and reject unsupported OCR letters',
    () {
      expect(
        captureCandidates(
          'Matrícula: 4821 LKR\n4821-LKR\n9200 FIC',
          CaptureKind.plate,
        ),
        ['4821LKR'],
      );
      expect(captureCandidates('4821IQR', CaptureKind.plate), isEmpty);
    },
  );
  test(
    'VIN proposals use valid characters without silently replacing I O or Q',
    () {
      expect(captureCandidates('VIN: WVWZZZ1KZAW123456', CaptureKind.vin), [
        'WVWZZZ1KZAW123456',
      ]);
      expect(captureCandidates('WVWZZZ1KZAW12345I', CaptureKind.vin), isEmpty);
    },
  );
  test('Several identifiers remain separate proposals for human choice', () {
    expect(
      captureCandidates('4821LKR y 7392LKR', CaptureKind.plate),
      hasLength(2),
    );
  });
  test(
    'Part reference keeps the exact observed value, independent of units or prices',
    () {
      expect(
        captureCandidates(
          'Oil-5W30\n0123456789012\nOil-5W30',
          CaptureKind.reference,
        ),
        ['Oil-5W30', '0123456789012'],
      );
    },
  );
  test(
    'Dictated time, quantities and prices remain text until separate operations',
    () {
      const text =
          'He trabajado 30 minutos y usado 1 litro de aceite por 12 euros';
      expect(reviewedCaptureValue(text, CaptureKind.technical), text);
      expect(captureCandidates(text, CaptureKind.technical), [text]);
    },
  );
  test('An empty or excessive draft cannot be confirmed', () {
    expect(
      () => reviewedCaptureValue(' ', CaptureKind.plate),
      throwsFormatException,
    );
    expect(
      () => reviewedCaptureValue('x' * 2001, CaptureKind.technical),
      throwsFormatException,
    );
  });
}
