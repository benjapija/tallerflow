import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/fiscal_calculation.dart';
import 'package:tallerflow/domain/fiscal_document_rules.dart';
import 'package:tallerflow/domain/verifactu_hash.dart';

const day = '07-10-2026';
final error = throwsA(isA<RuleException>());

FiscalLine item({
  String id = 'one',
  int base = 10000,
  int rate = 2100,
  FiscalTax tax = FiscalTax.iva,
  FiscalTreatment treatment = FiscalTreatment.taxable,
}) => FiscalLine(
  id: id,
  description: 'Servicio ficticio',
  quantityMilli: 1000,
  unitPriceCents: base,
  rateBps: rate,
  tax: tax,
  treatment: treatment,
  legalReason: treatment == FiscalTreatment.taxable ? '' : 'Motivo ficticio',
);

FiscalDocumentCharges money({
  int base = 10000,
  int rate = 2100,
  String date = day,
  Iterable<FiscalLine>? lines,
  Iterable<FiscalEquivalenceSurcharge> surcharges = const [],
  Iterable<FiscalWithholding> withholdings = const [],
  String adjustment = '',
}) => FiscalDocumentCharges.calculate(
  FiscalCalculation.calculate(
    lines ?? [item(base: base, rate: rate)],
    adjustmentReason: adjustment,
  ),
  operationDate: date,
  surcharges: surcharges,
  withholdings: withholdings,
);

FiscalDocumentParty party({String nif = 'B12345678'}) => FiscalDocumentParty(
  name: 'Taller ficticio',
  address: 'Calle de ensayo 1',
  country: 'ES',
  nif: nif,
);

FiscalOriginalReference source({
  String type = 'F1',
  String series = 'ENSAYO-F',
  String issueDate = day,
  String operationDate = day,
  int base = 10000,
  int tax = 2100,
  int surcharge = 0,
  int withholding = 0,
  FiscalDocumentCharges? savedCharges,
}) => FiscalOriginalReference(
  recordId: 'original-record',
  series: series,
  sourceHash: 'A' * 64,
  type: type,
  identity: VerifactuIdentity(
    issuerNif: 'B12345678',
    number: '$series/000001',
    issueDate: issueDate,
  ),
  operationDate: operationDate,
  baseCents: base,
  taxCents: tax,
  surchargeCents: surcharge,
  withholdingCents: withholding,
  savedCharges: savedCharges,
);

FiscalRectification rectification(
  FiscalOriginalReference original, {
  FiscalRectificationMethod method = FiscalRectificationMethod.differences,
  FiscalRectificationCause cause = FiscalRectificationCause.otherDeclaredCause,
}) => FiscalRectification(
  original: original,
  method: method,
  cause: cause,
  reason: 'Error material de transcripción declarado, ejemplo ficticio',
);

FiscalDocumentDraft draft({
  String id = 'new-record',
  String series = 'ENSAYO-F',
  String number = '000002',
  String date = day,
  String operationDate = day,
  String validationDate = day,
  FiscalDocumentShape shape = FiscalDocumentShape.complete,
  FiscalSimplificationBasis basis = FiscalSimplificationBasis.none,
  FiscalOperationNature nature = FiscalOperationNature.workshopService,
  FiscalRecipientUse use = FiscalRecipientUse.unknown,
  Iterable<FiscalSimplificationExclusion> exclusions = const [],
  bool businessGoods = false,
  String qualification = '',
  FiscalDocumentCharges? charges,
  FiscalDocumentParty? recipient,
  bool omitRecipient = false,
  FiscalRectification? rectification,
  FiscalRecordCorrection? correction,
  FiscalAdvanceDeclaration? advance,
  FiscalDeclaredRegime regime = FiscalDeclaredRegime.generalIva,
}) => FiscalDocumentDraft(
  recordId: id,
  series: series,
  description: 'Operación ficticia de ensayo',
  operationDate: operationDate,
  technicalValidationDate: validationDate,
  identity: VerifactuIdentity(
    issuerNif: 'B12345678',
    number: '$series/$number',
    issueDate: date,
  ),
  issuer: party(),
  shape: shape,
  charges: charges ?? money(date: operationDate),
  declaredRegime: regime,
  recipient: omitRecipient || shape == FiscalDocumentShape.simplified
      ? null
      : recipient ?? party(nif: '12345678Z'),
  rectification: rectification,
  recordCorrection: correction,
  advance: advance,
  simplificationBasis: basis,
  operationNature: nature,
  recipientUse: use,
  simplificationExclusions: exclusions,
  goodsMainlyForBusiness: businessGoods,
  qualificationReason: qualification,
);

FiscalEquivalenceSurcharge surcharge({
  String id = 'one',
  int rate = 520,
  FiscalEquivalenceBasis basis = FiscalEquivalenceBasis.declaredRetail,
}) => FiscalEquivalenceSurcharge(
  lineId: id,
  rateBps: rate,
  basis: basis,
  reason: 'Aplicación declarada y revisada, solo ensayo',
);

void main() {
  test('Complete trial keeps explicit parties, cents and all gates closed', () {
    final d = draft();
    expect(d.aeatType, 'F1');
    expect(d.charges.invoiceTotalCents, 12100);
    expect(d.charges.collectionCents, 12100);
    expect(d.toJson()['issuer']['nif'], 'B12345678');
    expect(
      jsonEncode(d.toJson()),
      contains('tallerflow-document-rules-sandbox-1'),
    );
    expect(d.emissionEnabled, false);
    expect(d.transmissionEnabled, false);
    expect(d.persistenceImplemented, false);
    expect(d.officialValidationImplemented, false);
    expect(() => draft(series: 'VENTAS'), error);
    expect(() => draft(omitRecipient: true), error);
    expect(() => draft(series: 'ENSAYO-\u00c1'), error);
    expect(() => draft(number: 'A=B'), error);
  });
  test(
    'Unicode identities and exported inspection copies keep source intact',
    () {
      final p = FiscalDocumentParty(
        name: 'Cliente de ensayo \u{1f697}',
        address: 'Calle ficticia\nPlanta 2',
        country: 'ES',
        nif: '12345678Z',
      );
      final d = draft(recipient: p);
      final copy = d.toJson();
      copy['recipient']['name'] = 'Nombre distinto';
      copy['charges']['lines'][0]['baseCents'] = 0;
      expect(d.recipient!.name, 'Cliente de ensayo \u{1f697}');
      expect(d.toJson()['charges']['lines'][0]['baseCents'], 10000);
      for (final control in [
        '\u0000',
        '\u000b',
        '\ufffe',
        String.fromCharCode(0xd800),
      ]) {
        expect(
          () => FiscalDocumentParty(
            name: 'Cliente$control',
            address: 'Calle',
            country: 'ES',
            nif: '12345678Z',
          ),
          error,
        );
      }
    },
  );
  test(
    'Party data requires a unique explicit ID, address and supported country',
    () {
      expect(
        () => FiscalDocumentParty(
          name: 'Cliente',
          address: '',
          country: 'ES',
          nif: '12345678Z',
        ),
        error,
      );
      expect(
        () => FiscalDocumentParty(
          name: 'Cliente',
          address: 'Calle',
          country: 'ZZ',
          nif: '12345678Z',
        ),
        error,
      );
      expect(
        () => FiscalDocumentParty(
          name: 'Cliente',
          address: 'Calle',
          country: 'ES',
        ),
        error,
      );
      expect(
        () => FiscalDocumentParty(
          name: 'Cliente',
          address: 'Calle',
          country: 'ES',
          nif: '12345678Z',
          other: FiscalOtherIdentity(
            country: 'ES',
            type: '07',
            identifier: 'CLIENTE-ENSAYO',
          ),
        ),
        error,
      );
    },
  );
  test('400 euros includes tax and does not become a workshop 3000 limit', () {
    final d = draft(
      shape: FiscalDocumentShape.simplified,
      basis: FiscalSimplificationBasis.upTo400,
      charges: money(base: 40000, rate: 0),
    );
    expect(d.aeatType, 'F2');
    expect(d.recipient, isNull);
    expect(
      () => draft(
        shape: FiscalDocumentShape.simplified,
        basis: FiscalSimplificationBasis.upTo400,
        charges: money(base: 40001, rate: 0),
      ),
      error,
    );
    expect(
      () => draft(
        shape: FiscalDocumentShape.simplified,
        basis: FiscalSimplificationBasis.consumerRetailUpTo3000,
        use: FiscalRecipientUse.consumer,
        charges: money(base: 100000, rate: 0),
      ),
      error,
    );
  });
  test(
    '3000 euros is only declared consumer retail goods, with no exclusion',
    () {
      final d = draft(
        shape: FiscalDocumentShape.simplified,
        basis: FiscalSimplificationBasis.consumerRetailUpTo3000,
        nature: FiscalOperationNature.consumerRetailGoods,
        use: FiscalRecipientUse.consumer,
        charges: money(base: 300000, rate: 0),
      );
      expect(d.aeatType, 'F2');
      expect(
        () => draft(
          shape: FiscalDocumentShape.simplified,
          basis: FiscalSimplificationBasis.consumerRetailUpTo3000,
          nature: FiscalOperationNature.consumerRetailGoods,
          use: FiscalRecipientUse.consumer,
          charges: money(base: 300001, rate: 0),
        ),
        error,
      );
      for (final use in [
        FiscalRecipientUse.business,
        FiscalRecipientUse.unknown,
      ]) {
        expect(
          () => draft(
            shape: FiscalDocumentShape.simplified,
            basis: FiscalSimplificationBasis.consumerRetailUpTo3000,
            nature: FiscalOperationNature.consumerRetailGoods,
            use: use,
            charges: money(base: 50000, rate: 0),
          ),
          error,
        );
      }
      expect(
        () => draft(
          shape: FiscalDocumentShape.simplified,
          basis: FiscalSimplificationBasis.consumerRetailUpTo3000,
          nature: FiscalOperationNature.consumerRetailGoods,
          use: FiscalRecipientUse.consumer,
          businessGoods: true,
          charges: money(base: 50000, rate: 0),
        ),
        error,
      );
      for (final exclusion in FiscalSimplificationExclusion.values) {
        expect(
          () => draft(
            shape: FiscalDocumentShape.simplified,
            basis: FiscalSimplificationBasis.upTo400,
            exclusions: [exclusion],
          ),
          error,
        );
      }
    },
  );
  test('Qualified simplified is F1 with recipient and a declared request', () {
    final d = draft(
      shape: FiscalDocumentShape.qualifiedSimplified,
      basis: FiscalSimplificationBasis.upTo400,
      qualification: 'Solicitud de deducción ficticia',
    );
    expect(d.aeatType, 'F1');
    expect(d.recipient!.nif, '12345678Z');
    expect(
      () => draft(
        shape: FiscalDocumentShape.qualifiedSimplified,
        basis: FiscalSimplificationBasis.upTo400,
      ),
      error,
    );
    expect(
      () => draft(
        shape: FiscalDocumentShape.qualifiedSimplified,
        basis: FiscalSimplificationBasis.upTo400,
        qualification: 'Solicitud',
        omitRecipient: true,
      ),
      error,
    );
    expect(() => draft(qualification: 'Solicitud incoherente'), error);
    expect(
      () => FiscalDocumentDraft(
        recordId: 'one',
        series: 'ENSAYO-F',
        description: 'Ensayo',
        operationDate: day,
        technicalValidationDate: day,
        identity: VerifactuIdentity(
          issuerNif: 'B12345678',
          number: 'ENSAYO-F/1',
          issueDate: day,
        ),
        issuer: party(),
        recipient: party(),
        shape: FiscalDocumentShape.simplified,
        charges: money(),
        declaredRegime: FiscalDeclaredRegime.generalIva,
        simplificationBasis: FiscalSimplificationBasis.upTo400,
      ),
      error,
    );
  });
  test('Country enumeration matches all 246 pinned XSD values', () {
    final xml = File(
      'tool/fixtures/aeat/SuministroInformacion.xsd',
    ).readAsStringSync();
    final fragment = xml
        .split('<simpleType name="CountryType2">')
        .last
        .split('</simpleType>')
        .first;
    final actual = RegExp(
      r'<enumeration value="([A-Z]{2})"',
    ).allMatches(fragment).map((m) => m.group(1)!).toSet();
    expect(actual.length, 246);
    expect(aeatDocumentCountryCodes, actual);
    expect(
      aeatDocumentCountryCodes,
      containsAll(['US', 'GR', 'JP', 'XG', 'QU', 'XB', 'XN']),
    );
  });
  test(
    'EU IDOtro validates only official broad structure, not census status',
    () {
      for (final entry in {
        'DE': 'DE123456789',
        'FR': 'FRAA123456789',
        'GR': 'EL123456789',
        'IE': 'IE1234567A',
        'RO': 'RO12',
        'NL': 'NL123456789B12',
        'AT': 'ATU12345678',
        'CY': 'CY12345678A',
      }.entries) {
        final other = FiscalOtherIdentity(
          country: entry.key,
          type: '02',
          identifier: entry.value,
        );
        final p = FiscalDocumentParty(
          name: 'Cliente ficticio',
          address: 'Dirección ficticia',
          country: entry.key,
          other: other,
        );
        expect(draft(recipient: p).recipient!.other!.identifier, entry.value);
      }
      for (final entry in {
        'DE': 'DE12345678',
        'GR': 'GR123456789',
        'RO': 'RO01',
        'US': 'US123456789',
        'GB': 'GB123456789',
        'FR': 'frAA123456789',
      }.entries) {
        expect(
          () => FiscalOtherIdentity(
            country: entry.key,
            type: '02',
            identifier: entry.value,
          ),
          error,
        );
      }
    },
  );
  test('Foreign passports and Spanish non-census IDs are explicit', () {
    final passport = FiscalOtherIdentity(
      country: 'US',
      type: '03',
      identifier: 'PASS-FICTICIO',
    );
    expect(
      draft(
        recipient: FiscalDocumentParty(
          name: 'Cliente ficticio',
          address: 'Dirección',
          country: 'US',
          other: passport,
        ),
      ).aeatType,
      'F1',
    );
    expect(
      FiscalOtherIdentity(
        country: 'ES',
        type: '07',
        identifier: 'NO-CENSADO-ENSAYO',
      ).type,
      '07',
    );
    expect(
      () => FiscalOtherIdentity(country: 'US', type: '07', identifier: 'ID'),
      error,
    );
    expect(
      () => FiscalOtherIdentity(country: 'ES', type: '04', identifier: 'ID'),
      error,
    );
    expect(
      () => FiscalOtherIdentity(country: 'ZZ', type: '03', identifier: 'ID'),
      error,
    );
    expect(
      () => FiscalOtherIdentity(country: 'US', type: '08', identifier: 'ID'),
      error,
    );
    expect(
      () => FiscalOtherIdentity(country: 'US', type: '03', identifier: ' ID '),
      error,
    );
    expect(
      () =>
          FiscalOtherIdentity(country: 'US', type: '03', identifier: 'A' * 21),
      error,
    );
    expect(
      () => FiscalDocumentParty(
        name: 'Cliente',
        address: 'Calle',
        country: 'CA',
        other: passport,
      ),
      error,
    );
  });
  test(
    'Difference rectification conserves source and signs with a new series',
    () {
      final original = source();
      final saved = jsonEncode(original.toJson());
      final d = draft(
        series: 'ENSAYO-R',
        rectification: rectification(original),
        charges: money(
          base: -1000,
          adjustment: 'Error material de transcripción ficticio',
        ),
      );
      expect(d.aeatType, 'R4');
      expect(d.rectification!.methodCode, 'I');
      expect(d.charges.invoiceTotalCents, -1210);
      expect(d.settlementAdjustmentCents, -1210);
      expect(d.rectifiedAmounts, isNull);
      expect(jsonEncode(original.toJson()), saved);
      expect(() => draft(rectification: rectification(original)), error);
      expect(
        () => draft(
          series: 'ENSAYO-R',
          id: original.recordId,
          rectification: rectification(original),
        ),
        error,
      );
      expect(
        () => draft(charges: money(base: -1000, adjustment: 'Motivo')),
        error,
      );
    },
  );
  test(
    'Substitution reports the new whole amount and frozen original amounts',
    () {
      final original = source(surcharge: 520, withholding: 1500);
      final d = draft(
        series: 'ENSAYO-R',
        rectification: rectification(
          original,
          method: FiscalRectificationMethod.substitution,
        ),
        charges: money(base: 8000),
      );
      expect(d.rectification!.methodCode, 'S');
      expect(d.charges.invoiceTotalCents, 9680);
      expect(d.rectifiedAmounts, {
        'baseCents': 10000,
        'taxCents': 2100,
        'surchargeCents': 520,
      });
      expect(
        d.settlementAdjustmentCents,
        -2940,
      ); // 9680 - (10000 + 2100 + 520), not cash.
      expect(
        () => d.rectifiedAmounts!['baseCents'] = 0,
        throwsUnsupportedError,
      );
      expect(
        () => draft(
          series: 'ENSAYO-R',
          rectification: rectification(
            original,
            method: FiscalRectificationMethod.substitution,
          ),
          charges: money(base: -100, adjustment: 'Motivo'),
        ),
        error,
      );
    },
  );
  test('Simplified rectification is R5 and may exceed ordinary 400 limit', () {
    final original = source(type: 'F2', base: 50000, tax: 10500);
    final d = draft(
      series: 'ENSAYO-R',
      shape: FiscalDocumentShape.simplified,
      basis: FiscalSimplificationBasis.rectification,
      rectification: rectification(original),
      charges: money(base: -50000, adjustment: 'Error material ficticio'),
    );
    expect(d.aeatType, 'R5');
    expect(d.recipient, isNull);
    expect(
      () => draft(series: 'ENSAYO-R', rectification: rectification(original)),
      error,
    );
    expect(
      () => draft(
        series: 'ENSAYO-R',
        shape: FiscalDocumentShape.simplified,
        basis: FiscalSimplificationBasis.upTo400,
        rectification: rectification(original),
      ),
      error,
    );
    expect(
      () => draft(
        series: 'ENSAYO-R',
        shape: FiscalDocumentShape.qualifiedSimplified,
        basis: FiscalSimplificationBasis.rectification,
        qualification: 'Solicitud',
        rectification: rectification(source()),
      ),
      error,
    );
  });
  test(
    'Unimplemented statutory causes and incomplete references fail closed',
    () {
      for (final cause in FiscalRectificationCause.values.where(
        (c) => c != FiscalRectificationCause.otherDeclaredCause,
      )) {
        expect(() => rectification(source(), cause: cause), error);
      }
      expect(() => source(type: 'R1'), error);
      expect(() => source(type: 'F2', base: 300001, tax: 0), error);
      expect(() => source(base: -100), error);
      expect(() => source(base: 100, withholding: 101), error);
      expect(
        () => FiscalOriginalReference(
          recordId: 'original',
          series: 'ENSAYO-F',
          sourceHash: 'invalid',
          type: 'F1',
          identity: VerifactuIdentity(
            issuerNif: 'B12345678',
            number: 'ENSAYO-F/1',
            issueDate: day,
          ),
          operationDate: day,
          baseCents: 10000,
          taxCents: 2100,
        ),
        error,
      );
      expect(
        () => draft(
          series: 'ENSAYO-R',
          operationDate: '06-10-2026',
          rectification: rectification(source()),
        ),
        error,
      );
    },
  );
  test(
    'Record correction requires source, same identity and economic values',
    () {
      expect(
        () => FiscalRecordCorrection(
          original: null,
          previousReception: FiscalPreviousReception.initialHighRejected,
          previousRegistryState: FiscalDeclaredRegistryState.doesNotExist,
          previousReceiptReference: 'receipt-previous',
          reason: 'Motivo',
        ),
        error,
      );
      for (final reception in FiscalPreviousReception.values) {
        final d = draft(
          number: '000001',
          correction: FiscalRecordCorrection(
            original: source(savedCharges: money()),
            previousReception: reception,
            previousRegistryState:
                reception == FiscalPreviousReception.initialHighRejected
                ? FiscalDeclaredRegistryState.doesNotExist
                : FiscalDeclaredRegistryState.exists,
            previousReceiptReference: 'receipt-previous',
            reason: 'Error de descripción del registro, ensayo',
          ),
        );
        expect(d.aeatType, 'F1');
        expect(d.toJson()['recordCorrection']['subsanacion'], 'S');
        expect(
          d.toJson()['recordCorrection']['rechazoPrevio'],
          switch (reception) {
            FiscalPreviousReception.acceptedWithErrors => 'N',
            FiscalPreviousReception.initialHighRejected => 'X',
            FiscalPreviousReception.correctionRejected => 'S',
          },
        );
      }
      final c = FiscalRecordCorrection(
        original: source(savedCharges: money()),
        previousReception: FiscalPreviousReception.initialHighRejected,
        previousRegistryState: FiscalDeclaredRegistryState.doesNotExist,
        previousReceiptReference: 'receipt-previous',
        reason: 'Motivo',
      );
      expect(() => draft(correction: c), error);
      expect(
        () =>
            draft(number: '000001', correction: c, charges: money(base: 9000)),
        error,
      );
      expect(
        () => draft(number: '000001', correction: c, id: 'original-record'),
        error,
      );
      expect(
        () => draft(
          number: '000001',
          correction: c,
          rectification: rectification(source()),
        ),
        error,
      );
    },
  );
  test(
    'Correction status cannot conflate rejected initial high with rejected correction',
    () {
      FiscalRecordCorrection c(
        FiscalPreviousReception reception,
        FiscalDeclaredRegistryState state, {
        FiscalOriginalReference? original,
        String receipt = 'receipt',
      }) => FiscalRecordCorrection(
        original: original ?? source(savedCharges: money()),
        previousReception: reception,
        previousRegistryState: state,
        previousReceiptReference: receipt,
        reason: 'Descripción errónea del registro, ensayo',
      );
      expect(
        c(
          FiscalPreviousReception.initialHighRejected,
          FiscalDeclaredRegistryState.doesNotExist,
        ).rejectionCode,
        'X',
      );
      expect(
        c(
          FiscalPreviousReception.correctionRejected,
          FiscalDeclaredRegistryState.exists,
        ).rejectionCode,
        'S',
      );
      expect(
        () => c(
          FiscalPreviousReception.initialHighRejected,
          FiscalDeclaredRegistryState.exists,
        ),
        error,
      );
      expect(
        () => c(
          FiscalPreviousReception.correctionRejected,
          FiscalDeclaredRegistryState.doesNotExist,
        ),
        error,
      );
      expect(
        () => c(
          FiscalPreviousReception.acceptedWithErrors,
          FiscalDeclaredRegistryState.doesNotExist,
        ),
        error,
      );
      expect(
        () => c(
          FiscalPreviousReception.acceptedWithErrors,
          FiscalDeclaredRegistryState.exists,
          original: source(),
        ),
        error,
      );
      expect(
        () => c(
          FiscalPreviousReception.acceptedWithErrors,
          FiscalDeclaredRegistryState.exists,
          receipt: '',
        ),
        error,
      );
    },
  );
  test(
    'Correction rejects a changed tax structure even when totals exactly match',
    () {
      final original = source(
        base: 10000,
        tax: 1000,
        savedCharges: money(rate: 1000),
      );
      final c = FiscalRecordCorrection(
        original: original,
        previousReception: FiscalPreviousReception.acceptedWithErrors,
        previousRegistryState: FiscalDeclaredRegistryState.exists,
        previousReceiptReference: 'receipt-accepted-errors',
        reason: 'Error de descripción ficticio',
      );
      final changed = money(
        lines: [
          item(id: 'one', base: 4762, rate: 2100),
          item(id: 'two', base: 5238, rate: 0),
        ],
      );
      expect(changed.calculation.baseCents, original.baseCents);
      expect(changed.calculation.taxCents, original.taxCents);
      expect(
        () => draft(number: '000001', correction: c, charges: changed),
        error,
      );
      expect(
        draft(
          number: '000001',
          correction: c,
          charges: money(rate: 1000),
        ).aeatType,
        'F1',
      );
    },
  );
  test(
    'Technical review date rejects future issue and operation dates together',
    () {
      expect(
        () => draft(date: '31-12-9999', operationDate: '31-12-9999'),
        error,
      );
      expect(() => draft(date: '08-10-2026', operationDate: day), error);
      expect(
        () => draft(
          operationDate: '06-10-2006',
          charges: money(date: '06-10-2006'),
        ),
        error,
      );
      expect(
        draft(
          operationDate: '07-10-2006',
          charges: money(date: '07-10-2006'),
        ).aeatType,
        'F1',
      );
      expect(
        () => draft(date: '27-10-2024', operationDate: '27-10-2024'),
        error,
      );
      expect(draft().toJson()['technicalValidationDate'], day);
      expect(() => draft(validationDate: '31-02-2026'), error);
    },
  );
  test(
    'Advances explicitly preserve received date, receipt and gross amount',
    () {
      final a = FiscalAdvanceDeclaration(
        receiptId: 'receipt-1',
        receivedDate: day,
        futureOperationReference: 'repair-future',
        reason: 'Anticipo recibido ficticio',
        receivedCents: 12100,
      );
      final d = draft(advance: a);
      expect(d.toJson()['advance']['receivedCents'], 12100);
      expect(
        d.toJson()['advance']['futureOperationReference'],
        'repair-future',
      );
      expect(() => draft(advance: a, charges: money(base: 9000)), error);
      expect(() => draft(advance: a, operationDate: '06-10-2026'), error);
      expect(
        () => draft(
          advance: a,
          exclusions: [FiscalSimplificationExclusion.intraCommunityExemptGoods],
        ),
        error,
      );
      expect(
        () => FiscalAdvanceDeclaration(
          receiptId: 'r',
          receivedDate: day,
          futureOperationReference: 'future',
          reason: 'Motivo',
          receivedCents: 0,
        ),
        error,
      );
    },
  );
  test(
    'Declared equivalence surcharge changes gross while no regime is inferred',
    () {
      final c = money(surcharges: [surcharge()]);
      expect(c.surchargeCents, 520);
      expect(c.invoiceTotalCents, 12620);
      expect(c.collectionCents, 12620);
      final d = draft(
        charges: c,
        regime: FiscalDeclaredRegime.equivalenceSurcharge,
      );
      expect(d.toJson()['declaredRegime'], 'equivalenceSurcharge');
      expect(() => draft(charges: c), error);
      expect(
        () => draft(regime: FiscalDeclaredRegime.equivalenceSurcharge),
        error,
      );
      expect(() => money(surcharges: [surcharge(rate: 175)]), error);
      expect(
        money(
          surcharges: [
            surcharge(
              rate: 175,
              basis: FiscalEquivalenceBasis.declaredTobaccoRetail,
            ),
          ],
        ).surchargeCents,
        175,
      );
      expect(
        () => money(
          rate: 1000,
          surcharges: [
            surcharge(
              rate: 140,
              basis: FiscalEquivalenceBasis.declaredTobaccoRetail,
            ),
          ],
        ),
        error,
      );
    },
  );
  test(
    'Reviewed surcharge pairs are dated, unique and attached to taxable IVA',
    () {
      for (final entry in {2100: 520, 1000: 140, 400: 50}.entries) {
        expect(
          money(
            rate: entry.key,
            surcharges: [surcharge(rate: entry.value)],
          ).surchargeCents,
          entry.value,
        );
      }
      final historical = money(
        date: '28-10-2024',
        rate: 200,
        surcharges: [surcharge(rate: 26)],
      );
      expect(historical.surchargeCents, 26);
      expect(
        () => draft(
          charges: historical,
          regime: FiscalDeclaredRegime.equivalenceSurcharge,
        ),
        error,
      );
      expect(
        draft(
          date: '28-10-2024',
          operationDate: '28-10-2024',
          validationDate: '28-10-2024',
          charges: historical,
          regime: FiscalDeclaredRegime.equivalenceSurcharge,
        ).charges.invoiceTotalCents,
        10226,
      );
      expect(
        money(
          date: '30-09-2024',
          rate: 500,
          surcharges: [surcharge(rate: 62)],
        ).surchargeCents,
        62,
      );
      expect(
        () => money(date: day, rate: 200, surcharges: [surcharge(rate: 26)]),
        error,
      );
      expect(() => money(surcharges: [surcharge(rate: 140)]), error);
      expect(() => money(surcharges: [surcharge(), surcharge()]), error);
      expect(() => money(surcharges: [surcharge(id: 'missing')]), error);
      expect(
        () => money(
          lines: [item(tax: FiscalTax.igic)],
          surcharges: [surcharge()],
        ),
        error,
      );
      expect(
        () => money(
          lines: [item(rate: 0, treatment: FiscalTreatment.exempt)],
          surcharges: [surcharge(rate: 0)],
        ),
        error,
      );
    },
  );
  test('BigInt surcharge and withholding round half cents symmetrically', () {
    expect(
      money(
        base: 100,
        rate: 400,
        surcharges: [surcharge(rate: 50)],
      ).surchargeCents,
      1,
    );
    expect(
      money(
        base: -100,
        rate: 400,
        adjustment: 'Motivo',
        surcharges: [surcharge(rate: 50)],
      ).surchargeCents,
      -1,
    );
    FiscalWithholding half() => FiscalWithholding(
      lineIds: ['one'],
      rateBps: 5000,
      reason: 'Tipo explícito de cálculo',
    );
    expect(money(base: 1, rate: 0, withholdings: [half()]).withholdingCents, 1);
    expect(
      money(
        base: -1,
        rate: 0,
        adjustment: 'Motivo',
        withholdings: [half()],
      ).withholdingCents,
      -1,
    );
    final huge = money(
      base: 800000000001,
      withholdings: [
        FiscalWithholding(
          lineIds: ['one'],
          rateBps: 1500,
          reason: 'Tipo declarado; no asignado automáticamente',
        ),
      ],
    );
    expect(huge.withholdingCents, 120000000000);
    expect(huge.invoiceTotalCents, 968000000001);
    expect(huge.collectionCents, 848000000001);
  });
  test(
    'Withholding uses selected bases and changes collection, not gross or IVA',
    () {
      final c = money(
        base: 20000,
        withholdings: [
          FiscalWithholding(
            lineIds: ['one'],
            rateBps: 1500,
            reason: 'Ejemplo AEAT de retención declarada',
          ),
        ],
      );
      expect(c.calculation.taxCents, 4200);
      expect(c.withholdingCents, 3000);
      expect(c.invoiceTotalCents, 24200);
      expect(c.collectionCents, 21200);
      final mixed = money(
        lines: [
          item(id: 'labor', base: 10000),
          item(id: 'goods', base: 5000),
        ],
        withholdings: [
          FiscalWithholding(
            lineIds: ['labor'],
            rateBps: 1500,
            reason: 'Base declarada',
          ),
        ],
      );
      expect(mixed.withholdingCents, 1500);
      expect(mixed.collectionCents, 16650);
      expect(
        () => c.withholdings.single['lineIds'].add('more'),
        throwsUnsupportedError,
      );
      expect(
        () => c.withholdings.single['baseCents'] = 0,
        throwsUnsupportedError,
      );
      expect(
        () => money(
          withholdings: [
            FiscalWithholding(
              lineIds: ['missing'],
              rateBps: 1500,
              reason: 'Motivo',
            ),
          ],
        ),
        error,
      );
      expect(
        () => FiscalWithholding(
          lineIds: ['one', 'one'],
          rateBps: 1500,
          reason: 'Motivo',
        ),
        error,
      );
      expect(
        () => money(
          withholdings: [
            FiscalWithholding(
              lineIds: ['one'],
              rateBps: 1500,
              reason: 'Motivo',
            ),
            FiscalWithholding(lineIds: ['one'], rateBps: 700, reason: 'Motivo'),
          ],
        ),
        error,
      );
    },
  );
  test(
    'Dates cannot mix snapshots or silently enable future special regimes',
    () {
      expect(() => draft(operationDate: '08-10-2026'), error);
      expect(() => draft(charges: money(date: '06-10-2026')), error);
      expect(() => source(issueDate: '06-10-2026'), error);
      expect(
        () => draft(
          series: 'ENSAYO-R',
          date: '06-10-2026',
          operationDate: '06-10-2026',
          rectification: rectification(
            source(issueDate: '08-10-2026', operationDate: '06-10-2026'),
          ),
        ),
        error,
      );
      expect(() => draft(charges: money(rate: 700)), error);
      expect(
        () => draft(
          charges: money(lines: [item(tax: FiscalTax.igic, rate: 700)]),
        ),
        error,
      );
      expect(
        () => draft(
          charges: money(
            lines: [item(rate: 0, treatment: FiscalTreatment.exempt)],
          ),
        ),
        error,
      );
      final ordinary = money(date: '31-12-2024', rate: 750);
      expect(
        draft(
          date: '31-12-2024',
          operationDate: '31-12-2024',
          charges: ordinary,
        ).charges.calculation.taxCents,
        750,
      );
      expect(() => draft(charges: money(rate: 750)), error);
    },
  );
}
