import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/utils/money.dart';

void main() {
  test('formats paise when a displayed amount has a fractional rupee', () {
    expect(formatMoney(1999), '₹19.99');
    expect(formatMoney(5000), '₹50');
  });
}
