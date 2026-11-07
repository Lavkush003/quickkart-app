import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../../catalog/data/catalog_api.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/domain/product.dart';
import '../data/coupon_api.dart';
import '../domain/cart.dart';
import '../domain/coupon.dart';
import '../domain/reconciliation.dart';

final cartReconcilerProvider = Provider<CartReconciler>(
  (ref) => CartReconciler(
    catalogApi: ref.watch(catalogApiProvider),
    couponApi: ref.watch(couponApiProvider),
  ),
);

/// Compares a local cart with the server's current state.
class CartReconciler {
  CartReconciler({required this.catalogApi, required this.couponApi});

  final CatalogApi catalogApi;
  final CouponApi couponApi;

  Future<ReconciliationResult> reconcile(Cart cart) async {
    if (cart.isEmpty && cart.coupon == null) {
      return ReconciliationResult(cart: cart, changes: const []);
    }

    final productIds =
        cart.lines.map((line) => line.productId).toSet().toList();
    final products = <String, Product>{};
    final missingIds = <String>{};

    for (var start = 0; start < productIds.length; start += 50) {
      final end = (start + 50).clamp(0, productIds.length);
      final requested = productIds.sublist(start, end);
      final ProductBatch batch;
      try {
        batch = await catalogApi.getProductsByIds(requested);
      } on ApiException {
        rethrow;
      } on FormatException {
        throw _invalidServerResponse();
      } on TypeError {
        throw _invalidServerResponse();
      }

      _validateBatch(batch, requested, products, missingIds);
    }

    final changes = <CartChange>[];
    final updatedLines = <CartLine>[];
    for (final line in cart.lines) {
      if (missingIds.contains(line.productId)) {
        changes.add(ProductUnavailable(
          productId: line.productId,
          productName: line.name,
        ));
        continue;
      }

      final product = products[line.productId];
      if (product == null) throw _invalidServerResponse();

      if (line.unitPricePaise != product.pricePaise) {
        changes.add(PriceChanged(
          productId: line.productId,
          productName: line.name,
          oldPricePaise: line.unitPricePaise,
          newPricePaise: product.pricePaise,
        ));
      }

      final available = product.purchasableQuantity;
      if (available <= 0) {
        changes.add(OutOfStock(
          productId: line.productId,
          productName: line.name,
        ));
        continue;
      }

      final quantity = line.quantity > available ? available : line.quantity;
      if (quantity != line.quantity) {
        changes.add(QuantityReduced(
          productId: line.productId,
          productName: line.name,
          requestedQuantity: line.quantity,
          availableQuantity: available,
        ));
      }
      updatedLines.add(line.copyWith(
        unitPricePaise: product.pricePaise,
        quantity: quantity,
        maxPerOrder: available,
      ));
    }

    Coupon? updatedCoupon;
    final coupon = cart.coupon;
    if (coupon != null) {
      updatedCoupon = await _refreshCoupon(coupon, changes);
    }

    return ReconciliationResult(
      cart: Cart(lines: updatedLines, coupon: updatedCoupon),
      changes: List.unmodifiable(changes),
    );
  }

  void _validateBatch(
    ProductBatch batch,
    List<String> requested,
    Map<String, Product> products,
    Set<String> missingIds,
  ) {
    final requestedIds = requested.toSet();
    for (final product in batch.products) {
      if (!requestedIds.contains(product.id) ||
          products.containsKey(product.id) ||
          missingIds.contains(product.id) ||
          product.pricePaise < 0 ||
          product.stock < 0 ||
          product.maxPerOrder <= 0 ||
          product.mrpPaise < 0) {
        throw _invalidServerResponse();
      }
      products[product.id] = product;
    }

    for (final id in batch.missingIds) {
      if (!requestedIds.contains(id) ||
          products.containsKey(id) ||
          !missingIds.add(id)) {
        throw _invalidServerResponse();
      }
    }

    for (final id in requested) {
      if (!products.containsKey(id) && !missingIds.contains(id)) {
        throw _invalidServerResponse();
      }
    }
  }

  Future<Coupon?> _refreshCoupon(
    Coupon coupon,
    List<CartChange> changes,
  ) async {
    final Coupon latest;
    try {
      latest = await couponApi.validate(coupon.code);
    } on ClientException catch (error) {
      final reason = switch (error.code) {
        'COUPON_EXPIRED' => 'EXPIRED',
        'COUPON_NOT_FOUND' => 'NOT_FOUND',
        _ => null,
      };
      if (reason == null) rethrow;
      changes.add(CouponRemoved(code: coupon.code, reason: reason));
      return null;
    } on ApiException {
      rethrow;
    } on FormatException {
      throw _invalidServerResponse();
    } on TypeError {
      throw _invalidServerResponse();
    }

    if (latest.code.toUpperCase() != coupon.code.toUpperCase()) {
      throw _invalidServerResponse();
    }
    if (latest.value < 0 ||
        latest.minOrderPaise < 0 ||
        (latest.maxDiscountPaise != null && latest.maxDiscountPaise! < 0)) {
      throw _invalidServerResponse();
    }
    if (latest.isExpired(DateTime.now())) {
      changes.add(CouponRemoved(code: coupon.code, reason: 'EXPIRED'));
      return null;
    }
    if (latest != coupon) {
      changes.add(CouponChanged(previous: coupon, latest: latest));
    }
    return latest;
  }

  ServerException _invalidServerResponse() => const ServerException(
        502,
        'The server returned invalid cart data. Please try again later.',
      );
}
