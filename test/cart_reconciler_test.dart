import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/network/api_exceptions.dart';
import 'package:quickkart/core/providers.dart';
import 'package:quickkart/features/cart/application/cart_reconciler.dart';
import 'package:quickkart/features/cart/data/coupon_api.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/coupon.dart';
import 'package:quickkart/features/cart/domain/reconciliation.dart';
import 'package:quickkart/features/catalog/data/catalog_api.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart';
import 'package:quickkart/features/catalog/domain/product.dart';

import 'helpers/test_harness.dart';

void main() {
  late TestHarness harness;

  setUp(() => harness = TestHarness());
  tearDown(() => harness.dispose());

  Future<Product> product(String id) async {
    final batch = await harness.read(catalogRepositoryProvider).getPage(
          categoryId: id.split('-').first,
          limit: 30,
        );
    return batch.items.firstWhere((item) => item.id == id);
  }

  CartLine line(Product product, {int quantity = 1}) =>
      CartLine.fromProduct(product, quantity: quantity);

  CartReconciler reconciler() => harness.read(cartReconcilerProvider);

  test('unchanged cart returns an equal cart and no changes', () async {
    final item = await product('fruits-01');
    final cart = Cart(lines: [line(item, quantity: 2)]);

    final result = await reconciler().reconcile(cart);

    expect(result.cart, cart);
    expect(result.changes, isEmpty);
    expect(result.requiresUserReview, isFalse);
  });

  test('price decrease is applied without requiring review', () async {
    final item = await product('fruits-01');
    final cart = Cart(lines: [line(item)]);
    final updatedPrice = item.pricePaise - 100;
    harness.server.setPrice(item.id, updatedPrice);

    final result = await reconciler().reconcile(cart);

    expect(result.cart.lineFor(item.id)!.unitPricePaise, updatedPrice);
    expect(result.changes, hasLength(1));
    expect(result.changes.single, isA<PriceChanged>());
    expect(result.requiresUserReview, isFalse);
  });

  test('price increase is applied and requires review', () async {
    final item = await product('fruits-01');
    final cart = Cart(lines: [line(item)]);
    final updatedPrice = item.pricePaise + 100;
    harness.server.setPrice(item.id, updatedPrice);

    final result = await reconciler().reconcile(cart);

    expect(result.cart.lineFor(item.id)!.unitPricePaise, updatedPrice);
    expect(result.changes.single, isA<PriceChanged>());
    expect(result.requiresUserReview, isTrue);
  });

  test('stock reduction lowers the quantity and requires review', () async {
    final item = await product('fruits-01');
    final cart = Cart(lines: [line(item, quantity: 3)]);
    harness.server.setStock(item.id, 1);

    final result = await reconciler().reconcile(cart);

    expect(result.cart.quantityOf(item.id), 1);
    expect(result.cart.lineFor(item.id)!.maxPerOrder, 1);
    expect(result.changes.single, isA<QuantityReduced>());
    expect(result.requiresUserReview, isTrue);
  });

  test('out-of-stock products are removed and require review', () async {
    final item = await product('fruits-01');
    final cart = Cart(lines: [line(item)]);
    harness.server.setStock(item.id, 0);

    final result = await reconciler().reconcile(cart);

    expect(result.cart.lines, isEmpty);
    expect(result.changes.single, isA<OutOfStock>());
    expect(result.requiresUserReview, isTrue);
  });

  test('discontinued products are removed and require review', () async {
    final item = await product('fruits-01');
    final cart = Cart(lines: [line(item)]);
    harness.server.setActive(item.id, false);

    final result = await reconciler().reconcile(cart);

    expect(result.cart.lines, isEmpty);
    expect(result.changes.single, isA<ProductUnavailable>());
    expect(result.requiresUserReview, isTrue);
  });

  test('expired coupon is removed with a reviewable change', () async {
    final item = await product('fruits-01');
    final coupon = await harness.read(couponApiProvider).validate('SAVE10');
    final cart = Cart(lines: [line(item)], coupon: coupon);
    harness.server.expireCoupon(coupon.code);

    final result = await reconciler().reconcile(cart);

    expect(result.cart.coupon, isNull);
    expect(result.changes.single, isA<CouponRemoved>());
    expect((result.changes.single as CouponRemoved).reason, 'EXPIRED');
    expect(result.requiresUserReview, isTrue);
  });

  test('unknown coupon is removed with a reviewable change', () async {
    final item = await product('fruits-01');
    final cart = Cart(
      lines: [line(item)],
      coupon: Coupon(
        code: 'OLD_CODE',
        type: CouponType.flat,
        value: 100,
        minOrderPaise: 0,
        expiresAt: DateTime.utc(2099),
      ),
    );

    final result = await reconciler().reconcile(cart);

    expect(result.cart.coupon, isNull);
    expect(result.changes.single, isA<CouponRemoved>());
    expect((result.changes.single as CouponRemoved).reason, 'NOT_FOUND');
  });

  test('latest coupon rules replace old rules and require review', () async {
    final item = await product('fruits-01');
    final oldCoupon = await harness.read(couponApiProvider).validate('SAVE10');
    final cart = Cart(lines: [line(item)], coupon: oldCoupon);
    final latestCoupon = Coupon(
      code: oldCoupon.code,
      type: oldCoupon.type,
      value: oldCoupon.value,
      maxDiscountPaise: 1000,
      minOrderPaise: oldCoupon.minOrderPaise + 100,
      expiresAt: oldCoupon.expiresAt,
      description: 'Updated terms',
    );
    final api = _FixedCouponApi(harness.read(apiClientProvider), latestCoupon);
    final subject = CartReconciler(
      catalogApi: harness.read(catalogApiProvider),
      couponApi: api,
    );

    final result = await subject.reconcile(cart);

    expect(result.cart.coupon, latestCoupon);
    expect(result.changes.single.toString(), 'CouponChanged(SAVE10)');
    expect(result.requiresUserReview, isTrue);
  });

  test('multiple simultaneous conflicts are all returned in cart order',
      () async {
    final products = await Future.wait([
      product('fruits-01'),
      product('dairy-03'),
      product('snacks-01'),
      product('beverages-01'),
    ]);
    final coupon = await harness.read(couponApiProvider).validate('SAVE10');
    final cart = Cart(
      lines: [
        line(products[0], quantity: 2),
        line(products[1]),
        line(products[2], quantity: 3),
        line(products[3]),
      ],
      coupon: coupon,
    );
    harness.server.setPrice(products[0].id, products[0].pricePaise + 100);
    harness.server.setStock(products[1].id, 0);
    harness.server.setStock(products[2].id, 1);
    harness.server.setActive(products[3].id, false);
    harness.server.expireCoupon(coupon.code);

    final result = await reconciler().reconcile(cart);

    expect(result.changes, hasLength(5));
    expect(result.changes[0], isA<PriceChanged>());
    expect(result.changes[1], isA<OutOfStock>());
    expect(result.changes[2], isA<QuantityReduced>());
    expect(result.changes[3], isA<ProductUnavailable>());
    expect(result.changes[4], isA<CouponRemoved>());
    expect(result.cart.lines.map((item) => item.productId),
        [products[0].id, products[2].id]);
    expect(result.requiresUserReview, isTrue);
  });

  test('empty cart returns without making a network request', () async {
    final before = harness.server.requestLog.length;

    final result = await reconciler().reconcile(const Cart.empty());

    expect(result.cart, const Cart.empty());
    expect(result.changes, isEmpty);
    expect(harness.server.requestLog.length, before);
  });

  test('cart with more than 50 products is fetched in contract-sized batches',
      () async {
    final ids = harness.server.productIds.take(51).toList();
    final products = <Product>[];
    for (var start = 0; start < ids.length; start += 50) {
      final end = (start + 50).clamp(0, ids.length);
      products.addAll(
        (await harness
                .read(catalogApiProvider)
                .getProductsByIds(ids.sublist(start, end)))
            .products,
      );
    }
    final cart = Cart(lines: products.map(line).toList());
    harness.server.requestLog.clear();

    await reconciler().reconcile(cart);

    final batches = harness.server.requestLog
        .where((request) => request.path == '/v1/products/batch')
        .toList();
    expect(batches, hasLength(2));
    for (final request in batches) {
      final body = jsonDecode(request.body!) as Map<String, dynamic>;
      expect((body['ids'] as List), hasLength(lessThanOrEqualTo(50)));
    }
  });

  test('unexpected product ids are rejected without a partial result',
      () async {
    final item = await product('fruits-01');
    final cart = Cart(lines: [line(item)]);
    final unexpectedProduct = Product(
      id: 'unexpected',
      name: 'Unexpected',
      categoryId: item.categoryId,
      emoji: '🛒',
      unit: '1 pc',
      pricePaise: item.pricePaise,
      mrpPaise: item.mrpPaise,
      stock: item.stock,
      maxPerOrder: item.maxPerOrder,
    );
    final subject = CartReconciler(
      catalogApi: _FixedCatalogApi(
        harness.read(apiClientProvider),
        ProductBatch(products: [unexpectedProduct], missingIds: []),
      ),
      couponApi: harness.read(couponApiProvider),
    );

    await expectLater(
      subject.reconcile(cart),
      throwsA(isA<ServerException>()),
    );
  });

  test('coupon network errors do not return a partially reconciled cart',
      () async {
    final item = await product('fruits-01');
    final coupon = await harness.read(couponApiProvider).validate('SAVE10');
    final cart = Cart(lines: [line(item)], coupon: coupon);
    harness.server.setPrice(item.id, item.pricePaise + 100);
    final subject = CartReconciler(
      catalogApi: harness.read(catalogApiProvider),
      couponApi: _FailingCouponApi(harness.read(apiClientProvider)),
    );

    await expectLater(
      subject.reconcile(cart),
      throwsA(isA<NetworkException>()),
    );
  });
}

class _FixedCatalogApi extends CatalogApi {
  _FixedCatalogApi(super.client, this.batch);

  final ProductBatch batch;

  @override
  Future<ProductBatch> getProductsByIds(List<String> ids) async => batch;
}

class _FixedCouponApi extends CouponApi {
  _FixedCouponApi(super.client, this.coupon);

  final Coupon coupon;

  @override
  Future<Coupon> validate(String code) async => coupon;
}

class _FailingCouponApi extends CouponApi {
  _FailingCouponApi(super.client);

  @override
  Future<Coupon> validate(String code) async => throw const NetworkException();
}
