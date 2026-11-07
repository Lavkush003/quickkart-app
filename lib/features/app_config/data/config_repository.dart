import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/providers.dart';
import '../../../core/storage/key_value_store.dart';
import '../domain/app_config.dart';

final configRepositoryProvider = Provider<ConfigRepository>(
  (ref) => ConfigRepository(
    ref.watch(apiClientProvider),
    ref.watch(keyValueStoreProvider),
    remoteUpdates: () => ref.read(mockServerProvider).configUpdates,
  ),
);

class ConfigRepository {
  ConfigRepository(
    this._client,
    this._store, {
    required Stream<int> Function() remoteUpdates,
  }) : _remoteUpdates = remoteUpdates;

  static const cachedConfigKey = 'app_config.cached.v1';

  final ApiClient _client;
  final KeyValueStore _store;
  final Stream<int> Function() _remoteUpdates;
  Future<AppConfig>? _refreshInFlight;

  /// Fires (with the new config version) every time config is published
  /// from the console. Equivalent to Firebase's `onConfigUpdated`.
  Stream<int> get remoteUpdates => _remoteUpdates();

  /// Fetches the latest config, falling back to the last valid cache or defaults.
  Future<AppConfig> load() async {
    try {
      return await loadFresh();
    } on ApiException {
      return loadCached();
    }
  }

  /// Loads locally persisted config without waiting for network access.
  Future<AppConfig> loadCached() async {
    final cached = await _store.getString(cachedConfigKey);
    if (cached == null) return AppConfig.defaults();

    try {
      final decoded = jsonDecode(cached);
      return AppConfig.fromValues(_validatedValues(decoded));
    } on FormatException {
      return AppConfig.defaults();
    } on TypeError {
      return AppConfig.defaults();
    } on ServerException {
      return AppConfig.defaults();
    }
  }

  /// Fetches config without a cached response or a success-shaped fallback.
  ///
  /// Checkout uses this to verify connectivity and the current store status.
  Future<AppConfig> loadFresh() async {
    final current = _refreshInFlight;
    if (current != null) return current;

    final refresh = _fetchAndCache();
    _refreshInFlight = refresh;
    try {
      return await refresh;
    } finally {
      if (identical(_refreshInFlight, refresh)) {
        _refreshInFlight = null;
      }
    }
  }

  Future<AppConfig> _fetchAndCache() async {
    try {
      final response = await _client.get('/v1/config', forceRefresh: true);
      if (response is! Map || !response.containsKey('values')) {
        throw _invalidConfigResponse();
      }
      final config = AppConfig.fromValues(_validatedValues(response['values']));
      await _store.setString(cachedConfigKey, jsonEncode(config.toJson()));
      return config;
    } on ApiException {
      rethrow;
    } on FormatException {
      throw _invalidConfigResponse();
    } on TypeError {
      throw _invalidConfigResponse();
    }
  }

  Map<String, Object?> _validatedValues(Object? rawValues) {
    if (rawValues is! Map || rawValues.keys.any((key) => key is! String)) {
      throw _invalidConfigResponse();
    }
    final values = Map<String, Object?>.from(rawValues);

    const stringKeys = {
      'min_supported_version',
      'latest_version',
      'update_url',
      'store_closed_message',
      'home_banner',
      'home_sections',
    };
    for (final key in stringKeys) {
      final isOptionalJsonString =
          (key == 'home_banner' || key == 'home_sections') &&
              values[key] == null;
      if (values.containsKey(key) &&
          values[key] is! String &&
          !isOptionalJsonString) {
        throw _invalidConfigResponse();
      }
    }

    if (values.containsKey('store_open')) {
      final storeOpen = values['store_open'];
      if (storeOpen is! bool &&
          (storeOpen is! String ||
              (storeOpen.toLowerCase() != 'true' &&
                  storeOpen.toLowerCase() != 'false'))) {
        throw _invalidConfigResponse();
      }
    }

    for (final key in {
      'delivery_fee_paise',
      'free_delivery_threshold_paise',
    }) {
      if (!values.containsKey(key)) continue;
      final value = values[key];
      final parsed = switch (value) {
        int number => number,
        num number when number == number.toInt() => number.toInt(),
        String text => int.tryParse(text),
        _ => null,
      };
      if (parsed == null || parsed < 0) throw _invalidConfigResponse();
    }
    return values;
  }

  ServerException _invalidConfigResponse() => const ServerException(
        502,
        'The server returned invalid store configuration. Please try again.',
      );
}
