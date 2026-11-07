import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/cart_pricing.dart';

void main() {
  test('cart at the free-delivery threshold has no delivery fee', () {
    final cart = Cart(lines: [
      const CartLine(
        productId: 'threshold-item',
        name: 'Threshold item',
        emoji: '🛒',
        unit: '1 pc',
        unitPricePaise: 19900,
        quantity: 1,
        maxPerOrder: 1,
      ),
    ]);

    final pricing = CartPricing.compute(cart, AppConfig.defaults());

    expect(pricing.deliveryFeePaise, 0);
    expect(pricing.totalPaise, 19900);
  });
}
