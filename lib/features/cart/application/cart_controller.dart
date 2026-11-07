import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalog/domain/product.dart';
import '../data/cart_storage.dart';
import '../domain/cart.dart';
import '../domain/coupon.dart';

/// The cart. Hydrated from storage in `main.dart` before the first frame.
final cartControllerProvider =
    NotifierProvider<CartController, Cart>(CartController.new);

class CartController extends Notifier<Cart> {
  Future<void> _mutationQueue = Future<void>.value();

  CartStorage get _storage => ref.read(cartStorageProvider);

  @override
  Cart build() => const Cart.empty();

  /// Used at startup with the cart restored from storage.
  void hydrate(Cart cart) => state = cart;

  /// Adds one unit of [product].
  Future<void> add(Product product) => _updateCart((current) {
        final existing = current.lineFor(product.id);
        if (existing == null) {
          if (!product.inStock) return current;
          return current.upsertLine(CartLine.fromProduct(product));
        }
        if (existing.quantity >= existing.maxPerOrder) return current;
        return current.updateQuantity(product.id, existing.quantity + 1);
      });

  /// Adds one more unit of a product that is already in the cart.
  Future<void> increment(String productId) => _updateCart((current) {
        final line = current.lineFor(productId);
        if (line == null || line.quantity >= line.maxPerOrder) return current;
        return current.updateQuantity(productId, line.quantity + 1);
      });

  /// Removes one unit (and the line when it reaches zero).
  Future<void> decrement(String productId) => _updateCart((current) {
        final line = current.lineFor(productId);
        if (line == null) return current;
        return current.updateQuantity(productId, line.quantity - 1);
      });

  Future<void> remove(String productId) =>
      _updateCart((current) => current.removeLine(productId));

  Future<void> applyCoupon(Coupon coupon) =>
      _updateCart((current) => current.withCoupon(coupon));

  Future<void> removeCoupon() =>
      _updateCart((current) => current.withoutCoupon());

  /// Replaces the whole cart (e.g. after reconciliation).
  Future<void> replace(Cart cart) => _updateCart((_) => cart);

  Future<void> clear() =>
      _updateCart((_) => const Cart.empty(), clearStorage: true);

  Future<void> _updateCart(
    Cart Function(Cart current) update, {
    bool clearStorage = false,
  }) async {
    final previousMutation = _mutationQueue;
    final nextMutation = Completer<void>();
    _mutationQueue = nextMutation.future;
    try {
      await previousMutation;
      final updated = update(state);
      if (updated == state && !clearStorage) return;
      if (clearStorage) {
        await _storage.clear();
      } else {
        await _storage.save(updated);
      }
      state = updated;
    } finally {
      nextMutation.complete();
    }
  }
}
