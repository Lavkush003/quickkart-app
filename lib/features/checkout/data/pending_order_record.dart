import '../../cart/domain/cart.dart';
import '../../cart/domain/cart_pricing.dart';
import '../domain/order.dart';

/// Durable copy of the exact request needed to safely retry checkout.
class PendingOrderRecord {
  const PendingOrderRecord({
    required this.key,
    required this.cart,
    required this.pricing,
    required this.attempts,
    required this.startedAt,
    this.confirmedOrder,
  });

  final String key;
  final Cart cart;
  final CartPricing pricing;
  final int attempts;
  final DateTime? startedAt;
  final Order? confirmedOrder;

  PendingOrderRecord withAttempts(int value) => PendingOrderRecord(
        key: key,
        cart: cart,
        pricing: pricing,
        attempts: value,
        startedAt: startedAt,
        confirmedOrder: confirmedOrder,
      );

  PendingOrderRecord withConfirmedOrder(Order order) => PendingOrderRecord(
        key: key,
        cart: cart,
        pricing: pricing,
        attempts: attempts,
        startedAt: startedAt,
        confirmedOrder: order,
      );

  Map<String, dynamic> toJson() => {
        'version': 2,
        'key': key,
        'cart': cart.toJson(),
        'pricing': {
          'subtotalPaise': pricing.subtotalPaise,
          'discountPaise': pricing.discountPaise,
          'deliveryFeePaise': pricing.deliveryFeePaise,
          'totalPaise': pricing.totalPaise,
          'amountForFreeDeliveryPaise': pricing.amountForFreeDeliveryPaise,
        },
        'attempts': attempts,
        'startedAt': startedAt?.toIso8601String(),
        if (confirmedOrder != null)
          'confirmedOrder': _orderToJson(confirmedOrder!),
      };

  factory PendingOrderRecord.fromJson(Map<String, dynamic> json) {
    final pricingJson = json['pricing'];
    final key = json['key'];
    final attempts = json['attempts'];
    final rawStartedAt = json['startedAt'];
    if (json['version'] != 2 ||
        key is! String ||
        key.isEmpty ||
        attempts is! int ||
        attempts < 0 ||
        pricingJson is! Map<String, dynamic> ||
        (rawStartedAt != null && rawStartedAt is! String)) {
      throw const FormatException('Invalid pending order record');
    }

    final orderJson = json['confirmedOrder'];
    return PendingOrderRecord(
      key: key,
      cart: Cart.fromJson(json['cart'] as Map<String, dynamic>),
      pricing: CartPricing(
        subtotalPaise: _requiredInt(pricingJson, 'subtotalPaise'),
        discountPaise: _requiredInt(pricingJson, 'discountPaise'),
        deliveryFeePaise: _requiredInt(pricingJson, 'deliveryFeePaise'),
        totalPaise: _requiredInt(pricingJson, 'totalPaise'),
        amountForFreeDeliveryPaise:
            _requiredInt(pricingJson, 'amountForFreeDeliveryPaise'),
      ),
      attempts: attempts,
      startedAt:
          rawStartedAt == null ? null : DateTime.parse(rawStartedAt).toUtc(),
      confirmedOrder: orderJson == null
          ? null
          : Order.fromJson(orderJson as Map<String, dynamic>),
    );
  }
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw const FormatException('Invalid pending order record');
  }
  return value;
}

Map<String, dynamic> _orderToJson(Order order) => {
      'id': order.id,
      'status': switch (order.status) {
        OrderStatus.placed => 'placed',
        OrderStatus.packed => 'packed',
        OrderStatus.outForDelivery => 'out_for_delivery',
        OrderStatus.delivered => 'delivered',
        OrderStatus.unknown => 'unknown',
      },
      'createdAt': order.createdAt.toIso8601String(),
      'items': [
        for (final item in order.items)
          {
            'productId': item.productId,
            'name': item.name,
            'emoji': item.emoji,
            'quantity': item.quantity,
            'unitPricePaise': item.unitPricePaise,
          },
      ],
      'subtotalPaise': order.subtotalPaise,
      'discountPaise': order.discountPaise,
      'deliveryFeePaise': order.deliveryFeePaise,
      'totalPaise': order.totalPaise,
      'couponCode': order.couponCode,
    };
