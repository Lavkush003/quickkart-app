import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/domain/home_layout.dart';

void main() {
  group('HomeLayout.parse', () {
    test('preserves configured section order', () {
      expect(
        HomeLayout.parse('["deals","banner","all_products","categories"]'),
        [
          HomeSection.deals,
          HomeSection.banner,
          HomeSection.allProducts,
          HomeSection.categories,
        ],
      );
    });

    test('ignores unknown ids, non-string values, and duplicates', () {
      expect(
        HomeLayout.parse(
            '["banner","video","categories","banner",null,"all_products"]'),
        [
          HomeSection.banner,
          HomeSection.categories,
          HomeSection.allProducts,
        ],
      );
    });

    test('uses defaults for null or malformed input', () {
      expect(HomeLayout.parse(null), HomeLayout.defaultSections);
      expect(HomeLayout.parse('[banner,'), HomeLayout.defaultSections);
    });

    test('uses defaults for a non-array or no known sections', () {
      expect(HomeLayout.parse('{"sections":["banner"]}'),
          HomeLayout.defaultSections);
      expect(HomeLayout.parse('[]'), HomeLayout.defaultSections);
      expect(
          HomeLayout.parse('["unknown",null,42]'), HomeLayout.defaultSections);
    });
  });
}
