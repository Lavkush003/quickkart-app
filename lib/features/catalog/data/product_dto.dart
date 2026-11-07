import '../../../core/utils/money.dart';
import '../domain/product.dart';

/// Maps the API representation of a product (see API_CONTRACT.md) to the
/// domain [Product].
class ProductDto {
  const ProductDto._();

  static Product fromJson(Map<String, dynamic> json) {
    final price = json['price'] as num;
    final mrp = json['mrp'] as num? ?? price;
    return Product(
      id: json['id'] as String,
      name: json['name'] as String,
      categoryId: json['categoryId'] as String,
      emoji: json['emoji'] as String? ?? '🛒',
      unit: json['unit'] as String? ?? '',
      pricePaise: rupeesToPaise(price),
      mrpPaise: rupeesToPaise(mrp),
      stock: _integer(json['stock'], 'stock'),
      maxPerOrder: json['maxPerOrder'] as int? ?? 10,
    );
  }

  static List<Product> listFromJson(Object? json) =>
      (json as List).map((e) => fromJson(e as Map<String, dynamic>)).toList();

  static int _integer(Object? value, String field) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw FormatException('Invalid product $field: $value');
  }
}
