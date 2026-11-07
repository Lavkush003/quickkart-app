import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/domain/update_policy.dart';

void main() {
  group('UpdatePolicy.evaluate', () {
    test('compares numeric segments instead of strings', () {
      expect(
        evaluate('1.9.0', '1.10.0', '2.0.0'),
        UpdateRequirement.required,
      );
      expect(
        evaluate('1.10.0', '1.9.0', '1.11.0'),
        UpdateRequirement.optional,
      );
      expect(
        evaluate('1.9999999999999999999', '2.0', '3.0'),
        UpdateRequirement.required,
      );
    });

    test('treats missing trailing segments as zero', () {
      expect(evaluate('1.4', '1.4.0', '1.4.0'), UpdateRequirement.none);
      expect(evaluate('1.3.9', '1.4', '1.5'), UpdateRequirement.required);
    });

    test('returns required, optional, or none according to the policy', () {
      expect(evaluate('1.2.0', '1.3.0', '1.5.0'), UpdateRequirement.required);
      expect(
        evaluate('1.4.0', '1.3.0', '1.5.0'),
        UpdateRequirement.optional,
      );
      expect(evaluate('1.5.0', '1.3.0', '1.5.0'), UpdateRequirement.none);
      expect(evaluate('1.6.0', '1.3.0', '1.5.0'), UpdateRequirement.none);
    });

    test('malformed current version fails open', () {
      for (final version in ['', '1..2', '1.beta', '-1.0', '1.2-', ' 1.2']) {
        expect(
          evaluate(version, '1.0.0', '2.0.0'),
          UpdateRequirement.none,
          reason: 'current version "$version" should not block the app',
        );
      }
    });

    test('malformed configuration versions fail open', () {
      for (final version in ['', '1..2', '1.beta', '-1.0']) {
        expect(
          evaluate('1.0.0', version, '2.0.0'),
          UpdateRequirement.none,
          reason: 'minimum version "$version" should not block the app',
        );
        expect(
          evaluate('1.0.0', '0.0.0', version),
          UpdateRequirement.none,
          reason: 'latest version "$version" should not block the app',
        );
      }
    });
  });
}

UpdateRequirement evaluate(
  String currentVersion,
  String minSupportedVersion,
  String latestVersion,
) {
  return UpdatePolicy.evaluate(
    currentVersion: currentVersion,
    minSupportedVersion: minSupportedVersion,
    latestVersion: latestVersion,
  );
}
