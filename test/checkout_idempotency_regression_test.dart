import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/checkout/application/checkout_controller.dart';

import 'helpers/test_harness.dart';

void main() {
  late TestHarness harness;

  setUp(() => harness = TestHarness());
  tearDown(() => harness.dispose());

  Future<void> prepareCart() async {
    final product = harness.server.product('fruits-01');
    await harness.read(cartControllerProvider.notifier).replace(Cart(lines: [
          CartLine(
            productId: product.id,
            name: product.name,
            emoji: '🍌',
            unit: '6 pcs',
            unitPricePaise: product.pricePaise,
            quantity: 1,
            maxPerOrder: product.maxPerOrder,
          ),
        ]));
  }

  test('a lost order response and retry create only one order', () async {
    await prepareCart();
    harness.server.chaos.loseNextOrderResponses = 2;
    final checkout = harness.read(checkoutControllerProvider.notifier);

    await checkout.placeOrder();
    expect(harness.server.orderCount, 1);

    final retryResult = await checkout.placeOrder();

    expect(retryResult, isA<CheckoutSuccess>());
    expect(harness.server.orderCount, 1);
  });

  test('simultaneous place-order calls create only one order', () async {
    await prepareCart();
    harness.server.chaos.latencyOverride = (request) =>
        request.path == '/v1/orders'
            ? const Duration(milliseconds: 20)
            : Duration.zero;
    final checkout = harness.read(checkoutControllerProvider.notifier);

    final results = await Future.wait([
      checkout.placeOrder(),
      checkout.placeOrder(),
    ]);

    expect(results, everyElement(isA<CheckoutSuccess>()));
    expect(harness.server.orderCount, 1);
  });
}
