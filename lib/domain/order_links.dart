import 'models.dart';

/// Identifies an order; the controller still checks membership and assignment.
class OrderReference {
  final String value;
  final bool isNumber;
  const OrderReference(this.value, {this.isNumber = false});

  static OrderReference parse(String input) {
    final text = input.trim();
    if (text.length > 256) {
      throw const FormatException('Código demasiado largo');
    }
    if (RegExp(r'^OT-[0-9]{1,10}$', caseSensitive: false).hasMatch(text)) {
      return OrderReference(text.toUpperCase(), isNumber: true);
    }
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    if (uuid.hasMatch(text)) return OrderReference(text.toLowerCase());
    final uri = Uri.tryParse(text);
    if (uri == null ||
        uri.scheme != 'tallerflow' ||
        uri.host != 'order' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.length != 1 ||
        !uuid.hasMatch(uri.pathSegments.single) ||
        text != 'tallerflow://order/${uri.pathSegments.single}') {
      throw const FormatException(
        'Usa un QR de TallerFlow o un código OT válido',
      );
    }
    return OrderReference(uri.pathSegments.single.toLowerCase());
  }

  WorkOrder? resolve(Iterable<WorkOrder> permittedOrders) => permittedOrders
      .where((o) => isNumber ? o.number.toUpperCase() == value : o.id == value)
      .firstOrNull;
}

String orderLink(String id) {
  final ref = OrderReference.parse(id);
  if (ref.isNumber) {
    throw const FormatException('El QR requiere un identificador estable');
  }
  return 'tallerflow://order/${ref.value}';
}
