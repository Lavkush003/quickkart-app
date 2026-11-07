import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/providers.dart';
import '../../app_config/data/config_repository.dart';
import '../../app_config/domain/app_config.dart';
import '../../app_config/presentation/app_config_controller.dart';
import '../../cart/application/cart_controller.dart';
import '../../cart/application/cart_reconciler.dart';
import '../../cart/domain/cart.dart';
import '../../cart/domain/cart_pricing.dart';
import '../../cart/domain/reconciliation.dart';
import '../../orders/data/order_tracking_repository.dart';
import '../data/order_api.dart';
import '../data/pending_order_record.dart';
import '../domain/order.dart';

/// Result of [CheckoutController.placeOrder].
sealed class CheckoutResult {
  const CheckoutResult();
}

/// The order was created and its purchased quantities have been removed.
class CheckoutSuccess extends CheckoutResult {
  const CheckoutSuccess(this.order);

  final Order order;
}

/// The cart changed on the server; the user must review it before trying
/// again. The cart in [CartController] has already been updated to
/// `reconciliation.cart`.
class CheckoutNeedsReview extends CheckoutResult {
  const CheckoutNeedsReview(this.reconciliation);

  final ReconciliationResult reconciliation;
}

/// The order was not placed.
class CheckoutFailure extends CheckoutResult {
  const CheckoutFailure(this.message, {this.canRetry = false});

  final String message;
  final bool canRetry;
}

/// The request may have created an order, but its final status is not known.
class CheckoutUnknown extends CheckoutResult {
  const CheckoutUnknown(this.message);

  final String message;
}

class CheckoutState {
  const CheckoutState({this.isPlacingOrder = false, this.lastResult});

  final bool isPlacingOrder;
  final CheckoutResult? lastResult;
}

final checkoutControllerProvider =
    NotifierProvider<CheckoutController, CheckoutState>(
  CheckoutController.new,
);

class CheckoutController extends Notifier<CheckoutState> {
  static const _pendingOrderKey = 'checkout.pending_order.v1';
  static const _pendingReviewCartKey = 'checkout.pending_review_cart.v1';
  static const _automaticRetryCount = 1;

  Future<CheckoutResult>? _inFlight;
  ReconciliationResult? _pendingReview;
  bool _reviewAccepted = false;

  @override
  CheckoutState build() => const CheckoutState();

  Future<CheckoutResult> placeOrder() {
    final activeRequest = _inFlight;
    if (activeRequest != null) return activeRequest;

    state = const CheckoutState(isPlacingOrder: true);
    final request = _placeOrder().then(
      (result) {
        state = CheckoutState(lastResult: result);
        return result;
      },
      onError: (Object error, StackTrace stackTrace) {
        state = const CheckoutState();
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _inFlight = request;
    return request.whenComplete(() => _inFlight = null);
  }

  /// Confirms the changes returned by the latest [CheckoutNeedsReview].
  Future<void> acceptChanges() async {
    if (_pendingReview == null) return;
    await ref.read(keyValueStoreProvider).remove(_pendingReviewCartKey);
    _reviewAccepted = true;
  }

  Future<CheckoutResult> _placeOrder() async {
    final store = ref.read(keyValueStoreProvider);
    final pendingReview = _pendingReview;
    if (pendingReview != null && !_reviewAccepted) {
      return CheckoutNeedsReview(pendingReview);
    }

    final cartController = ref.read(cartControllerProvider.notifier);
    final currentCart = ref.read(cartControllerProvider);
    final PendingOrderRecord? pendingOrder;
    try {
      pendingOrder = await _loadPendingOrder(currentCart);
    } on _InvalidPendingOrder {
      return const CheckoutUnknown(
        'We could not safely read the saved order attempt. Its status is '
        'unknown; do not place another order.',
      );
    }

    final confirmedOrder = pendingOrder?.confirmedOrder;
    if (pendingOrder != null && confirmedOrder != null) {
      return _completeOrder(pendingOrder, confirmedOrder);
    }

    final AppConfig config;
    try {
      config = await ref.read(configRepositoryProvider).loadFresh();
    } on ApiException catch (error) {
      if (pendingOrder != null) {
        return _resolvePendingAfterUncertainty(
          pendingOrder,
          'We could not verify whether your earlier order was placed. '
          'Its status is unknown. ${error.message}',
        );
      }
      return _preflightFailure(error);
    }
    ref.read(appConfigControllerProvider.notifier).hydrate(config);

    if (pendingOrder != null) {
      if (!config.storeOpen) {
        if (pendingOrder.attempts == 0) {
          await store.remove(_pendingOrderKey);
          return CheckoutFailure(config.storeClosedMessage);
        }
        return _resolvePendingAfterUncertainty(
          pendingOrder,
          '${config.storeClosedMessage} We could not verify your earlier '
          'order, so its status is unknown. Try checking again when the '
          'store reopens.',
        );
      }
      return _submitPendingOrder(pendingOrder);
    }

    if (!config.storeOpen) {
      return CheckoutFailure(config.storeClosedMessage);
    }

    if (pendingReview == null) {
      final savedReviewCart = await store.getString(_pendingReviewCartKey);
      if (savedReviewCart != null) {
        final Cart originalCart;
        try {
          final json = jsonDecode(savedReviewCart);
          if (json is! Map<String, dynamic>) throw const _InvalidPendingOrder();
          originalCart = Cart.fromJson(json);
        } on FormatException {
          return const CheckoutFailure(
            'Your saved cart review is invalid. Please rebuild your cart.',
          );
        } on TypeError {
          return const CheckoutFailure(
            'Your saved cart review is invalid. Please rebuild your cart.',
          );
        } on _InvalidPendingOrder {
          return const CheckoutFailure(
            'Your saved cart review is invalid. Please rebuild your cart.',
          );
        }

        final ReconciliationResult restoredReview;
        try {
          restoredReview = await _reconcile(originalCart);
        } on ApiException catch (error) {
          return CheckoutFailure(
            'Could not verify your cart with the store. ${error.message}',
            canRetry: error.isTransient,
          );
        }
        if (restoredReview.requiresUserReview) {
          if (ref.read(cartControllerProvider) != currentCart) {
            return const CheckoutFailure(
              'Your cart changed while it was being checked. Review the '
              'current cart and try again.',
              canRetry: true,
            );
          }
          await cartController.replace(restoredReview.cart);
          _pendingReview = restoredReview;
          _reviewAccepted = false;
          return CheckoutNeedsReview(restoredReview);
        }

        await store.remove(_pendingReviewCartKey);
        if (restoredReview.cart != currentCart) {
          await cartController.replace(restoredReview.cart);
        }
      }
    }

    var cart = ref.read(cartControllerProvider);
    if (cart.isEmpty) return const CheckoutFailure('Your cart is empty.');

    final ReconciliationResult reconciliation;
    try {
      reconciliation = await _reconcile(cart);
    } on ApiException catch (error) {
      return CheckoutFailure(
        'Could not verify your cart with the store. ${error.message}',
        canRetry: error.isTransient,
      );
    }
    if (ref.read(cartControllerProvider) != cart) {
      return const CheckoutFailure(
        'Your cart changed while it was being checked. Review the current '
        'cart and try again.',
        canRetry: true,
      );
    }
    if (reconciliation.hasChanges) {
      if (reconciliation.requiresUserReview) {
        await store.setString(
          _pendingReviewCartKey,
          jsonEncode(cart.toJson()),
        );
        if (ref.read(cartControllerProvider) != cart) {
          await store.remove(_pendingReviewCartKey);
          return const CheckoutFailure(
            'Your cart changed while it was being checked. Review the current '
            'cart and try again.',
            canRetry: true,
          );
        }
        await cartController.replace(reconciliation.cart);
        _pendingReview = reconciliation;
        _reviewAccepted = false;
        return CheckoutNeedsReview(reconciliation);
      }
      await cartController.replace(reconciliation.cart);
      cart = reconciliation.cart;
    }

    final validationError = _validateFinalCart(cart);
    if (validationError != null) {
      return CheckoutFailure(validationError);
    }

    final orderCart = _cartForOrder(cart);
    final pricing = CartPricing.compute(orderCart, config);
    final pending = PendingOrderRecord(
      key: const Uuid().v4(),
      cart: orderCart,
      pricing: pricing,
      attempts: 0,
      startedAt: DateTime.now().toUtc(),
    );
    await store.setString(_pendingOrderKey, jsonEncode(pending.toJson()));
    _pendingReview = null;
    _reviewAccepted = false;
    return _submitPendingOrder(pending);
  }

  Cart _cartForOrder(Cart cart) {
    final coupon = cart.coupon;
    if (coupon != null && cart.subtotalPaise < coupon.minOrderPaise) {
      return Cart(lines: cart.lines);
    }
    return cart;
  }

  Future<ReconciliationResult> _reconcile(Cart cart) =>
      ref.read(cartReconcilerProvider).reconcile(cart);

  CheckoutFailure _preflightFailure(ApiException error) {
    if (error is NetworkException) {
      return const CheckoutFailure(
        'No internet connection. Check your connection and try again.',
        canRetry: true,
      );
    }
    if (error is ApiTimeoutException) {
      return const CheckoutFailure(
        'The store check timed out. No order was placed. Please try again.',
        canRetry: true,
      );
    }
    return CheckoutFailure(
      'Could not verify the store before checkout. ${error.message}',
      canRetry: error.isTransient,
    );
  }

  String? _validateFinalCart(Cart cart) {
    final productIds = <String>{};
    for (final line in cart.lines) {
      if (!productIds.add(line.productId)) {
        return 'Your cart contains duplicate products. Please review it.';
      }
      if (line.quantity <= 0 ||
          line.unitPricePaise < 0 ||
          line.maxPerOrder <= 0 ||
          line.quantity > line.maxPerOrder) {
        return 'Your cart has invalid quantities or prices. Please review it.';
      }
    }
    return null;
  }

  Future<PendingOrderRecord?> _loadPendingOrder(Cart currentCart) async {
    final store = ref.read(keyValueStoreProvider);
    final raw = await store.getString(_pendingOrderKey);
    if (raw == null) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) throw const _InvalidPendingOrder();
      if (decoded['cart'] is Map && decoded['pricing'] is Map) {
        final pending = PendingOrderRecord.fromJson(decoded);
        final pricing = pending.pricing;
        if (pending.cart.isEmpty ||
            _validateFinalCart(pending.cart) != null ||
            pricing.subtotalPaise < 0 ||
            pricing.discountPaise < 0 ||
            pricing.deliveryFeePaise < 0 ||
            pricing.totalPaise < 0 ||
            pricing.amountForFreeDeliveryPaise < 0) {
          throw const _InvalidPendingOrder();
        }
        return pending;
      }
      return _restoreLegacyPendingOrder(decoded, currentCart);
    } on FormatException {
      throw const _InvalidPendingOrder();
    } on TypeError {
      throw const _InvalidPendingOrder();
    } on RangeError {
      throw const _InvalidPendingOrder();
    }
  }

  PendingOrderRecord _restoreLegacyPendingOrder(
    Map<String, dynamic> decoded,
    Cart currentCart,
  ) {
    final key = decoded['key'];
    final fingerprint = decoded['fingerprint'];
    if (key is! String || key.isEmpty || fingerprint is! String) {
      throw const _InvalidPendingOrder();
    }
    final data = jsonDecode(fingerprint);
    if (data is! Map<String, dynamic> ||
        data['items'] is! List ||
        data['expectedTotalPaise'] is! int ||
        data['couponCode'] != currentCart.coupon?.code) {
      throw const _InvalidPendingOrder();
    }
    final items = data['items'] as List;
    if (items.length != currentCart.lines.length) {
      throw const _InvalidPendingOrder();
    }
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final line = currentCart.lines[index];
      if (item is! Map<String, dynamic> ||
          item['productId'] != line.productId ||
          item['quantity'] != line.quantity ||
          item['unitPricePaise'] != line.unitPricePaise) {
        throw const _InvalidPendingOrder();
      }
    }
    final expectedTotal = data['expectedTotalPaise'] as int;
    final pricing = CartPricing(
      subtotalPaise: currentCart.subtotalPaise,
      discountPaise: 0,
      deliveryFeePaise: 0,
      totalPaise: expectedTotal,
      amountForFreeDeliveryPaise: 0,
    );
    return PendingOrderRecord(
      key: key,
      cart: currentCart,
      pricing: pricing,
      attempts: 1,
      startedAt: null,
    );
  }

  Future<CheckoutResult> _submitPendingOrder(
    PendingOrderRecord pending,
  ) async {
    final attemptsThisCall = 1 + _automaticRetryCount;
    var operation = pending;
    for (var attempt = 0; attempt < attemptsThisCall; attempt++) {
      if (attempt > 0) {
        final AppConfig config;
        try {
          config = await ref.read(configRepositoryProvider).loadFresh();
        } on ApiException catch (error) {
          return _resolvePendingAfterUncertainty(
            operation,
            'We could not verify whether your order was placed. '
            'Its status is unknown. ${error.message}',
          );
        }
        ref.read(appConfigControllerProvider.notifier).hydrate(config);
        if (!config.storeOpen) {
          return _resolvePendingAfterUncertainty(
            operation,
            '${config.storeClosedMessage} The earlier order status is still '
            'unknown. Check again when the store reopens.',
          );
        }
      }

      operation = operation.withAttempts(operation.attempts + 1);
      await ref
          .read(keyValueStoreProvider)
          .setString(_pendingOrderKey, jsonEncode(operation.toJson()));
      try {
        final order = await ref.read(orderApiProvider).placeOrder(
              operation.cart,
              operation.pricing,
              idempotencyKey: operation.key,
            );
        return await _completeOrder(operation, order);
      } on NetworkException {
        if (attempt + 1 < attemptsThisCall) continue;
        return _unknownOrderResult(
          'The connection was lost while placing the order.',
        );
      } on ApiTimeoutException {
        if (attempt + 1 < attemptsThisCall) continue;
        return _unknownOrderResult('The order request timed out.');
      } on ServerException catch (error) {
        if (error.code == 'STORE_CLOSED') {
          if (operation.attempts == 1) {
            await ref.read(keyValueStoreProvider).remove(_pendingOrderKey);
            return CheckoutFailure(error.message);
          }
          return _resolvePendingAfterUncertainty(
            operation,
            '${error.message} The earlier order status is unknown.',
          );
        }
        if (attempt + 1 < attemptsThisCall) continue;
        return _unknownOrderResult(
          'The server could not confirm the order response.',
        );
      } on ClientException catch (error) {
        if (error.code == 'IDEMPOTENCY_KEY_REUSED') {
          return _unknownOrderResult(
            'The server rejected the saved request key.',
          );
        }
        await ref.read(keyValueStoreProvider).remove(_pendingOrderKey);
        return _handleRejectedOrder(operation.cart, error);
      } on FormatException {
        return _unknownOrderResult(
          'The order response was invalid.',
        );
      } on TypeError {
        return _unknownOrderResult(
          'The order response was invalid.',
        );
      }
    }
    return _unknownOrderResult('The order response was not received.');
  }

  Future<CheckoutResult> _resolvePendingAfterUncertainty(
    PendingOrderRecord pending,
    String message,
  ) async {
    if (pending.attempts == 0 || pending.startedAt == null) {
      return CheckoutUnknown(message);
    }

    try {
      final orders = await ref.read(orderApiProvider).getOrders();
      final matches = orders
          .where((order) => _matchesPendingOrder(order, pending))
          .toList();
      if (matches.length == 1) {
        return await _completeOrder(pending, matches.single);
      }
      if (matches.length > 1) {
        return const CheckoutUnknown(
          'More than one recent order matches this checkout. Its status '
          'cannot be confirmed safely; do not place another order.',
        );
      }
    } on ApiException catch (error) {
      return CheckoutUnknown('$message Order lookup failed: ${error.message}');
    } on FormatException {
      return CheckoutUnknown(
        '$message The order history response could not be verified.',
      );
    } on TypeError {
      return CheckoutUnknown(
        '$message The order history response could not be verified.',
      );
    }
    return CheckoutUnknown(message);
  }

  // The API has no lookup by idempotency key; only an exact, unique order
  // created after this persisted attempt can resolve it from order history.
  bool _matchesPendingOrder(Order order, PendingOrderRecord pending) {
    final startedAt = pending.startedAt;
    if (startedAt == null || order.createdAt.isBefore(startedAt)) return false;
    if (order.totalPaise != pending.pricing.totalPaise ||
        order.couponCode?.toUpperCase() !=
            pending.cart.coupon?.code.toUpperCase() ||
        order.items.length != pending.cart.lines.length) {
      return false;
    }
    for (var index = 0; index < order.items.length; index++) {
      final item = order.items[index];
      final line = pending.cart.lines[index];
      if (item.productId != line.productId ||
          item.quantity != line.quantity ||
          item.unitPricePaise != line.unitPricePaise) {
        return false;
      }
    }
    return true;
  }

  CheckoutUnknown _unknownOrderResult(String reason) => CheckoutUnknown(
        '$reason We could not confirm whether your order was placed. Its '
        'status is unknown. Do not start a new order; tap Check order status '
        'to safely retry the same request.',
      );

  Future<CheckoutResult> _handleRejectedOrder(
    Cart attemptedCart,
    ClientException error,
  ) async {
    const conflictCodes = {
      'PRODUCT_UNAVAILABLE',
      'PRICE_CHANGED',
      'QUANTITY_LIMIT',
      'INSUFFICIENT_STOCK',
      'COUPON_INVALID',
      'TOTAL_MISMATCH',
    };
    if (!conflictCodes.contains(error.code)) {
      return CheckoutFailure(error.message);
    }

    final ReconciliationResult reconciliation;
    try {
      reconciliation = await _reconcile(attemptedCart);
    } on ApiException catch (reconcileError) {
      return CheckoutFailure(
        '${error.message} Could not refresh the cart: ${reconcileError.message}',
        canRetry: reconcileError.isTransient,
      );
    }
    if (ref.read(cartControllerProvider) != attemptedCart) {
      return const CheckoutFailure(
        'Your cart changed while the order was being checked. Review the '
        'current cart and try again.',
        canRetry: true,
      );
    }
    if (reconciliation.requiresUserReview) {
      await ref.read(keyValueStoreProvider).setString(
            _pendingReviewCartKey,
            jsonEncode(attemptedCart.toJson()),
          );
      if (ref.read(cartControllerProvider) != attemptedCart) {
        await ref.read(keyValueStoreProvider).remove(_pendingReviewCartKey);
        return const CheckoutFailure(
          'Your cart changed while the order was being checked. Review the '
          'current cart and try again.',
          canRetry: true,
        );
      }
      await ref
          .read(cartControllerProvider.notifier)
          .replace(reconciliation.cart);
      _pendingReview = reconciliation;
      _reviewAccepted = false;
      return CheckoutNeedsReview(reconciliation);
    }
    if (reconciliation.hasChanges) {
      await ref
          .read(cartControllerProvider.notifier)
          .replace(reconciliation.cart);
    }
    return CheckoutFailure(error.message);
  }

  Future<CheckoutResult> _completeOrder(
    PendingOrderRecord pending,
    Order order,
  ) async {
    final store = ref.read(keyValueStoreProvider);
    await store.setString(
      _pendingOrderKey,
      jsonEncode(pending.withConfirmedOrder(order).toJson()),
    );

    final cartController = ref.read(cartControllerProvider.notifier);
    final currentCart = ref.read(cartControllerProvider);
    final remainingCart = _remainingCartAfterOrder(currentCart, pending.cart);
    if (remainingCart.isEmpty) {
      await cartController.clear();
    } else {
      await cartController.replace(remainingCart);
    }
    await store.remove(_pendingOrderKey);
    _pendingReview = null;
    _reviewAccepted = false;
    ref.invalidate(ordersProvider);
    return CheckoutSuccess(order);
  }

  Cart _remainingCartAfterOrder(Cart current, Cart ordered) {
    if (current == ordered) return const Cart.empty();
    final orderedQuantities = {
      for (final line in ordered.lines) line.productId: line.quantity,
    };
    final remainingLines = <CartLine>[];
    for (final line in current.lines) {
      final remaining =
          line.quantity - (orderedQuantities[line.productId] ?? 0);
      if (remaining > 0) {
        remainingLines.add(line.copyWith(quantity: remaining));
      }
    }
    return Cart(
      lines: remainingLines,
      coupon: remainingLines.isEmpty ? null : current.coupon,
    );
  }
}

class _InvalidPendingOrder implements Exception {
  const _InvalidPendingOrder();
}
