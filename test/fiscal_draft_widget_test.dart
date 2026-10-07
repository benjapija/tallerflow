import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/domain/models.dart';
import 'package:tallerflow/domain/fiscal_drafts.dart';
import 'package:tallerflow/ui/app.dart';
import 'package:tallerflow/ui/fiscal_drafts_panel.dart';

const _admin = Actor('admin-test', 'Administradora ficticia', Role.admin);
const _draftId = '00000000-0000-4000-8000-000000000101';
Map<String, dynamic> _payload() => {
  'issuerNif': 'B12345678',
  'installation': 'PRUEBAS-1',
  'prefix': 'ENSAYO-TALLER',
  'issueDate': '2026-10-07',
  'recipient': {'name': 'Cliente ficticio', 'nif': 'A12345678'},
  'reason': 'Prueba ficticia de la interfaz',
  'lines': [
    {
      'id': '00000000-0000-4000-8000-000000000102',
      'description': 'Trabajo ficticio',
      'unitCents': 1000,
      'quantityMilli': 1000,
      'discountBps': 0,
      'taxBps': 2100,
      'tax': 'iva',
      'treatment': 'taxable',
      'reason': '',
    },
  ],
};

// Fixed presentation fixture; arithmetic is exercised by domain tests.
Map<String, dynamic> _calculation(List<Map<String, dynamic>> lines) => {
  'lines': [
    for (final line in lines)
      {...line, 'baseCents': 1000, 'taxCents': 210, 'totalCents': 1210},
  ],
  'baseCents': 1000,
  'taxCents': 210,
  'totalCents': 1210,
};

Map<String, dynamic> _record() => {
  'id': _draftId,
  'ledger_hash': 'A' * 64,
  'body': {
    ..._payload(),
    'id': _draftId,
    'kind': 'draft',
    'sequence': 1,
    'number': 1,
    'actorId': _admin.id,
    'deviceId': 'dispositivo-ficticio',
    'createdAt': '2026-10-07T15:00:00Z',
    'calculation': _calculation(
      (_payload()['lines'] as List).cast<Map<String, dynamic>>(),
    ),
  },
};

Widget _panel({
  Actor actor = _admin,
  bool accessAllowed = true,
  bool offline = false,
  bool demo = false,
  Map<String, dynamic> fiscalProfile = const {
    'territory': 'common',
    'sii': 'no',
  },
  Map<String, dynamic>? ledger,
  List<Map<String, dynamic>> queue = const [],
  Future<void> Function(Map<String, dynamic>)? onPrepare,
  Future<void> Function(String, String)? onWithdraw,
  Future<void> Function(String)? onRetry,
  Future<void> Function(String, String)? onReview,
}) => FiscalDraftsPanel(
  actor: actor,
  accessAllowed: accessAllowed,
  offline: offline,
  demo: demo,
  loaded: true,
  ledger: ledger ?? {'heads': [], 'records': []},
  fiscalProfile: fiscalProfile,
  queue: queue,
  history: const [],
  calculate: fiscalDraftCalculation,
  onPrepare: onPrepare ?? (_) async {},
  onWithdraw: onWithdraw ?? (_, _) async {},
  onRefresh: () async {},
  onRetry: onRetry ?? (_) async {},
  onReview: onReview ?? (_, _) async {},
);

Future<void> _show(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: tallerTheme(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Only active administrator sees records; expired session hides cached data',
    (tester) async {
      for (final actor in [
        const Actor('office', 'Oficina', Role.office),
        const Actor('operator', 'Operario', Role.technician),
        const Actor(
          'inactive',
          'Administrador retirado',
          Role.admin,
          active: false,
        ),
      ]) {
        await _show(
          tester,
          _panel(
            actor: actor,
            ledger: {
              'records': [_record()],
            },
          ),
        );
        expect(find.text('Preparar ensayo'), findsNothing);
        expect(find.textContaining('ENSAYO-TALLER-1'), findsNothing);
      }
      await _show(
        tester,
        _panel(
          accessAllowed: false,
          ledger: {
            'records': [_record()],
          },
        ),
      );
      expect(
        find.text('Renueva tu sesión para consultar y registrar ensayos.'),
        findsOneWidget,
      );
      expect(find.textContaining('ENSAYO-TALLER-1'), findsNothing);
      expect(find.textContaining('Cliente ficticio'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Local pending, rejected and conflict requests never receive a server number',
    (tester) async {
      final queue = [
        for (final status in ['pending', 'rejected', 'conflict'])
          {
            'id': 'request-$status',
            'action': 'fiscal_draft_append',
            'payload': _payload(),
            'status': status,
          },
      ];
      await _show(tester, _panel(offline: true, queue: queue));
      expect(find.text('Pendiente local · sin confirmación'), findsOneWidget);
      expect(find.text('Rechazada'), findsOneWidget);
      expect(find.text('En conflicto · requiere revisión'), findsOneWidget);
      expect(find.textContaining('Confirmado por el servidor'), findsNothing);
      expect(find.textContaining('ENSAYO-TALLER-1'), findsNothing);
      expect(
        find.textContaining('Emisión y transmisión fiscal desactivadas'),
        findsOneWidget,
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('fiscal-command-request-pending')),
      );
      final retry = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Reintentar misma solicitud'),
      );
      expect(retry.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Demo cannot label a local result as confirmed by server', (
    tester,
  ) async {
    await _show(
      tester,
      _panel(
        demo: true,
        ledger: {
          'records': [_record()],
        },
        queue: [
          {
            'id': 'local',
            'status': 'confirmed',
            'action': 'fiscal_draft_append',
            'payload': _payload(),
          },
        ],
      ),
    );
    expect(find.text('Confirmada por el servidor'), findsNothing);
    expect(find.text('Confirmado por el servidor'), findsNothing);
    expect(
      find.textContaining('sin confirmación del servidor'),
      findsOneWidget,
    );
    expect(find.text('Ensayo local · sin servidor'), findsOneWidget);
  });

  testWidgets(
    'Unknown, SII and foral profile keep preparation disabled without choosing obligations',
    (tester) async {
      for (final profile in [
        {'sii': 'unknown', 'territory': 'unknown'},
        {'sii': 'yes', 'territory': 'common'},
        {'sii': 'no', 'territory': 'bizkaia'},
      ]) {
        await _show(tester, _panel(fiscalProfile: profile));
        final prepare = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Preparar ensayo'),
        );
        expect(prepare.onPressed, isNull);
        expect(
          find.textContaining('Conserva pendientes los datos desconocidos'),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Review is a separate step and only explicit save returns unchanged payload',
    (tester) async {
      Map<String, dynamic>? saved;
      await _show(
        tester,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              saved = await showDialog<Map<String, dynamic>>(
                context: context,
                builder: (_) => FiscalDraftEditor(
                  initial: _payload(),
                  calculate: _calculation,
                ),
              );
            },
            child: const Text('Abrir editor'),
          ),
        ),
      );
      await _tap(tester, find.text('Abrir editor'));
      final reason = find.widgetWithText(TextFormField, 'Motivo del ensayo');
      await tester.ensureVisible(reason);
      await tester.enterText(reason, 'Revisión humana de datos ficticios');
      await _tap(tester, find.text('Revisar ensayo'));
      expect(saved, isNull);
      expect(find.text('Total revisado: 12,10 €'), findsOneWidget);
      expect(
        find.textContaining(
          'El número de ensayo se asigna al confirmar el servidor',
        ),
        findsOneWidget,
      );
      expect(find.text('Guardar solicitud de ensayo'), findsOneWidget);
      await _tap(tester, find.text('Guardar solicitud de ensayo'));
      expect(saved!['reason'], 'Revisión humana de datos ficticios');
      expect(saved!['lines'], _payload()['lines']);
      expect(saved!.containsKey('number'), isFalse);
      expect(saved!.containsKey('expectedHash'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Administrator prepares and reviews a decimal line through the panel',
    (tester) async {
      Map<String, dynamic>? submitted;
      await _show(
        tester,
        _panel(
          onPrepare: (payload) async {
            submitted = payload;
          },
        ),
      );
      await _tap(tester, find.text('Preparar ensayo'));
      Future<void> fill(String label, String value) async {
        final field = find.widgetWithText(TextFormField, label);
        await tester.ensureVisible(field);
        await tester.enterText(field, value);
      }

      await fill('NIF del emisor de ensayo', 'b12345678');
      await fill('Instalación de ensayo', 'PRUEBAS-UI');
      await fill('Nombre del destinatario ficticio', 'Cliente ficticio');
      await fill('NIF del destinatario ficticio', 'a12345678');
      await fill('Motivo del ensayo', 'Revisión de preparación ficticia');
      await _tap(tester, find.text('Añadir partida'));
      await fill('Descripción', 'Aceite ficticio');
      await fill('Cantidad', '1,5');
      await fill('Precio por unidad (€)', '10,00');
      await fill('Descuento (%)', '10,00');
      await _tap(tester, find.text('Confirmar y guardar'));
      await _tap(tester, find.text('Revisar ensayo'));
      expect(submitted, isNull);
      expect(find.text('Total revisado: 16,34 €'), findsOneWidget);
      await _tap(tester, find.text('Guardar solicitud de ensayo'));
      expect(submitted!['issuerNif'], 'B12345678');
      expect(submitted!['recipient']['nif'], 'A12345678');
      expect(submitted!['lines'].single['quantityMilli'], 1500);
      expect(submitted!['lines'].single['discountBps'], 1000);
      expect(submitted!.containsKey('number'), isFalse);
      expect(
        find.textContaining('solo el servidor confirma el registro'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Recovered installation is visible but cannot continue or withdraw originals',
    (tester) async {
      final head = {
        'issuer_nif': 'B12345678',
        'installation': 'PRUEBAS-1',
        'restored': true,
      };
      await _show(
        tester,
        _panel(
          ledger: {
            'heads': [head],
            'records': [_record()],
          },
        ),
      );
      await _tap(tester, find.byKey(const ValueKey('fiscal-record-$_draftId')));
      expect(find.text('Retirar con motivo'), findsNothing);
      expect(
        find.textContaining('Las instalaciones recuperadas están congeladas'),
        findsOneWidget,
      );
      await _show(
        tester,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => FiscalDraftEditor(
                initial: _payload(),
                calculate: _calculation,
                frozenHeads: [head],
              ),
            ),
            child: const Text('Abrir editor'),
          ),
        ),
      );
      await _tap(tester, find.text('Abrir editor'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo del ensayo'),
        'Prueba de recuperación',
      );
      await _tap(tester, find.text('Revisar ensayo'));
      expect(
        find.textContaining('Esta instalación recuperada está congelada'),
        findsOneWidget,
      );
      expect(find.text('Guardar solicitud de ensayo'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Withdrawal requires reason and never changes the original display before confirmation',
    (tester) async {
      String? id, reason;
      final original = _record();
      await _show(
        tester,
        _panel(
          ledger: {
            'records': [original],
          },
          onWithdraw: (i, r) async {
            id = i;
            reason = r;
          },
        ),
      );
      await _tap(tester, find.byKey(const ValueKey('fiscal-record-$_draftId')));
      await _tap(tester, find.text('Retirar con motivo'));
      await _tap(tester, find.text('Confirmar y guardar'));
      expect(id, isNull);
      expect(find.text('Completa este campo'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField),
        'Ensayo descartado tras revisión ficticia',
      );
      await _tap(tester, find.text('Confirmar y guardar'));
      expect(id, _draftId);
      expect(reason, 'Ensayo descartado tras revisión ficticia');
      expect(original['body']['number'], 1);
      expect(
        find.textContaining('retirado mediante registro posterior'),
        findsNothing,
      );
      expect(
        find.text(
          'Solicitud de retirada conservada. Consulta su estado de confirmación.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Retry preserves request identity; conflict review cannot resend',
    (tester) async {
      String? retryId, reviewedId, reviewReason;
      var prepared = 0;
      final original = _payload();
      await _show(
        tester,
        _panel(
          queue: [
            {
              'id': 'uncertain-request',
              'action': 'fiscal_draft_append',
              'payload': original,
              'status': 'pending',
            },
            {
              'id': 'conflicting-request',
              'action': 'fiscal_draft_append',
              'payload': original,
              'status': 'conflict',
              'error': 'La cadena cambió',
            },
          ],
          onRetry: (id) async {
            retryId = id;
          },
          onReview: (id, reason) async {
            reviewedId = id;
            reviewReason = reason;
          },
          onPrepare: (_) async {
            prepared++;
          },
        ),
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('fiscal-command-uncertain-request')),
      );
      await _tap(tester, find.text('Reintentar misma solicitud'));
      expect(retryId, 'uncertain-request');
      await _tap(
        tester,
        find.byKey(const ValueKey('fiscal-command-conflicting-request')),
      );
      await _tap(tester, find.text('Registrar revisión'));
      await tester.enterText(
        find.byType(TextFormField),
        'Contenido revisado; se conserva el rechazo',
      );
      await _tap(tester, find.text('Confirmar y guardar'));
      expect(reviewedId, 'conflicting-request');
      expect(reviewReason, 'Contenido revisado; se conserva el rechazo');
      expect(prepared, 0);
      expect(original, _payload());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Mobile layout wraps identifiers and preserves server record details',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _show(
        tester,
        _panel(
          ledger: {
            'records': [_record()],
          },
        ),
      );
      await _tap(tester, find.byKey(const ValueKey('fiscal-record-$_draftId')));
      expect(find.text('Total registrado: 12,10 €'), findsOneWidget);
      expect(
        find.textContaining('Esta huella no es la huella AEAT'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
