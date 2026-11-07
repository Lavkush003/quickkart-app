import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/providers.dart';
import '../../app_config/presentation/app_config_controller.dart';
import '../../cart/application/cart_controller.dart';
import '../../cart/domain/cart.dart';
import '../../cart/domain/cart_pricing.dart';
import '../../cart/domain/reconciliation.dart';
import '../../orders/data/order_tracking_repository.dart';
import '../data/order_api.dart';
import '../domain/order.dart';

/// Result of [CheckoutController.placeOrder].
sealed class CheckoutResult {
  const CheckoutResult();
}

/// The order was created. The cart has been cleared.
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

  Future<CheckoutResult>? _inFlight;

  @override
  CheckoutState build() => const CheckoutState();

  Future<CheckoutResult> placeOrder() {
    final activeRequest = _inFlight;
    if (activeRequest != null) return activeRequest;

    state = const CheckoutState(isPlacingOrder: true);
    final request = _placeOrder(retryOnTimeout: true).then(
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

  Future<CheckoutResult> _placeOrder({
    required bool retryOnTimeout,
    String? idempotencyKey,
  }) async {
    final cart = ref.read(cartControllerProvider);
    if (cart.isEmpty) {
      return const CheckoutFailure('Your cart is empty');
    }
    final pricing =
        CartPricing.compute(cart, ref.read(appConfigControllerProvider));
    final key = idempotencyKey ?? await _idempotencyKeyFor(cart, pricing);

    try {
      final order = await ref
          .read(orderApiProvider)
          .placeOrder(cart, pricing, idempotencyKey: key);
      await ref.read(cartControllerProvider.notifier).clear();
      await ref.read(keyValueStoreProvider).remove(_pendingOrderKey);
      ref.invalidate(ordersProvider);
      return CheckoutSuccess(order);
    } on ApiTimeoutException {
      if (retryOnTimeout) {
        return _placeOrder(
          retryOnTimeout: false,
          idempotencyKey: key,
        );
      }
      return const CheckoutFailure(
        'Your order may have been placed. Check My orders before trying again.',
        canRetry: true,
      );
    } on ApiException catch (e) {
      return CheckoutFailure(e.message, canRetry: e.isTransient);
    }
  }

  Future<String> _idempotencyKeyFor(
    Cart cart,
    CartPricing pricing,
  ) async {
    final items = [
      for (final line in cart.lines)
        {
          'productId': line.productId,
          'quantity': line.quantity,
          'unitPricePaise': line.unitPricePaise,
        },
    ];
    final fingerprint = jsonEncode({
      'items': items,
      'couponCode': cart.coupon?.code,
      'expectedTotalPaise': pricing.totalPaise,
    });
    final store = ref.read(keyValueStoreProvider);
    final pending = await store.getString(_pendingOrderKey);

    if (pending != null) {
      Object? decoded;
      try {
        decoded = jsonDecode(pending);
      } on FormatException {
        await store.remove(_pendingOrderKey);
      }
      if (decoded is Map<String, dynamic> &&
          decoded['fingerprint'] == fingerprint &&
          decoded['key'] is String &&
          (decoded['key'] as String).isNotEmpty) {
        return decoded['key'] as String;
      }
    }

    final key = const Uuid().v4();
    await store.setString(
      _pendingOrderKey,
      jsonEncode({'fingerprint': fingerprint, 'key': key}),
    );
    return key;
  }
}
