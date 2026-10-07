import 'engine.dart';
import 'models.dart';

enum FiscalTax { iva, igic, ipsi, other }

enum FiscalTreatment { taxable, exempt, reverseCharge, outsideScope }

/// Arithmetic only: rates and legal treatment must be supplied and reviewed.
/// This model neither assigns an obligation nor issues a fiscal document.
class FiscalLine {
  final String id, description, legalReason;
  final int quantityMilli, unitPriceCents, discountBps, rateBps;
  final FiscalTax tax;
  final FiscalTreatment treatment;
  FiscalLine({
    required this.id,
    required this.description,
    required this.quantityMilli,
    required this.unitPriceCents,
    required this.rateBps,
    required this.tax,
    this.discountBps = 0,
    this.treatment = FiscalTreatment.taxable,
    this.legalReason = '',
  }) {
    _text(id, 'Identificador de partida', 100);
    _text(description, 'Descripción', 4000);
    if (quantityMilli <= 0 || quantityMilli > 1000000000) {
      throw const RuleException('Cantidad fuera de rango');
    }
    _amount(unitPriceCents);
    _rate(rateBps);
    _rate(discountBps);
    if (treatment != FiscalTreatment.taxable) {
      _text(legalReason, 'Motivo del tratamiento fiscal', 1000);
      if (rateBps != 0) {
        throw const RuleException(
          'Este tratamiento no repercute cuota; revisa el tipo',
        );
      }
    } else if (legalReason.isNotEmpty) {
      _text(legalReason, 'Referencia fiscal', 1000);
    }
  }
}

class FiscalCalculatedLine {
  final FiscalLine source;
  final int grossCents, discountCents, baseCents, taxCents;
  const FiscalCalculatedLine._(
    this.source,
    this.grossCents,
    this.discountCents,
    this.baseCents,
    this.taxCents,
  );
  int get totalCents => baseCents + taxCents;
}

class FiscalTaxGroup {
  final FiscalTax tax;
  final FiscalTreatment treatment;
  final int rateBps, baseCents, taxCents;
  final String legalReason;
  const FiscalTaxGroup._(
    this.tax,
    this.treatment,
    this.rateBps,
    this.legalReason,
    this.baseCents,
    this.taxCents,
  );
}

class FiscalCalculation {
  final List<FiscalCalculatedLine> lines;
  final List<FiscalTaxGroup> groups;
  final int baseCents, taxCents, totalCents;
  final String adjustmentReason;
  bool get emissionEnabled => false;
  const FiscalCalculation._(
    this.lines,
    this.groups,
    this.baseCents,
    this.taxCents,
    this.totalCents,
    this.adjustmentReason,
  );

  /// Round quantity, discount and tax once per line, half away from zero.
  /// Group totals sum those saved line values; they are never rounded again.
  factory FiscalCalculation.calculate(
    Iterable<FiscalLine> input, {
    String adjustmentReason = '',
  }) {
    final sources = List<FiscalLine>.of(input);
    if (sources.isEmpty || sources.length > 1000) {
      throw const RuleException('Indica entre una y mil partidas');
    }
    if (sources.map((l) => l.id).toSet().length != sources.length) {
      throw const RuleException('Identificador de partida repetido');
    }
    if (adjustmentReason.isNotEmpty) {
      _text(adjustmentReason, 'Motivo de ajuste', 1000);
    }
    final lines = <FiscalCalculatedLine>[], groups = <FiscalTaxGroup>[];
    for (final source in sources) {
      if (source.unitPriceCents < 0 && adjustmentReason.trim().isEmpty) {
        throw const RuleException(
          'El importe negativo requiere motivo de ajuste',
        );
      }
      final gross = _product(source.unitPriceCents, source.quantityMilli, 1000);
      final discount = _product(gross, source.discountBps, 10000);
      final base = _amount(gross - discount);
      final tax = _product(base, source.rateBps, 10000);
      _amount(base + tax);
      lines.add(FiscalCalculatedLine._(source, gross, discount, base, tax));
      final index = groups.indexWhere(
        (g) =>
            g.tax == source.tax &&
            g.treatment == source.treatment &&
            g.rateBps == source.rateBps &&
            g.legalReason == source.legalReason,
      );
      final old = index < 0 ? null : groups.removeAt(index);
      final group = FiscalTaxGroup._(
        source.tax,
        source.treatment,
        source.rateBps,
        source.legalReason,
        _amount((old?.baseCents ?? 0) + base),
        _amount((old?.taxCents ?? 0) + tax),
      );
      if (index < 0) {
        groups.add(group);
      } else {
        groups.insert(index, group);
      }
    }
    final base = _amount(lines.fold<int>(0, (s, l) => s + l.baseCents));
    final tax = _amount(lines.fold<int>(0, (s, l) => s + l.taxCents));
    return FiscalCalculation._(
      List.unmodifiable(lines),
      List.unmodifiable(groups),
      base,
      tax,
      _amount(base + tax),
      adjustmentReason,
    );
  }
}

class SavedTaxGroup {
  final int? rateBps;
  final int baseCents, taxCents, lineCount;
  const SavedTaxGroup._(
    this.rateBps,
    this.baseCents,
    this.taxCents,
    this.lineCount,
  );
}

/// Reads an existing work document without choosing a tax from today's profile.
/// Legacy rows without a saved percentage remain explicitly unidentified.
class SavedTaxBreakdown {
  final List<SavedTaxGroup> groups;
  final int baseCents, taxCents, totalCents;
  const SavedTaxBreakdown._(
    this.groups,
    this.baseCents,
    this.taxCents,
    this.totalCents,
  );
  factory SavedTaxBreakdown.fromNote(Map<String, dynamic> note, Actor actor) {
    if (!actor.active || !actor.isOffice) {
      throw const RuleException('Se requiere una cuenta activa de oficina');
    }
    if (note['lines'] is! List || (note['lines'] as List).length > 1000) {
      throw const RuleException('Partidas guardadas inválidas');
    }
    final groups = <int?, SavedTaxGroup>{};
    var base = 0, tax = 0;
    for (final raw in note['lines']) {
      if (raw is! Map || raw['netCents'] is! int || raw['taxCents'] is! int) {
        throw const RuleException('Importes guardados inválidos');
      }
      final int b = _amount(raw['netCents']), t = _amount(raw['taxCents']);
      final r = raw['taxBps'];
      if (r != null) {
        if (r is! int) throw const RuleException('Tipo guardado inválido');
        _rate(r);
      }
      if (raw['totalCents'] != null && raw['totalCents'] != b + t) {
        throw const RuleException('Total de partida incoherente');
      }
      final old = groups[r];
      groups[r] = SavedTaxGroup._(
        r,
        _amount((old?.baseCents ?? 0) + b),
        _amount((old?.taxCents ?? 0) + t),
        (old?.lineCount ?? 0) + 1,
      );
      base = _amount(base + b);
      tax = _amount(tax + t);
    }
    if (note['netCents'] != base ||
        note['taxCents'] != tax ||
        note['totalCents'] != base + tax) {
      throw const RuleException('Los importes guardados no cuadran');
    }
    return SavedTaxBreakdown._(
      List.unmodifiable(groups.values),
      base,
      tax,
      _amount(base + tax),
    );
  }
}

String fiscalDecimal(int cents) {
  _amount(cents);
  return '${cents < 0 ? '-' : ''}${cents.abs() ~/ 100}.${(cents.abs() % 100).toString().padLeft(2, '0')}';
}

int _product(int a, int b, int divisor) {
  final n = BigInt.from(a) * BigInt.from(b), d = BigInt.from(divisor);
  final rounded = (n.abs() * BigInt.two + d) ~/ (d * BigInt.two);
  if (rounded > BigInt.from(1000000000000)) {
    throw const RuleException('Importe fuera de rango');
  }
  return n.isNegative ? -rounded.toInt() : rounded.toInt();
}

int _amount(int value) {
  if (value.abs() > 1000000000000) {
    throw const RuleException('Importe fuera de rango');
  }
  return value;
}

void _rate(int value) {
  if (value < 0 || value > 10000) {
    throw const RuleException('Porcentaje fuera de rango');
  }
}

void _text(String value, String field, int max) {
  if (value.trim().isEmpty || value.length > max || value.contains('\u0000')) {
    throw RuleException('$field inválido');
  }
}
