import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/cart/data/coupon_api.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/checkout/application/checkout_controller.dart';
import 'package:quickkart/features/cart/domain/reconciliation.dart';

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

    final firstAttempt = await checkout.placeOrder();
    expect(firstAttempt, isA<CheckoutUnknown>());
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

  test('checkout checks connectivity before creating an order', () async {
    await prepareCart();
    harness.server.chaos.offline = true;

    final result =
        await harness.read(checkoutControllerProvider.notifier).placeOrder();

    expect(result, isA<CheckoutFailure>());
    expect((result as CheckoutFailure).message.toLowerCase(),
        contains('internet'));
    expect(harness.server.orderCount, 0);
  });

  test('checkout respects the current store-closed config', () async {
    await prepareCart();
    harness.server.publishConfig({
      'store_open': false,
      'store_closed_message': 'Closed for inventory',
    });

    final result =
        await harness.read(checkoutControllerProvider.notifier).placeOrder();

    expect(result, isA<CheckoutFailure>());
    expect(
        (result as CheckoutFailure).message, contains('Closed for inventory'));
    expect(harness.server.orderCount, 0);
  });

  test('a lost order response is reported as unknown, not failed', () async {
    await prepareCart();
    harness.server.chaos.loseNextOrderResponses = 2;

    final result =
        await harness.read(checkoutControllerProvider.notifier).placeOrder();

    expect(result, isA<CheckoutUnknown>());
    expect(harness.server.orderCount, 1);
  });

  test('order history resolves a lost response while the store is closed',
      () async {
    await prepareCart();
    harness.server.chaos.loseNextOrderResponses = 2;
    final checkout = harness.read(checkoutControllerProvider.notifier);
    final unknown = await checkout.placeOrder();
    expect(unknown, isA<CheckoutUnknown>());
    expect(harness.server.orderCount, 1);
    harness.server.publishConfig({
      'store_open': false,
      'store_closed_message': 'Closed for inventory',
    });

    final recovered = await checkout.placeOrder();

    expect(recovered, isA<CheckoutSuccess>());
    expect(harness.server.orderCount, 1);
  });

  test('order history resolves a close-during-retry race', () async {
    await prepareCart();
    harness.server.chaos.loseNextOrderResponses = 1;
    var configRequests = 0;
    harness.server.chaos.latencyOverride = (request) {
      if (request.path == '/v1/config') {
        configRequests++;
        if (configRequests == 2) {
          harness.server.publishConfig({
            'store_open': false,
            'store_closed_message': 'Closed during retry',
          });
        }
      }
      return Duration.zero;
    };

    final result =
        await harness.read(checkoutControllerProvider.notifier).placeOrder();

    expect(result, isA<CheckoutSuccess>());
    expect(harness.server.orderCount, 1);
  });

  test('restart resolves the original order after the cart has changed',
      () async {
    await prepareCart();
    harness.server.chaos.loseNextOrderResponses = 2;
    final firstAttempt =
        await harness.read(checkoutControllerProvider.notifier).placeOrder();
    expect(firstAttempt, isA<CheckoutUnknown>());
    expect(harness.server.orderCount, 1);
    final originalLine = harness.read(cartControllerProvider).lines.single;

    final previousHarness = harness;
    final restartedHarness = previousHarness.restart();
    previousHarness.dispose();
    harness = restartedHarness;
    await harness.read(cartControllerProvider.notifier).replace(
          Cart(lines: [originalLine.copyWith(quantity: 2)]),
        );

    final recovered =
        await harness.read(checkoutControllerProvider.notifier).placeOrder();

    expect(recovered, isA<CheckoutSuccess>());
    expect((recovered as CheckoutSuccess).order.items.single.quantity, 1);
    expect(harness.read(cartControllerProvider).quantityOf('fruits-01'), 1);
    expect(harness.server.orderCount, 1);
  });

  test('corrupt pending state fails closed without submitting a new order',
      () async {
    await prepareCart();
    await harness.store.setString('checkout.pending_order.v1', '{invalid');

    final result =
        await harness.read(checkoutControllerProvider.notifier).placeOrder();

    expect(result, isA<CheckoutUnknown>());
    expect(harness.server.orderCount, 0);
  });

  test('a below-minimum coupon stays on the cart but is not sent to the order',
      () async {
    await prepareCart();
    final cart = harness.read(cartControllerProvider);
    final coupon = await harness.read(couponApiProvider).validate('SAVE10');
    await harness.read(cartControllerProvider.notifier).replace(
          cart.withCoupon(coupon),
        );

    final result =
        await harness.read(checkoutControllerProvider.notifier).placeOrder();

    expect(result, isA<CheckoutSuccess>());
    final order = (result as CheckoutSuccess).order;
    expect(order.couponCode, isNull);
    expect(order.discountPaise, 0);
    expect(harness.server.orderCount, 1);
  });

  test('invalid final cart is rejected before the order request', () async {
    await prepareCart();
    final line = harness.read(cartControllerProvider).lines.single;
    await harness.read(cartControllerProvider.notifier).replace(
          Cart(lines: [line.copyWith(quantity: 0)]),
        );

    final result =
        await harness.read(checkoutControllerProvider.notifier).placeOrder();

    expect(result, isA<CheckoutFailure>());
    expect((result as CheckoutFailure).message, contains('invalid'));
    expect(harness.server.orderCount, 0);
  });

  test('a stock race at submission is reconciled for customer review',
      () async {
    await prepareCart();
    harness.server.chaos.latencyOverride = (request) {
      if (request.path == '/v1/orders') {
        harness.server.setStock('fruits-01', 0);
      }
      return Duration.zero;
    };

    final result =
        await harness.read(checkoutControllerProvider.notifier).placeOrder();

    expect(result, isA<CheckoutNeedsReview>());
    final changes = (result as CheckoutNeedsReview).reconciliation.changes;
    expect(changes.single, isA<OutOfStock>());
    expect(harness.server.orderCount, 0);
  });
}
