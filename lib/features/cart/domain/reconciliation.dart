import 'cart.dart';
import 'coupon.dart';

/// A difference between the user's local cart and the server's current
/// state, detected by `CartReconciler`.
sealed class CartChange {
  const CartChange();

  /// Whether the user must see and accept this change before an order can
  /// be placed (BUSINESS_RULES.md).
  bool get requiresUserReview;
}

class PriceChanged extends CartChange {
  const PriceChanged({
    required this.productId,
    required this.oldPricePaise,
    required this.newPricePaise,
    this.productName,
  });

  final String productId;
  final String? productName;
  final int oldPricePaise;
  final int newPricePaise;

  bool get isIncrease => newPricePaise > oldPricePaise;

  /// Price drops may be applied silently; increases must be reviewed.
  @override
  bool get requiresUserReview => isIncrease;

  @override
  String toString() =>
      'PriceChanged($productId, $oldPricePaise -> $newPricePaise)';
}

/// The product exists but has zero stock right now.
class OutOfStock extends CartChange {
  const OutOfStock({required this.productId, this.productName});

  final String productId;
  final String? productName;

  @override
  bool get requiresUserReview => true;

  @override
  String toString() => 'OutOfStock($productId)';
}

/// The requested quantity is more than stock or the per-order limit.
class QuantityReduced extends CartChange {
  const QuantityReduced({
    required this.productId,
    required this.requestedQuantity,
    required this.availableQuantity,
    this.productName,
  });

  final String productId;
  final String? productName;
  final int requestedQuantity;
  final int availableQuantity;

  @override
  bool get requiresUserReview => true;

  @override
  String toString() =>
      'QuantityReduced($productId, $requestedQuantity -> $availableQuantity)';
}

/// The product is no longer sold (reported as `missing` by the API).
class ProductUnavailable extends CartChange {
  const ProductUnavailable({required this.productId, this.productName});

  final String productId;
  final String? productName;

  @override
  bool get requiresUserReview => true;

  @override
  String toString() => 'ProductUnavailable($productId)';
}

/// The applied coupon can no longer be used.
class CouponRemoved extends CartChange {
  const CouponRemoved({required this.code, required this.reason});

  final String code;

  /// `EXPIRED` or `NOT_FOUND`.
  final String reason;

  @override
  bool get requiresUserReview => true;

  @override
  String toString() => 'CouponRemoved($code, $reason)';
}

class CouponChanged extends CartChange {
  const CouponChanged({required this.previous, required this.latest});

  final Coupon previous;
  final Coupon latest;

  String get code => previous.code;

  @override
  bool get requiresUserReview => true;

  @override
  String toString() => 'CouponChanged($code)';
}

class ReconciliationResult {
  const ReconciliationResult({required this.cart, required this.changes});

  /// The cart as it can be ordered *right now* (see the contract on
  /// `CartReconciler.reconcile`).
  final Cart cart;

  /// Every difference that was detected, in no particular order.
  final List<CartChange> changes;

  bool get hasChanges => changes.isNotEmpty;

  bool get requiresUserReview => changes.any((c) => c.requiresUserReview);
}
