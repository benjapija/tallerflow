import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/fiscal_calculation.dart';
import 'package:tallerflow/domain/fiscal_profile.dart';
import 'package:tallerflow/domain/verifactu_draft.dart';
import 'package:tallerflow/domain/verifactu_hash.dart';

final preparation = {
  ...initialFiscalProfile(),
  'territory': 'common',
  'sii': 'no',
};
VerifactuIdentity identity([String number = '12345678/G33']) =>
    VerifactuIdentity(
      issuerNif: '89890001K',
      number: number,
      issueDate: '01-01-2024',
    );
final issuer = VerifactuParty(
  name: 'Emisor ficticio Álvarez & Hijos',
  nif: '89890001K',
);
final recipient = VerifactuParty(
  name: 'Cliente ficticio <ejemplo>',
  nif: '12345678Z',
);
final system = VerifactuSystem(
  manufacturer: VerifactuParty(name: 'Fabricante ficticio', nif: '12345678Z'),
  name: 'TallerFlow ensayo',
  id: 'TF',
  version: 'ensayo-1',
  installation: 'INSTALACION-FICTICIA',
  onlyVerifactu: true,
  canHaveMultipleTaxpayers: true,
  hasMultipleTaxpayers: false,
);
FiscalCalculation calculation({FiscalTax tax = FiscalTax.iva}) =>
    FiscalCalculation.calculate([
      FiscalLine(
        id: 'one',
        description: 'Trabajo ficticio',
        quantityMilli: 1000,
        unitPriceCents: 10000,
        rateBps: 2100,
        tax: tax,
      ),
    ]);
Future<VerifactuOfflineDraft> draft({
  Map<String, dynamic>? profile,
  FiscalCalculation? c,
  List<VerifactuDetail>? details,
  VerifactuAnchor? previous,
  String at = '2024-01-01T19:20:30+01:00',
}) {
  final calc = c ?? calculation();
  return VerifactuOfflineDraft.high(
    preparation: profile ?? preparation,
    identity: identity(),
    issuer: issuer,
    recipient: recipient,
    system: system,
    calculation: calc,
    details:
        details ??
        [
          for (final g in calc.groups)
            VerifactuDetail(group: g, regime: '01', classification: 'S1'),
        ],
    description: 'Revisión ficticia & <sin emisión>',
    generatedAt: at,
    previous: previous,
  );
}

void main() {
  test(
    'Three official AEAT SHA-256 vectors reproduce published uppercase hashes',
    () async {
      final first = await VerifactuHash.high(
        identity: identity(),
        invoiceType: 'F1',
        taxTotal: '12.35',
        total: '123.45',
        generatedAt: '2024-01-01T19:20:30+01:00',
      );
      expect(
        first.hex,
        '3C464DAF61ACB827C65FDA19F352A4E3BDC2C640E9E9FC4CC058073F38F12F60',
      );
      final second = await VerifactuHash.high(
        identity: identity('12345679/G34'),
        invoiceType: 'F1',
        taxTotal: '12.35',
        total: '123.45',
        previousHash: first.hex,
        generatedAt: '2024-01-01T19:20:35+01:00',
      );
      expect(
        second.hex,
        'F7B94CFD8924EDFF273501B01EE5153E4CE8F259766F88CF6ACB8935802A2B97',
      );
      final cancellation = await VerifactuHash.cancellation(
        identity: identity('12345679/G34'),
        previousHash: second.hex,
        generatedAt: '2024-01-01T19:20:40+01:00',
      );
      expect(
        cancellation.hex,
        '177547C0D57AC74748561D054A9CEC14B4C4EA23D1BEFD6F2E69E3A388F90C68',
      );
    },
  );
  test(
    'Hash trims fields, preserves numeric representation and encodes QR delimiters',
    () async {
      final id = VerifactuIdentity(
        issuerNif: ' 89890001K ',
        number: ' 12345678&G33 ',
        issueDate: '01-01-2024',
      );
      final hash = await VerifactuHash.high(
        identity: id,
        invoiceType: 'F1',
        taxTotal: ' 12.3 ',
        total: '123.4',
        generatedAt: '2024-01-01T19:20:30+01:00',
      );
      expect(hash.canonical, contains('NumSerieFactura=12345678&G33'));
      expect(hash.canonical, contains('CuotaTotal=12.3'));
      final qr = verifactuTestQr(id, 24140);
      expect(qr.host, 'prewww2.aeat.es');
      expect(qr.queryParameters.length, 4);
      expect(qr.queryParameters['numserie'], '12345678&G33');
      expect(qr.toString(), contains('numserie=12345678%26G33'));
      expect(qr.queryParameters['importe'], '241.40');
    },
  );
  test(
    'Invalid dates, timezone, serials, decimal commas and previous hashes are rejected',
    () async {
      expect(() => identity('bad\nserial'), throwsA(isA<RuleException>()));
      expect(
        () => VerifactuIdentity(
          issuerNif: '89890001K',
          number: '1',
          issueDate: '31-02-2024',
        ),
        throwsA(isA<RuleException>()),
      );
      for (final at in [
        '2024-01-01T19:20:30',
        '2024-01-01T25:20:30+01:00',
        '2024-01-01T19:20:30+14:01',
      ]) {
        await expectLater(
          VerifactuHash.cancellation(identity: identity(), generatedAt: at),
          throwsA(isA<RuleException>()),
        );
      }
      await expectLater(
        VerifactuHash.high(
          identity: identity(),
          invoiceType: 'F1',
          taxTotal: '12,3',
          total: '123.4',
          generatedAt: '2024-01-01T19:20:30+01:00',
        ),
        throwsA(isA<RuleException>()),
      );
      await expectLater(
        VerifactuHash.cancellation(
          identity: identity(),
          previousHash: 'incorrect',
          generatedAt: '2024-01-01T19:20:30+01:00',
        ),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Offline XML uses exact totals, escaping, chain and explicitly disabled gates',
    () async {
      final high = await draft();
      final cancellation = await VerifactuOfflineDraft.cancellation(
        preparation: preparation,
        identity: identity(),
        issuer: issuer,
        system: system,
        generatedAt: '2024-01-01T19:20:31+01:00',
        previous: high.anchor,
      );
      expect(high.xml, contains('Álvarez &amp; Hijos'));
      expect(high.xml, contains('&lt;sin emisión&gt;'));
      expect(high.xml, contains('<sf:CuotaTotal>21.00</sf:CuotaTotal>'));
      expect(high.xml, contains('<sf:ImporteTotal>121.00</sf:ImporteTotal>'));
      expect(high.xml, contains('<sf:PrimerRegistro>S</sf:PrimerRegistro>'));
      expect(cancellation.xml, contains('<sf:RegistroAnterior>'));
      expect(cancellation.hash.canonical, contains('Huella=${high.hash.hex}'));
      expect(high.emissionEnabled, false);
      expect(high.transmissionEnabled, false);
      // Local/CI fixture evidence; fictional identities, no network calls.
      if (const bool.fromEnvironment('WRITE_FISCAL_EVIDENCE')) {
        final dir = Directory('build/fiscal-fixtures')
          ..createSync(recursive: true);
        File('${dir.path}/high.xml').writeAsStringSync(high.xml);
        File(
          '${dir.path}/cancellation.xml',
        ).writeAsStringSync(cancellation.xml);
        File('${dir.path}/hashes.json').writeAsStringSync(
          jsonEncode({
            'high': high.hash.hex,
            'cancellation': cancellation.hash.hex,
            'emissionEnabled': false,
            'transmissionEnabled': false,
          }),
        );
      }
    },
  );
  test(
    'SII, unknown and foral profiles cannot silently use the state adapter',
    () async {
      for (final territory in [
        'unknown',
        'navarra',
        'alava',
        'bizkaia',
        'gipuzkoa',
      ]) {
        await expectLater(
          draft(profile: {...preparation, 'territory': territory}),
          throwsA(isA<RuleException>()),
        );
      }
      for (final sii in ['yes', 'unknown']) {
        await expectLater(
          draft(profile: {...preparation, 'sii': sii}),
          throwsA(isA<RuleException>()),
        );
      }
      await expectLater(
        draft(profile: {...preparation, 'emissionEnabled': true}),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Tax codes distinguish IVA, IGIC and IPSI without choosing legal rates',
    () async {
      final codes = {
        FiscalTax.iva: '01',
        FiscalTax.igic: '03',
        FiscalTax.ipsi: '02',
        FiscalTax.other: '05',
      };
      for (final e in codes.entries) {
        final high = await draft(c: calculation(tax: e.key));
        expect(high.xml, contains('<sf:Impuesto>${e.value}</sf:Impuesto>'));
      }
    },
  );
  test(
    'Missing/duplicate/unrelated details, classifications and corrections are rejected',
    () async {
      final c = calculation();
      await expectLater(
        draft(c: c, details: []),
        throwsA(isA<RuleException>()),
      );
      final detail = VerifactuDetail(
        group: c.groups.first,
        regime: '01',
        classification: 'S1',
      );
      await expectLater(
        draft(c: c, details: [detail, detail]),
        throwsA(isA<RuleException>()),
      );
      expect(
        () => VerifactuDetail(
          group: c.groups.first,
          regime: '99',
          classification: 'S1',
        ),
        throwsA(isA<RuleException>()),
      );
      expect(
        () => VerifactuDetail(
          group: c.groups.first,
          regime: '01',
          classification: 'S2',
        ),
        throwsA(isA<RuleException>()),
      );
      final correction = FiscalCalculation.calculate([
        FiscalLine(
          id: 'credit',
          description: 'Ajuste',
          quantityMilli: 1000,
          unitPriceCents: -100,
          rateBps: 2100,
          tax: FiscalTax.iva,
        ),
      ], adjustmentReason: 'Ficticio');
      await expectLater(draft(c: correction), throwsA(isA<RuleException>()));
    },
  );
  test(
    'Other taxpayer chains and reversed timestamps cannot be mixed; equal seconds are ordered separately',
    () async {
      final high = await draft();
      final sameSecond = await draft(previous: high.anchor);
      expect(sameSecond.xml, contains('<sf:RegistroAnterior>'));
      await expectLater(
        draft(previous: high.anchor, at: '2024-01-01T19:20:29+01:00'),
        throwsA(isA<RuleException>()),
      );
      final foreign = VerifactuAnchor(
        identity: VerifactuIdentity(
          issuerNif: '12345678Z',
          number: 'OTHER',
          issueDate: '01-01-2024',
        ),
        hash: high.hash.hex,
        generatedAt: high.anchor.generatedAt,
      );
      await expectLater(
        draft(previous: foreign, at: '2024-01-01T19:20:31+01:00'),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Reverse charge S2 explicitly serializes the zero rate and quota required by AEAT',
    () async {
      final calculation = FiscalCalculation.calculate([
        FiscalLine(
          id: 'reverse',
          description: 'Ensayo ficticio',
          quantityMilli: 1000,
          unitPriceCents: 10000,
          rateBps: 0,
          tax: FiscalTax.iva,
          treatment: FiscalTreatment.reverseCharge,
          legalReason: 'Motivo ficticio',
        ),
      ]);
      final high = await draft(
        c: calculation,
        details: [
          VerifactuDetail(
            group: calculation.groups.single,
            regime: '01',
            classification: 'S2',
          ),
        ],
      );
      expect(high.xml, contains('<sf:TipoImpositivo>0.00</sf:TipoImpositivo>'));
      expect(
        high.xml,
        contains('<sf:CuotaRepercutida>0.00</sf:CuotaRepercutida>'),
      );
    },
  );
}
