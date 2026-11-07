/// A coupon as returned by `POST /v1/coupons/validate`.
class Coupon {
  const Coupon({
    required this.code,
    required this.type,
    required this.value,
    required this.minOrderPaise,
    required this.expiresAt,
    this.maxDiscountPaise,
    this.description = '',
  });

  factory Coupon.fromJson(Map<String, dynamic> json) => Coupon(
        code: json['code'] as String,
        type: json['type'] == 'percent' ? CouponType.percent : CouponType.flat,
        value: (json['value'] as num).toInt(),
        maxDiscountPaise: (json['maxDiscountPaise'] as num?)?.toInt(),
        minOrderPaise: (json['minOrderPaise'] as num?)?.toInt() ?? 0,
        expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
        description: json['description'] as String? ?? '',
      );

  final String code;
  final CouponType type;

  /// Paise for [CouponType.flat], percentage for [CouponType.percent].
  final int value;
  final int? maxDiscountPaise;
  final int minOrderPaise;
  final DateTime expiresAt;
  final String description;

  bool isExpired(DateTime now) => !expiresAt.isAfter(now.toUtc());

  /// Discount for a given subtotal (0 if the minimum order is not met).
  int discountFor(int subtotalPaise) {
    if (subtotalPaise < minOrderPaise) return 0;
    switch (type) {
      case CouponType.flat:
        return value < subtotalPaise ? value : subtotalPaise;
      case CouponType.percent:
        final raw = subtotalPaise * value ~/ 100;
        final cap = maxDiscountPaise;
        return cap != null && raw > cap ? cap : raw;
    }
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'type': type == CouponType.percent ? 'percent' : 'flat',
        'value': value,
        'maxDiscountPaise': maxDiscountPaise,
        'minOrderPaise': minOrderPaise,
        'expiresAt': expiresAt.toIso8601String(),
        'description': description,
      };

  @override
  bool operator ==(Object other) =>
      other is Coupon &&
      other.code == code &&
      other.type == type &&
      other.value == value &&
      other.maxDiscountPaise == maxDiscountPaise &&
      other.minOrderPaise == minOrderPaise &&
      other.expiresAt == expiresAt &&
      other.description == description;

  @override
  int get hashCode => Object.hash(code, type, value, maxDiscountPaise,
      minOrderPaise, expiresAt, description);
}

enum CouponType { flat, percent }
