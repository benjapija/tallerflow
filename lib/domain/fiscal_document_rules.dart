import 'dart:convert';

import 'engine.dart';
import 'fiscal_calculation.dart';
import 'verifactu_hash.dart';

/// Pure planning rules for future sandbox formats. No ledger mutation, official
/// numbering, XML, transmission or invoice issuance exists in this model.
enum FiscalDocumentShape { complete, simplified, qualifiedSimplified }

enum FiscalSimplificationBasis {
  none,
  upTo400,
  consumerRetailUpTo3000,
  rectification,
}

enum FiscalOperationNature { workshopService, consumerRetailGoods, other }

enum FiscalRecipientUse { consumer, business, unknown }

enum FiscalSimplificationExclusion {
  intraCommunityExemptGoods,
  distanceSaleOutsideAllowedRegime,
  nonEstablishedReverseChargeSelfBilling,
  articleTwoThreeBPrime,
}

enum FiscalRectificationMethod { differences, substitution }

enum FiscalRectificationCause {
  otherDeclaredCause,
  errorInLawOrArticle80_1_2_6,
  insolvency,
  uncollectedDebt,
}

enum FiscalPreviousReception {
  acceptedWithErrors,
  initialHighRejected,
  correctionRejected,
}

enum FiscalDeclaredRegistryState { exists, doesNotExist }

enum FiscalEquivalenceBasis { declaredRetail, declaredTobaccoRetail }

enum FiscalDeclaredRegime { generalIva, equivalenceSurcharge }

class FiscalOtherIdentity {
  final String country, type, identifier;
  FiscalOtherIdentity({
    required this.country,
    required this.type,
    required this.identifier,
  }) {
    if (!aeatDocumentCountryCodes.contains(country) ||
        !{'02', '03', '04', '05', '06', '07'}.contains(type)) {
      throw const RuleException('Identificación alternativa no soportada');
    }
    _text(identifier, 'Identificación alternativa', 20);
    if (identifier != identifier.trim() ||
        (country == 'ES' && !{'03', '07'}.contains(type)) ||
        (type == '07' && country != 'ES')) {
      throw const RuleException('País y tipo de identificación incompatibles');
    }
    if (type == '02') {
      final prefix = country == 'GR' ? 'EL' : country;
      final pattern = _vatPatterns[country];
      if (pattern == null ||
          !RegExp('^$prefix$pattern\$').hasMatch(identifier)) {
        throw const RuleException(
          'Estructura NIF-IVA no soportada para el país',
        );
      }
    }
  }
  Map<String, dynamic> toJson() => {
    'country': country,
    'type': type,
    'identifier': identifier,
  };
}

class FiscalDocumentParty {
  final String name, address, country;
  final String? nif;
  final FiscalOtherIdentity? other;
  FiscalDocumentParty({
    required this.name,
    required this.address,
    required this.country,
    this.nif,
    this.other,
  }) {
    _text(name, 'Nombre fiscal', 120);
    _text(address, 'Domicilio fiscal', 500);
    if (!aeatDocumentCountryCodes.contains(country) ||
        (nif == null) == (other == null)) {
      throw const RuleException('Indica una única identificación y país');
    }
    if (nif != null && !RegExp(r'^[A-Z0-9]{9}$').hasMatch(nif!)) {
      throw const RuleException('Estructura NIF inválida');
    }
    if (other != null && other!.country != country) {
      throw const RuleException('El país no coincide con la identificación');
    }
  }
  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'country': country,
    if (nif != null) 'nif': nif,
    if (other != null) 'other': other!.toJson(),
  };
}

class FiscalEquivalenceSurcharge {
  final String lineId, reason;
  final int rateBps;
  final FiscalEquivalenceBasis basis;
  FiscalEquivalenceSurcharge({
    required this.lineId,
    required this.rateBps,
    required this.reason,
    required this.basis,
  }) {
    _text(lineId, 'Partida del recargo', 100);
    _text(reason, 'Motivo revisado del recargo', 2000);
    if (rateBps < 0 || rateBps > 10000) {
      throw const RuleException('Tipo de recargo inválido');
    }
  }
}

class FiscalWithholding {
  final List<String> lineIds;
  final int rateBps;
  final String reason;
  FiscalWithholding({
    required Iterable<String> lineIds,
    required this.rateBps,
    required this.reason,
  }) : lineIds = List.unmodifiable(lineIds) {
    _text(reason, 'Referencia revisada de retención', 2000);
    if (this.lineIds.isEmpty ||
        this.lineIds.length > 1000 ||
        this.lineIds.toSet().length != this.lineIds.length ||
        rateBps <= 0 ||
        rateBps > 10000) {
      throw const RuleException('Base o tipo de retención inválidos');
    }
  }
}

class FiscalDocumentCharges {
  final FiscalCalculation calculation;
  final String operationDate;
  final int surchargeCents,
      withholdingCents,
      invoiceTotalCents,
      collectionCents;
  final List<Map<String, dynamic>> surcharges, withholdings;
  const FiscalDocumentCharges._(
    this.calculation,
    this.operationDate,
    this.surchargeCents,
    this.withholdingCents,
    this.invoiceTotalCents,
    this.collectionCents,
    this.surcharges,
    this.withholdings,
  );
  bool get emissionEnabled => false;

  /// Exact conserved economic structure, deliberately stricter than equal sums.
  /// This is a comparison key, not a hash or proof of an official response.
  String get economicComparisonKey => jsonEncode({
    'operationDate': operationDate,
    'lines': [
      for (final line in calculation.lines)
        {
          'id': line.source.id,
          'quantityMilli': line.source.quantityMilli,
          'unitPriceCents': line.source.unitPriceCents,
          'discountBps': line.source.discountBps,
          'tax': line.source.tax.name,
          'treatment': line.source.treatment.name,
          'rateBps': line.source.rateBps,
          'legalReason': line.source.legalReason,
          'grossCents': line.grossCents,
          'discountCents': line.discountCents,
          'baseCents': line.baseCents,
          'taxCents': line.taxCents,
        },
    ],
    'surcharges': [
      for (final row in surcharges)
        {
          'lineId': row['lineId'],
          'baseCents': row['baseCents'],
          'rateBps': row['rateBps'],
          'amountCents': row['amountCents'],
          'basis': row['basis'],
        },
    ],
    'withholdings': [
      for (final row in withholdings)
        {
          'lineIds': row['lineIds'],
          'baseCents': row['baseCents'],
          'rateBps': row['rateBps'],
          'amountCents': row['amountCents'],
        },
    ],
  });
  factory FiscalDocumentCharges.calculate(
    FiscalCalculation calculation, {
    required String operationDate,
    Iterable<FiscalEquivalenceSurcharge> surcharges = const [],
    Iterable<FiscalWithholding> withholdings = const [],
  }) {
    final date = _date(operationDate);
    final byId = {for (final line in calculation.lines) line.source.id: line};
    final surchargeRows = <Map<String, dynamic>>[],
        withholdingRows = <Map<String, dynamic>>[];
    final charged = <String>{}, withheld = <String>{};
    var surchargeSum = 0, withholdingSum = 0;
    for (final spec in surcharges) {
      final line = byId[spec.lineId];
      if (line == null ||
          !charged.add(spec.lineId) ||
          line.source.tax != FiscalTax.iva ||
          line.source.treatment != FiscalTreatment.taxable ||
          !_surchargeAllowed(line.source.rateBps, spec.rateBps, date) ||
          (spec.basis == FiscalEquivalenceBasis.declaredTobaccoRetail
              ? line.source.rateBps != 2100 || spec.rateBps != 175
              : spec.rateBps == 175)) {
        throw const RuleException(
          'Recargo incompatible, repetido o sin partida',
        );
      }
      final amount = _round(line.baseCents, spec.rateBps);
      surchargeSum = _amount(surchargeSum + amount);
      surchargeRows.add(
        Map.unmodifiable({
          'lineId': spec.lineId,
          'baseCents': line.baseCents,
          'rateBps': spec.rateBps,
          'amountCents': amount,
          'reason': spec.reason,
          'basis': spec.basis.name,
        }),
      );
    }
    for (final spec in withholdings) {
      var base = 0;
      for (final id in spec.lineIds) {
        final line = byId[id];
        if (line == null || !withheld.add(id)) {
          throw const RuleException(
            'Base de retención inexistente o aplicada dos veces',
          );
        }
        base = _amount(base + line.baseCents);
      }
      final amount = _round(base, spec.rateBps);
      withholdingSum = _amount(withholdingSum + amount);
      withholdingRows.add(
        Map.unmodifiable({
          'lineIds': List.unmodifiable(spec.lineIds),
          'baseCents': base,
          'rateBps': spec.rateBps,
          'amountCents': amount,
          'reason': spec.reason,
        }),
      );
    }
    final total = _amount(calculation.totalCents + surchargeSum);
    return FiscalDocumentCharges._(
      calculation,
      operationDate,
      surchargeSum,
      withholdingSum,
      total,
      _amount(total - withholdingSum),
      List.unmodifiable(surchargeRows),
      List.unmodifiable(withholdingRows),
    );
  }
  Map<String, dynamic> toJson() => {
    'operationDate': operationDate,
    'lines': [
      for (final line in calculation.lines)
        {
          'id': line.source.id,
          'description': line.source.description,
          'quantityMilli': line.source.quantityMilli,
          'unitPriceCents': line.source.unitPriceCents,
          'discountBps': line.source.discountBps,
          'tax': line.source.tax.name,
          'treatment': line.source.treatment.name,
          'rateBps': line.source.rateBps,
          'legalReason': line.source.legalReason,
          'grossCents': line.grossCents,
          'discountCents': line.discountCents,
          'baseCents': line.baseCents,
          'taxCents': line.taxCents,
        },
    ],
    'baseCents': calculation.baseCents,
    'taxCents': calculation.taxCents,
    'surchargeCents': surchargeCents,
    'withholdingCents': withholdingCents,
    'invoiceTotalCents': invoiceTotalCents,
    'collectionCents': collectionCents,
    'surcharges': surcharges,
    'withholdings': withholdings,
  };
}

/// A conserved reference supplied by a future authorized document repository.
/// A matching digest alone does not prove identity or an accepted AEAT receipt.
class FiscalOriginalReference {
  final String recordId, series, sourceHash, type, operationDate;
  final VerifactuIdentity identity;
  final FiscalDocumentCharges? savedCharges;
  final int baseCents, taxCents, surchargeCents, withholdingCents;
  FiscalOriginalReference({
    required this.recordId,
    required this.series,
    required this.sourceHash,
    required this.type,
    required this.identity,
    required this.baseCents,
    required this.taxCents,
    required this.operationDate,
    this.savedCharges,
    this.surchargeCents = 0,
    this.withholdingCents = 0,
  }) {
    _text(recordId, 'Registro original', 100);
    _series(series);
    _aeatNumber(identity.number);
    if (!{'F1', 'F2'}.contains(type) ||
        !RegExp(r'^[A-F0-9]{64}$').hasMatch(sourceHash) ||
        !identity.number.startsWith('$series/')) {
      throw const RuleException(
        'Referencia original fuera del circuito soportado',
      );
    }
    if (_date(operationDate).isAfter(_date(identity.issueDate))) {
      throw const RuleException('Fecha original de operación no soportada');
    }
    for (final amount in [
      baseCents,
      taxCents,
      surchargeCents,
      withholdingCents,
    ]) {
      _amount(amount);
      if (amount < 0) {
        throw const RuleException(
          'Esta referencia requiere un original ordinario no negativo',
        );
      }
    }
    if (withholdingCents > baseCents) {
      throw const RuleException(
        'Retención original fuera del circuito de base declarada',
      );
    }
    _amount(baseCents + taxCents + surchargeCents);
    if (type == 'F2' && invoiceTotalCents > 300000) {
      throw const RuleException(
        'Original F2 necesita una autorización especial aún no modelada',
      );
    }
    if (savedCharges != null &&
        (savedCharges!.operationDate != operationDate ||
            savedCharges!.calculation.baseCents != baseCents ||
            savedCharges!.calculation.taxCents != taxCents ||
            savedCharges!.surchargeCents != surchargeCents ||
            savedCharges!.withholdingCents != withholdingCents)) {
      throw const RuleException(
        'Desglose original incompatible con sus importes conservados',
      );
    }
  }
  int get invoiceTotalCents => baseCents + taxCents + surchargeCents;
  Map<String, dynamic> toJson() => {
    'recordId': recordId,
    'series': series,
    'sourceHash': sourceHash,
    'type': type,
    'issuerNif': identity.issuerNif,
    'number': identity.number,
    'issueDate': identity.issueDate,
    'operationDate': operationDate,
    'baseCents': baseCents,
    'taxCents': taxCents,
    'surchargeCents': surchargeCents,
    'withholdingCents': withholdingCents,
    if (savedCharges != null) 'savedCharges': savedCharges!.toJson(),
  };
}

class FiscalRectification {
  final FiscalOriginalReference original;
  final FiscalRectificationMethod method;
  final FiscalRectificationCause cause;
  final String reason;
  FiscalRectification({
    required this.original,
    required this.method,
    required this.reason,
    required this.cause,
  }) {
    _text(reason, 'Motivo de rectificación', 2000);
    if (cause != FiscalRectificationCause.otherDeclaredCause) {
      throw const RuleException(
        'Esta causa exige un circuito R1/R2/R3 aún no implementado',
      );
    }
  }
  String get methodCode =>
      method == FiscalRectificationMethod.differences ? 'I' : 'S';

  /// Deliberately only R4/R5. Insolvency, bad debt and Art.80.1/2 circuits need
  /// additional evidence and rules, so no arbitrary R1/R2/R3 code is accepted.
  String get type => original.type == 'F2' ? 'R5' : 'R4';
}

class FiscalRecordCorrection {
  final FiscalOriginalReference original;
  final FiscalPreviousReception previousReception;
  final FiscalDeclaredRegistryState previousRegistryState;
  final String reason, previousReceiptReference;
  FiscalRecordCorrection({
    required FiscalOriginalReference? original,
    required this.previousReception,
    required this.reason,
    required this.previousRegistryState,
    required this.previousReceiptReference,
  }) : original =
           original ??
           (throw const RuleException(
             'La subsanación requiere el registro original',
           )) {
    _text(reason, 'Motivo de subsanación', 2000);
    _text(previousReceiptReference, 'Referencia de recepción conservada', 100);
    if (this.original.savedCharges == null) {
      throw const RuleException(
        'La subsanación requiere el desglose económico original',
      );
    }
    if ((previousReception == FiscalPreviousReception.initialHighRejected) !=
        (previousRegistryState == FiscalDeclaredRegistryState.doesNotExist)) {
      throw const RuleException(
        'Recepción y existencia declarada del registro incompatibles',
      );
    }
  }
  String get rejectionCode => switch (previousReception) {
    FiscalPreviousReception.acceptedWithErrors => 'N',
    FiscalPreviousReception.initialHighRejected => 'X',
    FiscalPreviousReception.correctionRejected => 'S',
  };
}

class FiscalAdvanceDeclaration {
  final String receiptId, receivedDate, futureOperationReference, reason;
  final int receivedCents;
  FiscalAdvanceDeclaration({
    required this.receiptId,
    required this.receivedDate,
    required this.futureOperationReference,
    required this.reason,
    required this.receivedCents,
  }) {
    _text(receiptId, 'Recibo de anticipo', 100);
    _date(receivedDate);
    _text(futureOperationReference, 'Operación futura', 100);
    _text(reason, 'Motivo del anticipo', 2000);
    if (receivedCents <= 0) {
      throw const RuleException('Anticipo recibido inválido');
    }
    _amount(receivedCents);
  }
}

class FiscalDocumentDraft {
  final String recordId,
      series,
      description,
      operationDate,
      technicalValidationDate;
  final VerifactuIdentity identity;
  final FiscalDocumentParty issuer;
  final FiscalDocumentParty? recipient;
  final FiscalDocumentShape shape;
  final FiscalDocumentCharges charges;
  final FiscalDeclaredRegime declaredRegime;
  final FiscalRectification? rectification;
  final FiscalRecordCorrection? recordCorrection;
  final FiscalAdvanceDeclaration? advance;
  final FiscalSimplificationBasis simplificationBasis;
  final FiscalOperationNature operationNature;
  final FiscalRecipientUse recipientUse;
  final Set<FiscalSimplificationExclusion> simplificationExclusions;
  final bool goodsMainlyForBusiness;
  final String qualificationReason;
  FiscalDocumentDraft({
    required this.recordId,
    required this.series,
    required this.description,
    required this.operationDate,
    required this.technicalValidationDate,
    required this.identity,
    required this.issuer,
    required this.shape,
    required this.charges,
    required this.declaredRegime,
    this.recipient,
    this.rectification,
    this.recordCorrection,
    this.advance,
    this.simplificationBasis = FiscalSimplificationBasis.none,
    this.operationNature = FiscalOperationNature.workshopService,
    this.recipientUse = FiscalRecipientUse.unknown,
    Iterable<FiscalSimplificationExclusion> simplificationExclusions = const [],
    this.goodsMainlyForBusiness = false,
    this.qualificationReason = '',
  }) : simplificationExclusions = Set.unmodifiable(simplificationExclusions) {
    _text(recordId, 'Identidad del documento de ensayo', 100);
    _series(series);
    _text(description, 'Descripción de operación', 500);
    _date(operationDate);
    _aeatNumber(identity.number);
    if (!series.startsWith('ENSAYO-') ||
        !identity.number.startsWith('$series/') ||
        issuer.nif == null ||
        issuer.nif != identity.issuerNif ||
        issuer.other != null ||
        issuer.country != 'ES') {
      throw const RuleException(
        'Solo documentos de ensayo con emisor nacional explícito',
      );
    }
    final issued = _date(identity.issueDate),
        operated = _date(operationDate),
        reviewed = _date(technicalValidationDate);
    if (charges.operationDate != operationDate ||
        operated.isAfter(issued) ||
        issued.isAfter(reviewed) ||
        issued.isBefore(_date('28-10-2024')) ||
        operated.isBefore(_subtractCalendarYears(reviewed, 20))) {
      throw const RuleException(
        'Fecha de operación incoherente o régimen futuro no implementado',
      );
    }
    if ((charges.surcharges.isNotEmpty) !=
        (declaredRegime == FiscalDeclaredRegime.equivalenceSurcharge)) {
      throw const RuleException(
        'El régimen debe declararse y coincidir con los recargos revisados',
      );
    }
    final calc = charges.calculation;
    if (calc.groups.any(
      (group) =>
          group.treatment != FiscalTreatment.taxable ||
          group.tax != FiscalTax.iva,
    )) {
      throw const RuleException(
        'Las reglas documentales actuales solo cubren IVA sujeto general',
      );
    }
    for (final group in calc.groups) {
      if (!_ivaAllowed(group.rateBps, _date(operationDate))) {
        throw const RuleException(
          'Tipo IVA no soportado para la fecha de operación',
        );
      }
    }
    if (shape == FiscalDocumentShape.simplified) {
      if (recipient != null || qualificationReason.isNotEmpty) {
        throw const RuleException(
          'La simplificada F2 no lleva destinatario en el registro AEAT',
        );
      }
    } else if (recipient == null) {
      throw const RuleException(
        'Este documento requiere identidad y domicilio del destinatario',
      );
    }
    if (shape == FiscalDocumentShape.qualifiedSimplified) {
      _text(qualificationReason, 'Petición de simplificada cualificada', 2000);
    } else if (qualificationReason.isNotEmpty) {
      throw const RuleException('Petición de cualificación incoherente');
    }
    if ([
          rectification,
          recordCorrection,
          advance,
        ].where((v) => v != null).length >
        1) {
      throw const RuleException(
        'No mezcles anticipo, rectificación y subsanación',
      );
    }
    if (rectification != null) {
      final original = rectification!.original;
      if (shape == FiscalDocumentShape.qualifiedSimplified) {
        throw const RuleException(
          'Rectificación de simplificada cualificada aún no modelada',
        );
      }
      if (original.identity.issuerNif != issuer.nif ||
          original.recordId == recordId ||
          original.series == series ||
          _sameIdentity(original.identity, identity) ||
          original.operationDate != operationDate ||
          _date(
            original.identity.issueDate,
          ).isAfter(_date(identity.issueDate)) ||
          (original.type == 'F2') !=
              (shape == FiscalDocumentShape.simplified)) {
        throw const RuleException(
          'Rectificación requiere serie separada y referencia compatible',
        );
      }
      if (rectification!.method == FiscalRectificationMethod.substitution &&
          calc.lines.any((line) => line.baseCents < 0)) {
        throw const RuleException(
          'La sustitución conserva el importe nuevo completo; no una diferencia negativa',
        );
      }
    } else if (calc.adjustmentReason.isNotEmpty ||
        calc.lines.any((line) => line.baseCents < 0)) {
      throw const RuleException(
        'Importe de ajuste requiere una rectificación explícita',
      );
    }
    if (recordCorrection != null) {
      final original = recordCorrection!.original;
      if (!_sameIdentity(original.identity, identity) ||
          original.series != series ||
          original.operationDate != operationDate ||
          original.recordId == recordId ||
          original.baseCents != calc.baseCents ||
          original.taxCents != calc.taxCents ||
          original.surchargeCents != charges.surchargeCents ||
          original.withholdingCents != charges.withholdingCents ||
          original.savedCharges!.economicComparisonKey !=
              charges.economicComparisonKey ||
          (original.type == 'F2') !=
              (shape == FiscalDocumentShape.simplified)) {
        throw const RuleException(
          'La subsanación conserva identidad e importes; cambios económicos necesitan otro circuito',
        );
      }
    }
    if (shape == FiscalDocumentShape.complete) {
      if (simplificationBasis != FiscalSimplificationBasis.none) {
        throw const RuleException(
          'La completa no necesita una autorización de simplificación',
        );
      }
    } else {
      _simplification();
    }
    if (advance != null) {
      if (rectification != null ||
          recordCorrection != null ||
          charges.surchargeCents != 0 ||
          charges.withholdingCents != 0 ||
          advance!.receivedCents != charges.invoiceTotalCents ||
          advance!.receivedDate != operationDate ||
          simplificationExclusions.contains(
            FiscalSimplificationExclusion.intraCommunityExemptGoods,
          )) {
        throw const RuleException(
          'Anticipo fuera del circuito general de importe recibido explícito',
        );
      }
    }
  }
  String get aeatType =>
      rectification?.type ??
      (shape == FiscalDocumentShape.simplified ? 'F2' : 'F1');
  bool get emissionEnabled => false;
  bool get transmissionEnabled => false;
  bool get persistenceImplemented => false;
  bool get officialValidationImplemented => false;
  int get settlementAdjustmentCents =>
      rectification?.method == FiscalRectificationMethod.substitution
      ? charges.invoiceTotalCents - rectification!.original.invoiceTotalCents
      : charges.invoiceTotalCents;
  Map<String, int>? get rectifiedAmounts =>
      rectification?.method == FiscalRectificationMethod.substitution
      ? Map.unmodifiable({
          'baseCents': rectification!.original.baseCents,
          'taxCents': rectification!.original.taxCents,
          'surchargeCents': rectification!.original.surchargeCents,
        })
      : null;
  Map<String, dynamic> toJson() => {
    'format': 'tallerflow-document-rules-sandbox-1',
    'recordId': recordId,
    'series': series,
    'number': identity.number,
    'issueDate': identity.issueDate,
    'operationDate': operationDate,
    'technicalValidationDate': technicalValidationDate,
    'description': description,
    'shape': shape.name,
    'aeatType': aeatType,
    'issuer': issuer.toJson(),
    if (recipient != null) 'recipient': recipient!.toJson(),
    'declaredRegime': declaredRegime.name,
    'charges': charges.toJson(),
    'settlementAdjustmentCents': settlementAdjustmentCents,
    'simplificationBasis': simplificationBasis.name,
    'operationNature': operationNature.name,
    'recipientUse': recipientUse.name,
    'goodsMainlyForBusiness': goodsMainlyForBusiness,
    'simplificationExclusions': simplificationExclusions
        .map((e) => e.name)
        .toList(),
    'qualificationReason': qualificationReason,
    if (rectification != null)
      'rectification': {
        'original': rectification!.original.toJson(),
        'method': rectification!.methodCode,
        'cause': rectification!.cause.name,
        'reason': rectification!.reason,
        if (rectifiedAmounts != null) 'rectifiedAmounts': rectifiedAmounts,
      },
    if (recordCorrection != null)
      'recordCorrection': {
        'original': recordCorrection!.original.toJson(),
        'reason': recordCorrection!.reason,
        'subsanacion': 'S',
        'rechazoPrevio': recordCorrection!.rejectionCode,
        'previousRegistryState': recordCorrection!.previousRegistryState.name,
        'previousReceiptReference': recordCorrection!.previousReceiptReference,
      },
    if (advance != null)
      'advance': {
        'receiptId': advance!.receiptId,
        'receivedDate': advance!.receivedDate,
        'receivedCents': advance!.receivedCents,
        'futureOperationReference': advance!.futureOperationReference,
        'reason': advance!.reason,
      },
    'emissionEnabled': false,
    'transmissionEnabled': false,
    'persistenceImplemented': false,
    'officialValidationImplemented': false,
  };
  void _simplification() {
    if (simplificationExclusions.isNotEmpty) {
      throw const RuleException(
        'La operación declarada excluye factura simplificada',
      );
    }
    if (rectification != null) {
      if (simplificationBasis != FiscalSimplificationBasis.rectification) {
        throw const RuleException(
          'La simplificada rectificativa requiere su fundamento explícito',
        );
      }
      return;
    }
    if (simplificationBasis == FiscalSimplificationBasis.upTo400 &&
        charges.invoiceTotalCents >= 0 &&
        charges.invoiceTotalCents <= 40000) {
      return;
    }
    if (simplificationBasis ==
            FiscalSimplificationBasis.consumerRetailUpTo3000 &&
        operationNature == FiscalOperationNature.consumerRetailGoods &&
        recipientUse == FiscalRecipientUse.consumer &&
        !goodsMainlyForBusiness &&
        charges.invoiceTotalCents >= 0 &&
        charges.invoiceTotalCents <= 300000) {
      return;
    }
    throw const RuleException(
      'Importe o actividad no permite esta simplificada',
    );
  }
}

bool _surchargeAllowed(int iva, int surcharge, DateTime date) {
  if (iva == 2100) return surcharge == 520 || surcharge == 175;
  if (iva == 1000) return surcharge == 140;
  if (iva == 400) return surcharge == 50;
  if (iva == 750 && _between(date, '01-10-2024', '31-12-2024')) {
    return surcharge == 100;
  }
  if (iva == 200 && _between(date, '01-10-2024', '31-12-2024')) {
    return surcharge == 26;
  }
  if (iva == 500 && _between(date, '01-07-2022', '31-12-2022')) {
    return surcharge == 50;
  }
  if (iva == 500 && _between(date, '01-01-2023', '30-09-2024')) {
    return surcharge == 62;
  }
  if (iva == 0 && _between(date, '01-01-2023', '30-09-2024')) {
    return surcharge == 0;
  }
  return false;
}

bool _ivaAllowed(int iva, DateTime date) =>
    {0, 400, 1000, 2100}.contains(iva) ||
    (iva == 500 && _between(date, '01-07-2022', '30-09-2024')) ||
    ({200, 750}.contains(iva) && _between(date, '01-10-2024', '31-12-2024'));
bool _between(DateTime date, String from, String to) =>
    !date.isBefore(_date(from)) && !date.isAfter(_date(to));
DateTime _subtractCalendarYears(DateTime value, int years) {
  final year = value.year - years;
  final lastDay = DateTime.utc(year, value.month + 1, 0).day;
  return DateTime.utc(
    year,
    value.month,
    value.day <= lastDay ? value.day : lastDay,
  );
}

bool _sameIdentity(VerifactuIdentity a, VerifactuIdentity b) =>
    a.issuerNif == b.issuerNif &&
    a.number == b.number &&
    a.issueDate == b.issueDate;
DateTime _date(String value) {
  validateFiscalDate(value);
  final p = value.split('-').map(int.parse).toList();
  return DateTime.utc(p[2], p[1], p[0]);
}

int _round(int base, int rate) {
  final numerator = BigInt.from(base) * BigInt.from(rate),
      divisor = BigInt.from(10000);
  final result =
      (numerator.abs() * BigInt.two + divisor) ~/ (divisor * BigInt.two);
  if (result > BigInt.from(1000000000000)) {
    throw const RuleException('Importe calculado fuera de rango');
  }
  return numerator.isNegative ? -result.toInt() : result.toInt();
}

int _amount(int amount) {
  if (amount.abs() > 1000000000000) {
    throw const RuleException('Importe documental fuera de rango');
  }
  return amount;
}

void _text(String value, String label, int max) {
  if (value.trim().isEmpty ||
      value.runes.length > max ||
      _hasUnpairedSurrogate(value) ||
      value.codeUnits.any(
        (c) =>
            (c < 32 && !{9, 10, 13}.contains(c)) || c == 0xfffe || c == 0xffff,
      )) {
    throw RuleException('$label inválido');
  }
}

bool _hasUnpairedSurrogate(String value) {
  final units = value.codeUnits;
  for (var i = 0; i < units.length; i++) {
    if (units[i] >= 0xd800 && units[i] <= 0xdbff) {
      if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
        return true;
      }
    } else if (units[i] >= 0xdc00 && units[i] <= 0xdfff) {
      return true;
    }
  }
  return false;
}

void _series(String value) {
  _text(value, 'Serie declarada', 50);
  _aeatNumber(value);
  if (value.contains('/')) {
    throw const RuleException('Serie declarada no soportada');
  }
}

void _aeatNumber(String number) {
  if (number.isEmpty ||
      number.length > 60 ||
      number.codeUnits.any((c) => c < 32 || c > 126) ||
      RegExp('["\'<>=]').hasMatch(number)) {
    throw const RuleException('Serie/número no cumple caracteres del registro');
  }
}

// Structural subset of the published EU NIF-IVA table. No VIES/census lookup.
// Historic GB/XI requires dated territory rules and is deliberately unsupported.
const _vatPatterns = <String, String>{
  'AT': r'[A-Z0-9]{9}',
  'BE': r'\d{10}',
  'BG': r'\d{9,10}',
  'HR': r'\d{11}',
  'CY': r'[A-Z0-9]{9}',
  'CZ': r'\d{8,10}',
  'DE': r'\d{9}',
  'DK': r'\d{8}',
  'EE': r'\d{9}',
  'FI': r'\d{8}',
  'FR': r'[A-Z0-9]{11}',
  'GR': r'\d{9}',
  'HU': r'\d{8}',
  'IE': r'[A-Z0-9]{8,9}',
  'IT': r'\d{11}',
  'LT': r'(\d{9}|\d{12})',
  'LU': r'\d{8}',
  'LV': r'\d{11}',
  'MT': r'\d{8}',
  'NL': r'[A-Z0-9]{12}',
  'PL': r'\d{10}',
  'PT': r'\d{9}',
  'RO': r'[1-9]\d{1,9}',
  'SE': r'\d{12}',
  'SI': r'\d{8}',
  'SK': r'\d{10}',
};

/// Pinned country codes from AEAT SuministroInformacion.xsd, CountryType2.
/// Special reporting codes are preserved; this does not assign tax treatment.
const aeatDocumentCountryCodes = <String>{
  'AF',
  'AL',
  'DE',
  'AD',
  'AO',
  'AI',
  'AQ',
  'AG',
  'SA',
  'DZ',
  'AR',
  'AM',
  'AW',
  'AU',
  'AT',
  'AZ',
  'BS',
  'BH',
  'BD',
  'BB',
  'BE',
  'BZ',
  'BJ',
  'BM',
  'BY',
  'BO',
  'BA',
  'BW',
  'BV',
  'BR',
  'BN',
  'BG',
  'BF',
  'BI',
  'BT',
  'CV',
  'KY',
  'KH',
  'CM',
  'CA',
  'CF',
  'CC',
  'CO',
  'KM',
  'CG',
  'CD',
  'CK',
  'KP',
  'KR',
  'CI',
  'CR',
  'HR',
  'CU',
  'TD',
  'CZ',
  'CL',
  'CN',
  'CY',
  'CW',
  'DK',
  'DM',
  'DO',
  'EC',
  'EG',
  'AE',
  'ER',
  'SK',
  'SI',
  'ES',
  'US',
  'EE',
  'ET',
  'FO',
  'PH',
  'FI',
  'FJ',
  'FR',
  'GA',
  'GM',
  'GE',
  'GS',
  'GH',
  'GI',
  'GD',
  'GR',
  'GL',
  'GU',
  'GT',
  'GG',
  'GN',
  'GQ',
  'GW',
  'GY',
  'HT',
  'HM',
  'HN',
  'HK',
  'HU',
  'IN',
  'ID',
  'IR',
  'IQ',
  'IE',
  'IM',
  'IS',
  'IL',
  'IT',
  'JM',
  'JP',
  'JE',
  'JO',
  'KZ',
  'KE',
  'KG',
  'KI',
  'KW',
  'LA',
  'LS',
  'LV',
  'LB',
  'LR',
  'LY',
  'LI',
  'LT',
  'LU',
  'XG',
  'MO',
  'MK',
  'MG',
  'MY',
  'MW',
  'MV',
  'ML',
  'MT',
  'FK',
  'MP',
  'MA',
  'MH',
  'MU',
  'MR',
  'YT',
  'UM',
  'MX',
  'FM',
  'MD',
  'MC',
  'MN',
  'ME',
  'MS',
  'MZ',
  'MM',
  'NA',
  'NR',
  'CX',
  'NP',
  'NI',
  'NE',
  'NG',
  'NU',
  'NF',
  'NO',
  'NC',
  'NZ',
  'IO',
  'OM',
  'NL',
  'BQ',
  'PK',
  'PW',
  'PA',
  'PG',
  'PY',
  'PE',
  'PN',
  'PF',
  'PL',
  'PT',
  'PR',
  'QA',
  'GB',
  'RW',
  'RO',
  'RU',
  'RE',
  'SB',
  'SV',
  'WS',
  'AS',
  'KN',
  'SM',
  'SX',
  'PM',
  'VC',
  'SH',
  'LC',
  'ST',
  'SN',
  'RS',
  'SC',
  'SL',
  'SG',
  'SY',
  'SO',
  'LK',
  'SZ',
  'ZA',
  'SD',
  'SS',
  'SE',
  'CH',
  'SR',
  'TH',
  'TW',
  'TZ',
  'TJ',
  'PS',
  'TF',
  'TL',
  'TG',
  'TK',
  'TO',
  'TT',
  'TN',
  'TC',
  'TM',
  'TR',
  'TV',
  'UA',
  'UG',
  'UY',
  'UZ',
  'VU',
  'VA',
  'VE',
  'VN',
  'VG',
  'VI',
  'WF',
  'YE',
  'DJ',
  'ZM',
  'ZW',
  'QU',
  'XB',
  'XU',
  'XN',
};
