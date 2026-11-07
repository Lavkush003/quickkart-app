/// Money helpers.
///
/// Every amount inside the app is an integer number of **paise**
/// (1 rupee = 100 paise). Never store money in a `double`.
library;

/// Formats paise for display.
String formatMoney(int paise) {
  final absolutePaise = paise.abs();
  final rupees = absolutePaise ~/ 100;
  final remainingPaise = absolutePaise % 100;
  final sign = paise < 0 ? '-' : '';
  if (remainingPaise == 0) return '₹$sign$rupees';
  return '₹$sign$rupees.${remainingPaise.toString().padLeft(2, '0')}';
}

/// Converts a rupee amount coming from the (legacy) API into paise.
int rupeesToPaise(num rupees) => (rupees * 100).toInt();
