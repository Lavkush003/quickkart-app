import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/cart/data/cart_storage.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart';
import 'package:quickkart/features/checkout/application/checkout_controller.dart';
import 'package:quickkart/features/cart/presentation/cart_screen.dart';

import 'helpers/test_harness.dart';

void main() {
  late TestHarness harness;

  setUp(() => harness = TestHarness());
  tearDown(() => harness.dispose());

  test('checkout waits for explicit acceptance of reconciliation changes',
      () async {
    final product =
        (await harness.read(catalogApiProvider).getProductsByIds(['fruits-01']))
            .products
            .single;
    await harness.read(cartControllerProvider.notifier).replace(
          Cart(lines: [CartLine.fromProduct(product)]),
        );
    harness.server.setPrice(product.id, product.pricePaise + 100);
    final checkout = harness.read(checkoutControllerProvider.notifier);

    final firstAttempt = await checkout.placeOrder();

    expect(firstAttempt, isA<CheckoutNeedsReview>());
    expect(harness.server.orderCount, 0);
    expect(
      harness.read(cartControllerProvider).lineFor(product.id)!.unitPricePaise,
      product.pricePaise + 100,
    );

    final unacceptedAttempt = await checkout.placeOrder();

    expect(unacceptedAttempt, isA<CheckoutNeedsReview>());
    expect(harness.server.orderCount, 0);

    await checkout.acceptChanges();
    final acceptedAttempt = await checkout.placeOrder();

    expect(acceptedAttempt, isA<CheckoutSuccess>());
    expect(harness.server.orderCount, 1);
  });

  test('unaccepted reconciliation is still required after app restart',
      () async {
    final product =
        (await harness.read(catalogApiProvider).getProductsByIds(['fruits-01']))
            .products
            .single;
    await harness.read(cartControllerProvider.notifier).replace(
          Cart(lines: [CartLine.fromProduct(product)]),
        );
    harness.server.setPrice(product.id, product.pricePaise + 100);
    final firstAttempt =
        await harness.read(checkoutControllerProvider.notifier).placeOrder();
    expect(firstAttempt, isA<CheckoutNeedsReview>());
    expect(harness.server.orderCount, 0);

    final previousHarness = harness;
    final restartedHarness = previousHarness.restart();
    final restoredCart =
        await restartedHarness.read(cartStorageProvider).load();
    restartedHarness
        .read(cartControllerProvider.notifier)
        .hydrate(restoredCart);
    previousHarness.dispose();
    harness = restartedHarness;

    final afterRestart =
        await harness.read(checkoutControllerProvider.notifier).placeOrder();

    expect(afterRestart, isA<CheckoutNeedsReview>());
    expect(harness.server.orderCount, 0);
  });

  testWidgets('review dialog explains changes before the user accepts them',
      (tester) async {
    final product =
        (await harness.read(catalogApiProvider).getProductsByIds(['fruits-01']))
            .products
            .single;
    await harness.read(cartControllerProvider.notifier).replace(
          Cart(lines: [CartLine.fromProduct(product)]),
        );
    harness.server.setPrice(product.id, product.pricePaise + 100);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: const MaterialApp(home: CartScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Place order  ▶'));
    await tester.pumpAndSettle();

    expect(find.text('Review cart changes'), findsOneWidget);
    expect(
      find.textContaining('${product.name}: price increased'),
      findsOneWidget,
    );
    expect(harness.server.orderCount, 0);

    await tester.tap(find.text('Accept changes'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Changes accepted'), findsOneWidget);
    expect(harness.server.orderCount, 0);
  });

  testWidgets(
      'removed products remain explained when reconciliation empties cart',
      (tester) async {
    final product =
        (await harness.read(catalogApiProvider).getProductsByIds(['fruits-01']))
            .products
            .single;
    await harness.read(cartControllerProvider.notifier).replace(
          Cart(lines: [CartLine.fromProduct(product)]),
        );
    harness.server.setStock(product.id, 0);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: const MaterialApp(home: CartScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Place order  ▶'));
    await tester.pumpAndSettle();

    expect(find.text('Review cart changes'), findsOneWidget);
    expect(
      find.text('${product.name} is out of stock and was removed.'),
      findsOneWidget,
    );
    expect(harness.server.orderCount, 0);
  });
}
