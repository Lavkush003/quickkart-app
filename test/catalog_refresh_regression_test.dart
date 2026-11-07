import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/network/api_client.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart';
import 'package:quickkart/features/catalog/data/catalog_api.dart';
import 'package:quickkart/features/catalog/data/catalog_cache.dart';
import 'package:quickkart/features/catalog/presentation/catalog_controller.dart';
import 'package:quickkart/features/checkout/application/checkout_controller.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
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

  test('concurrent pagination requests do not append duplicate products',
      () async {
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

    harness.server.chaos.latencyOverride = (request) =>
        request.path == '/v1/products'
            ? const Duration(milliseconds: 20)
            : Duration.zero;
    final controller = harness.read(provider.notifier);
    await Future.wait([controller.loadMore(), controller.loadMore()]);

    final ids = harness.read(provider).items.map((product) => product.id);
    expect(ids.toSet(), hasLength(ids.length));
    subscription.close();
  });

  test('offline fallback keeps catalog pages scoped to their category',
      () async {
    final repository = CatalogRepository(
      CatalogApi(ApiClient(
        harness.server.transport,
        maxRetries: 0,
        responseCacheTtl: Duration.zero,
      )),
      CatalogCache(harness.store),
    );
    final fruitPage = await repository.getPage(categoryId: 'fruits', limit: 30);
    final beveragePage =
        await repository.getPage(categoryId: 'beverages', limit: 30);
    expect(fruitPage.items, isNotEmpty);
    expect(fruitPage.items.every((p) => p.categoryId == 'fruits'), isTrue);
    expect(beveragePage.items, isNotEmpty);
    expect(
      beveragePage.items.every((p) => p.categoryId == 'beverages'),
      isTrue,
    );

    harness.server.chaos.offline = true;
    final offlineFruitPage =
        await repository.getPage(categoryId: 'fruits', limit: 30);
    final offlineBeveragePage =
        await repository.getPage(categoryId: 'beverages', limit: 30);

    expect(offlineFruitPage.fromCache, isTrue);
    expect(
      offlineFruitPage.items.every((p) => p.categoryId == 'fruits'),
      isTrue,
    );
    expect(offlineBeveragePage.fromCache, isTrue);
    expect(
      offlineBeveragePage.items.every((p) => p.categoryId == 'beverages'),
      isTrue,
    );
  });

  test('legacy catalog fields parse without crashing category browsing',
      () async {
    final page = await harness.read(catalogRepositoryProvider).getPage(
          categoryId: 'dairy',
          limit: 30,
        );
    final legacyMilk = page.items.firstWhere((p) => p.id == 'dairy-00');

    expect(legacyMilk.mrpPaise, legacyMilk.pricePaise);
    expect(legacyMilk.stock, 120);
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
