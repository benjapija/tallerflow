import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import '../domain/order_links.dart';

class OrderLinkInbox extends ChangeNotifier {
  static final shared = OrderLinkInbox();
  OrderReference? pending;
  StreamSubscription<Uri>? _subscription;

  void startNative() {
    if (kIsWeb || _subscription != null) return;
    _subscription = AppLinks().uriLinkStream.listen(
      (uri) => receive(uri.toString()),
      onError: (Object _) {},
    );
  }

  void receive(String raw) {
    try {
      pending = OrderReference.parse(raw);
      notifyListeners();
    } on FormatException {
      // Unrelated links never navigate, switch accounts or change privileges.
    }
  }

  void clear() => pending = null;
}
