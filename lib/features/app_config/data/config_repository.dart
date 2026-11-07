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

/// Loads remote config (think: Firebase Remote Config).
class ConfigRepository {
  ConfigRepository(
    this._client,
    this._store, {
    required Stream<int> Function() remoteUpdates,
  }) : _remoteUpdates = remoteUpdates;

  final ApiClient _client;
  // ignore: unused_field
  final KeyValueStore _store;
  final Stream<int> Function() _remoteUpdates;

  /// Fires (with the new config version) every time config is published
  /// from the console. Equivalent to Firebase's `onConfigUpdated`.
  Stream<int> get remoteUpdates => _remoteUpdates();

  /// Fetches the latest config.
  Future<AppConfig> load() async {
    try {
      final json = await _client.get('/v1/config') as Map<String, dynamic>;
      final values = (json['values'] as Map).cast<String, Object?>();
      return AppConfig.fromValues(values);
    } on ApiException {
      return AppConfig.defaults();
    }
  }

  /// Fetches config without a cached response or a success-shaped fallback.
  ///
  /// Checkout uses this to verify connectivity and the current store status.
  Future<AppConfig> loadFresh() async {
    try {
      final json = await _client.get('/v1/config', forceRefresh: true)
          as Map<String, dynamic>;
      final rawValues = json['values'];
      if (rawValues is! Map) throw _invalidConfigResponse();
      return AppConfig.fromValues(rawValues.cast<String, Object?>());
    } on ApiException {
      rethrow;
    } on TypeError {
      throw _invalidConfigResponse();
    } on FormatException {
      throw _invalidConfigResponse();
    }
  }

  ServerException _invalidConfigResponse() => const ServerException(
        502,
        'The server returned invalid store configuration. Please try again.',
      );
}
