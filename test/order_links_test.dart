import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/order_link_inbox.dart';
import 'package:tallerflow/domain/order_links.dart';

void main() {
  const id = '1d4e7ee1-303c-483b-81bf-1ac1d2148f91';
  test('QR and native link have one canonical stable order identity', () {
    expect(OrderReference.parse(orderLink(id)).value, id);
    expect(OrderReference.parse(id.toUpperCase()).value, id);
    expect(
      OrderReference.parse(' ot-1048 ').resolve(demoState().orders.values)?.id,
      'o-1048',
    );
  });
  test(
    'Foreign URLs, credentials, query tokens and malformed paths do not navigate',
    () {
      for (final value in [
        'https://example.org/$id',
        'tallerflow://order/$id?token=secret',
        'tallerflow://order/$id#action=approve',
        'tallerflow://person@order/$id',
        'tallerflow://order:8080/$id',
        'tallerflow://order//$id',
        'tallerflow://order/%31${id.substring(1)}',
        'tallerflow://order/../$id',
        'tallerflow://order/$id/',
        'OT-1048/anything',
        'o-1048',
      ]) {
        expect(
          () => OrderReference.parse(value),
          throwsFormatException,
          reason: value,
        );
      }
    },
  );
  test('A valid code cannot discover an unassigned or unavailable order', () {
    final orders = demoState().orders.values;
    expect(
      OrderReference.parse(
        'OT-1048',
      ).resolve(orders.where((o) => o.assigned('unassigned'))),
      isNull,
    );
    expect(
      OrderReference.parse(
        'OT-1048',
      ).resolve(orders.where((o) => o.assigned('tech-alex'))),
      isNotNull,
    );
    expect(OrderReference.parse(id).resolve(orders), isNull);
  });
  test('Initial link survives login; malformed events cannot replace it', () {
    final inbox = OrderLinkInbox();
    inbox.receive(orderLink(id));
    inbox.receive('https://unrelated.invalid/login');
    expect(inbox.pending?.value, id);
    inbox.clear();
    expect(inbox.pending, isNull);
  });
}
