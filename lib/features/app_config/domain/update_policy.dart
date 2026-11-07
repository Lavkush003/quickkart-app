/// What the app must do about its own version.
enum UpdateRequirement {
  /// Nothing to do.
  none,

  /// A newer version exists; the user may update or dismiss.
  optional,

  /// This version is no longer supported; the app must be blocked until the
  /// user updates.
  required,
}

/// Decides whether the running app must / may be updated.
class UpdatePolicy {
  const UpdatePolicy._();

  static UpdateRequirement evaluate({
    required String currentVersion,
    required String minSupportedVersion,
    required String latestVersion,
  }) {
    final current = _parseVersion(currentVersion);
    final minimum = _parseVersion(minSupportedVersion);
    final latest = _parseVersion(latestVersion);
    if (current == null || minimum == null || latest == null) {
      return UpdateRequirement.none;
    }

    if (_compare(current, minimum) < 0) return UpdateRequirement.required;
    if (_compare(current, latest) < 0) return UpdateRequirement.optional;
    return UpdateRequirement.none;
  }

  static List<BigInt>? _parseVersion(String version) {
    if (!RegExp(r'^\d+(?:\.\d+)*$').hasMatch(version)) return null;

    final segments = <BigInt>[];
    for (final segment in version.split('.')) {
      final value = BigInt.tryParse(segment);
      if (value == null) return null;
      segments.add(value);
    }
    return segments;
  }

  static int _compare(List<BigInt> left, List<BigInt> right) {
    final length = left.length > right.length ? left.length : right.length;
    for (var index = 0; index < length; index++) {
      final leftSegment = index < left.length ? left[index] : BigInt.zero;
      final rightSegment = index < right.length ? right[index] : BigInt.zero;
      final comparison = leftSegment.compareTo(rightSegment);
      if (comparison != 0) return comparison;
    }
    return 0;
  }
}
