import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/text_capture.dart';
import 'package:tallerflow/domain/capture_draft.dart';
import 'package:tallerflow/ui/capture_dialog.dart';
import 'package:tallerflow/ui/dialogs.dart';

class FakeCapture implements TextCaptureBackend {
  int starts = 0, cancels = 0;
  void Function(String)? result;
  void Function(bool)? status;
  @override
  bool get cameraAvailable => true;
  @override
  Future<void> startVoice({
    required void Function(String) words,
    required void Function(bool) listening,
    required void Function(String) error,
  }) async {
    starts++;
    result = words;
    status = listening;
    listening(true);
    words('He trabajado 30 minutos');
  }

  @override
  Future<void> stopVoice() async {
    status?.call(false);
  }

  @override
  Future<void> cancelVoice() async {
    cancels++;
    status?.call(false);
  }

  @override
  Future<String?> cameraText() async => '4821LKR y 7392LKR';
}

void main() {
  testWidgets(
    'Partial dictation never saves, stop permits human edits, cancellation keeps original field',
    (tester) async {
      final backend = FakeCapture();
      String? value;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CaptureTextButton(
              kind: CaptureKind.technical,
              initial: 'Original',
              backend: backend,
              onReviewed: (v) => value = v,
            ),
          ),
        ),
      );
      expect(backend.starts, 0);
      await tester.tap(find.text('Capturar y revisar texto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dictar en español'));
      await tester.pumpAndSettle();
      expect(value, isNull);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'He revisado: usar texto'),
            )
            .onPressed,
        isNull,
      );
      backend.result?.call('He trabajado 30 minutos y comprobado el ruido');
      await tester.pump();
      await tester.tap(find.text('Detener dictado'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Texto revisado'),
        'Resultado revisado por operario',
      );
      await tester.tap(find.text('He revisado: usar texto'));
      await tester.pumpAndSettle();
      expect(value, 'Resultado revisado por operario');
      expect(backend.cancels, 1);
      await tester.tap(find.text('Capturar y revisar texto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(value, 'Resultado revisado por operario');
    },
  );
  testWidgets(
    'Several OCR candidates require a human choice and preserve editable text',
    (tester) async {
      String? value;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CaptureTextButton(
              kind: CaptureKind.plate,
              initial: '',
              backend: FakeCapture(),
              onReviewed: (v) => value = v,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Capturar y revisar texto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leer con cámara'));
      await tester.pumpAndSettle();
      expect(value, isNull);
      await tester.tap(find.text('He revisado: usar texto'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Revisar: 7392LKR'));
      await tester.pump();
      await tester.tap(find.text('He revisado: usar texto'));
      await tester.pumpAndSettle();
      expect(value, '7392LKR');
    },
  );
  testWidgets(
    'Revised capture fills the visible field and final payload only after both confirmations',
    (tester) async {
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  saved = await formDialog(
                    context,
                    'Ficticio',
                    [
                      const FieldSpec(
                        'text',
                        'Campo técnico',
                        initial: 'Original',
                        capture: CaptureKind.technical,
                      ),
                    ],
                    (v) => v,
                    captureBackend: FakeCapture(),
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Capturar y revisar texto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dictar en español'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detener dictado'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Texto revisado'),
        'Comprobación revisada',
      );
      await tester.tap(find.text('He revisado: usar texto'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.text('Comprobación revisada'), findsOneWidget);
      await tester.tap(find.text('Confirmar y guardar'));
      await tester.pumpAndSettle();
      expect(saved?['text'], 'Comprobación revisada');
    },
  );
}
