import 'dart:convert';

/// Strongly typed view of the remote config values.
///
/// Parsing is deliberately forgiving: a bad value falls back to the default
/// instead of throwing, because a typo in the config console must never
/// crash the app for every user.
class AppConfig {
  const AppConfig({
    required this.minSupportedVersion,
    required this.latestVersion,
    required this.updateUrl,
    required this.storeOpen,
    required this.storeClosedMessage,
    required this.homeBannerJson,
    required this.homeSectionsJson,
    required this.deliveryFeePaise,
    required this.freeDeliveryThresholdPaise,
  });

  /// Safe values used when nothing has ever been fetched.
  factory AppConfig.defaults() => const AppConfig(
        minSupportedVersion: '0.0.0',
        latestVersion: '0.0.0',
        updateUrl: '',
        storeOpen: true,
        storeClosedMessage: 'The store is closed right now.',
        homeBannerJson: null,
        homeSectionsJson: null,
        deliveryFeePaise: 2500,
        freeDeliveryThresholdPaise: 19900,
      );

  factory AppConfig.fromValues(Map<String, Object?> values) {
    final d = AppConfig.defaults();
    return AppConfig(
      minSupportedVersion:
          _string(values['min_supported_version']) ?? d.minSupportedVersion,
      latestVersion: _string(values['latest_version']) ?? d.latestVersion,
      updateUrl: _string(values['update_url']) ?? d.updateUrl,
      storeOpen: _bool(values['store_open']) ?? d.storeOpen,
      storeClosedMessage:
          _string(values['store_closed_message']) ?? d.storeClosedMessage,
      homeBannerJson: _string(values['home_banner']),
      homeSectionsJson: _string(values['home_sections']),
      deliveryFeePaise:
          _int(values['delivery_fee_paise']) ?? d.deliveryFeePaise,
      freeDeliveryThresholdPaise:
          _int(values['free_delivery_threshold_paise']) ??
              d.freeDeliveryThresholdPaise,
    );
  }

  final String minSupportedVersion;
  final String latestVersion;
  final String updateUrl;
  final bool storeOpen;
  final String storeClosedMessage;

  /// Raw JSON string, e.g. `{"title": "...", "subtitle": "...", "color": "#FF6F00"}`.
  final String? homeBannerJson;

  /// Raw JSON string, e.g. `["banner","categories","deals","all_products"]`.
  /// Parse it with `HomeLayout.parse`.
  final String? homeSectionsJson;

  final int deliveryFeePaise;
  final int freeDeliveryThresholdPaise;

  Map<String, Object?> toJson() => {
        'min_supported_version': minSupportedVersion,
        'latest_version': latestVersion,
        'update_url': updateUrl,
        'store_open': storeOpen,
        'store_closed_message': storeClosedMessage,
        'home_banner': homeBannerJson,
        'home_sections': homeSectionsJson,
        'delivery_fee_paise': deliveryFeePaise,
        'free_delivery_threshold_paise': freeDeliveryThresholdPaise,
      };

  /// Parsed banner, or null if missing / malformed.
  HomeBanner? get homeBanner {
    final raw = homeBannerJson;
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      final title = json['title'];
      if (title is! String || title.isEmpty) return null;
      return HomeBanner(
        title: title,
        subtitle: json['subtitle'] as String? ?? '',
        colorHex: json['color'] as String? ?? '#FF6F00',
      );
    } catch (_) {
      return null;
    }
  }

  static String? _string(Object? v) => v is String ? v : null;

  static bool? _bool(Object? v) {
    if (v is bool) return v;
    if (v is String) {
      if (v.toLowerCase() == 'true') return true;
      if (v.toLowerCase() == 'false') return false;
    }
    return null;
  }

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}

class HomeBanner {
  const HomeBanner({
    required this.title,
    required this.subtitle,
    required this.colorHex,
  });

  final String title;
  final String subtitle;
  final String colorHex;
}
