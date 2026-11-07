import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../data/config_repository.dart';
import '../domain/app_config.dart';

/// The config the app is currently using. Hydrated in `main.dart` before the
/// first frame.
final appConfigControllerProvider =
    NotifierProvider<AppConfigController, AppConfig>(AppConfigController.new);

class AppConfigController extends Notifier<AppConfig> {
  Future<void>? _refreshInFlight;
  bool _disposed = false;

  @override
  AppConfig build() {
    _disposed = false;
    final subscription =
        ref.read(configRepositoryProvider).remoteUpdates.listen((_) {
      unawaited(
        refresh().then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('Remote config refresh failed: $error');
          },
        ),
      );
    }, onError: (Object error, StackTrace stackTrace) {
      debugPrint('Remote config update stream failed: $error');
    });
    ref.onDispose(() {
      _disposed = true;
      unawaited(subscription.cancel());
    });
    return AppConfig.defaults();
  }

  /// Used at startup with the config loaded during bootstrap.
  void hydrate(AppConfig config) => state = config;

  Future<void> refresh() {
    final current = _refreshInFlight;
    if (current != null) return current;

    final refresh = _refresh();
    _refreshInFlight = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshInFlight, refresh)) {
        _refreshInFlight = null;
      }
    });
  }

  Future<void> _refresh() async {
    try {
      final config = await ref.read(configRepositoryProvider).loadFresh();
      if (!_disposed) state = config;
    } on ApiException catch (error) {
      debugPrint(
          'Remote config refresh failed; retaining current config: $error');
    }
  }
}
