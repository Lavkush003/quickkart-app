import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/providers.dart';
import 'core/storage/key_value_store.dart';
import 'features/app_config/data/config_repository.dart';
import 'features/app_config/presentation/app_config_controller.dart';
import 'features/cart/application/cart_controller.dart';
import 'features/cart/data/cart_storage.dart';
import 'mock_server/mock_server.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final store = SharedPrefsKeyValueStore(prefs);

  // The "backend". Its data is persisted on the device.
  final server = await MockServer.open(store);

  final versionOverride = await store.getString(kDebugAppVersionKey);

  final container = ProviderContainer(
    overrides: [
      keyValueStoreProvider.overrideWithValue(store),
      mockServerProvider.overrideWithValue(server),
      if (versionOverride != null && versionOverride.isNotEmpty)
        appVersionProvider.overrideWithValue(versionOverride),
    ],
  );

  // Restore local state before the first frame; network config refresh is
  // deliberately deferred so an offline launch is not blocked by retries.
  final cart = await container.read(cartStorageProvider).load();
  container.read(cartControllerProvider.notifier).hydrate(cart);

  final config = await container.read(configRepositoryProvider).loadCached();
  container.read(appConfigControllerProvider.notifier).hydrate(config);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const QuickKartApp(),
    ),
  );
  unawaited(container.read(appConfigControllerProvider.notifier).refresh());
}
