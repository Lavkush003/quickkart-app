import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart';
import 'package:quickkart/features/catalog/presentation/catalog_controller.dart';
import 'package:quickkart/features/checkout/application/checkout_controller.dart';
import 'package:quickkart/features/checkout/domain/order.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/cart_pricing.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/orders/data/order_tracking_repository.dart';

import 'helpers/test_harness.dart';

void main() {
  late TestHarness harness;

  setUp(() => harness = TestHarness());
  tearDown(() => harness.dispose());

  test('pull-to-refresh fetches updated catalog prices', () async {
    final provider = catalogControllerProvider(kAllProductsCategory);
    final loaded = Completer<void>();
    final subscription = harness.container.listen(
      provider,
      (previous, next) {
        if (!next.isLoadingFirstPage &&
            next.items.isNotEmpty &&
            !loaded.isCompleted) {
          loaded.complete();
        }
      },
      fireImmediately: true,
    );
    await loaded.future;

    final before = harness.read(provider).items.first;
    final updatedPrice = before.pricePaise + 500;
    harness.server.setPrice(before.id, updatedPrice);

    await harness.read(provider.notifier).refresh();

    expect(
      harness
          .read(provider)
          .items
          .firstWhere((p) => p.id == before.id)
          .pricePaise,
      updatedPrice,
    );
    subscription.close();
  });

  test('offline fallback keeps catalog pages scoped to their category',
      () async {
    final repository = harness.read(catalogRepositoryProvider);
    final fruitPage = await repository.getPage(categoryId: 'fruits', limit: 30);
    expect(fruitPage.items, isNotEmpty);
    expect(fruitPage.items.every((p) => p.categoryId == 'fruits'), isTrue);

    harness.server.chaos.offline = true;
    final dairyPage = await repository.getPage(categoryId: 'dairy', limit: 30);

    expect(dairyPage.fromCache, isTrue);
    expect(dairyPage.items, isNotEmpty);
    expect(dairyPage.items.every((p) => p.categoryId == 'dairy'), isTrue);
  });

  test('order history refreshes after a successful checkout', () async {
    expect(await harness.read(ordersProvider.future), isEmpty);

    final product = harness.server.product('fruits-01');
    final cart = Cart(lines: [
      CartLine(
        productId: product.id,
        name: product.name,
        emoji: '🍌',
        unit: '6 pcs',
        unitPricePaise: product.pricePaise,
        quantity: 1,
        maxPerOrder: product.maxPerOrder,
      ),
    ]);
    await harness.read(cartControllerProvider.notifier).replace(cart);

    final result =
        await harness.read(checkoutControllerProvider.notifier).placeOrder();

    expect(result, isA<CheckoutSuccess>());
    expect(
      await harness.read(ordersProvider.future),
      hasLength(1),
    );
  });
}
