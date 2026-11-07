import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/cart/data/cart_storage.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/coupon.dart';
import 'package:quickkart/features/catalog/domain/product.dart';

import 'helpers/test_harness.dart';

void main() {
  late TestHarness harness;

  setUp(() => harness = TestHarness());
  tearDown(() => harness.dispose());

  final product = Product(
    id: 'fruits-01',
    name: 'Banana',
    categoryId: 'fruits',
    emoji: '🍌',
    unit: '6 pcs',
    pricePaise: 4900,
    mrpPaise: 5900,
    stock: 10,
    maxPerOrder: 5,
  );
  final coupon = Coupon(
    code: 'SAVE10',
    type: CouponType.percent,
    value: 10,
    maxDiscountPaise: 7500,
    minOrderPaise: 0,
    expiresAt: DateTime.utc(2099),
  );
  final initialCart = Cart(
    lines: [CartLine.fromProduct(product, quantity: 2)],
    coupon: coupon,
  );

  Future<void> prepare(Cart cart) async {
    await harness.read(cartStorageProvider).save(cart);
    harness.read(cartControllerProvider.notifier).hydrate(cart);
  }

  Future<void> expectPersisted(Cart expected) async {
    expect(await harness.read(cartStorageProvider).load(), expected);
  }

  test('add persists the cart', () async {
    await prepare(const Cart.empty());
    await harness.read(cartControllerProvider.notifier).add(product);
    await expectPersisted(Cart(lines: [CartLine.fromProduct(product)]));
  });

  test('increment persists the cart', () async {
    final initial = initialCart.withoutCoupon();
    await prepare(initial);
    await harness.read(cartControllerProvider.notifier).increment(product.id);
    await expectPersisted(initial.updateQuantity(product.id, 3));
  });

  test('decrement persists the cart', () async {
    final initial = initialCart.withoutCoupon();
    await prepare(initial);
    await harness.read(cartControllerProvider.notifier).decrement(product.id);
    await expectPersisted(initial.updateQuantity(product.id, 1));
  });

  test('remove persists the cart', () async {
    await prepare(initialCart);
    await harness.read(cartControllerProvider.notifier).remove(product.id);
    await expectPersisted(const Cart.empty());
  });

  test('applyCoupon persists the cart', () async {
    final initial = initialCart.withoutCoupon();
    await prepare(initial);
    await harness.read(cartControllerProvider.notifier).applyCoupon(coupon);
    await expectPersisted(initial.withCoupon(coupon));
  });

  test('removeCoupon persists the cart', () async {
    await prepare(initialCart);
    await harness.read(cartControllerProvider.notifier).removeCoupon();
    await expectPersisted(initialCart.withoutCoupon());
  });

  test('replace persists the cart', () async {
    await prepare(initialCart);
    const replacement = Cart.empty();
    await harness.read(cartControllerProvider.notifier).replace(replacement);
    await expectPersisted(replacement);
  });

  test('clear persists the cart', () async {
    await prepare(initialCart);
    await harness.read(cartControllerProvider.notifier).clear();
    await expectPersisted(const Cart.empty());
  });
}
