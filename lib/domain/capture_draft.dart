enum CaptureKind { technical, plate, vin, reference }

List<String> captureCandidates(String raw, CaptureKind kind) {
  final text = raw.trim();
  if (kind == CaptureKind.technical) return text.isEmpty ? [] : [text];
  final upper = text.toUpperCase();
  if (kind == CaptureKind.plate) {
    return RegExp(
          r'(?<![A-Z0-9])\d{4}[\s-]*[BCDFGHJKLMNPRSTVWXYZ]{3}(?![A-Z0-9])',
        )
        .allMatches(upper)
        .map((m) => m[0]!.replaceAll(RegExp(r'[\s-]'), ''))
        .toSet()
        .toList();
  }
  if (kind == CaptureKind.vin) {
    return RegExp(
      r'(?<![A-Z0-9])[A-HJ-NPR-Z0-9]{17}(?![A-Z0-9])',
    ).allMatches(upper).map((m) => m[0]!).toSet().toList();
  }
  return text
      .split(RegExp(r'\r?\n'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet()
      .toList();
}

String reviewedCaptureValue(String text, CaptureKind kind) {
  final value = text.trim();
  final max = kind == CaptureKind.technical
      ? 2000
      : kind == CaptureKind.reference
      ? 100
      : 50;
  if (value.isEmpty || value.length > max) {
    throw FormatException('Revisa el texto: entre 1 y $max caracteres');
  }
  // Capture proposes text. Stock, timers and authorizations remain separate.
  return value;
}
