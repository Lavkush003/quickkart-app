import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/network/api_exceptions.dart';
import 'package:quickkart/features/app_config/data/config_repository.dart';
import 'package:quickkart/features/app_config/presentation/app_config_controller.dart';

import 'helpers/test_harness.dart';

void main() {
  late TestHarness harness;

  setUp(() => harness = TestHarness());
  tearDown(() => harness.dispose());

  test('load persists the latest valid remote configuration', () async {
    final config = await harness.read(configRepositoryProvider).load();

    expect(config.deliveryFeePaise, 2500);
    expect(harness.store.snapshot, contains('app_config.cached.v1'));
  });

  test('offline load falls back to the last known valid configuration',
      () async {
    harness.server.publishConfig({'delivery_fee_paise': 4200});
    final repository = harness.read(configRepositoryProvider);
    await repository.load();
    harness.server.chaos.offline = true;

    final config = await repository.load();

    expect(config.deliveryFeePaise, 4200);
  });

  test('malformed remote config preserves the previous valid cache', () async {
    final repository = harness.read(configRepositoryProvider);
    await repository.load();
    harness.server.publishConfig({'delivery_fee_paise': -1});

    await expectLater(
      repository.loadFresh(),
      throwsA(isA<ServerException>()),
    );
    final config = await repository.load();

    expect(config.deliveryFeePaise, 2500);
  });

  test('simultaneous fresh loads share one request', () async {
    harness.server.chaos.latencyOverride = (request) =>
        request.path == '/v1/config'
            ? const Duration(milliseconds: 10)
            : Duration.zero;
    final repository = harness.read(configRepositoryProvider);

    await Future.wait([
      repository.loadFresh(),
      repository.loadFresh(),
      repository.loadFresh(),
    ]);

    final configRequests = harness.server.requestLog
        .where((request) => request.path == '/v1/config')
        .length;
    expect(configRequests, 1);
  });

  test('published configuration updates the controller without restart',
      () async {
    harness.read(appConfigControllerProvider.notifier);
    expect(harness.server.configListenerCount, 1);
    harness.server.publishConfig({'delivery_fee_paise': 4700});

    for (var attempt = 0; attempt < 20; attempt++) {
      if (harness.read(appConfigControllerProvider).deliveryFeePaise == 4700) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(
      harness.read(appConfigControllerProvider).deliveryFeePaise,
      4700,
    );
  });

  test('disposing the controller cancels its live update subscription',
      () async {
    final server = harness.server;
    harness.read(appConfigControllerProvider.notifier);
    expect(server.configListenerCount, 1);

    final previousHarness = harness;
    previousHarness.dispose();
    expect(server.configListenerCount, 0);
    harness = TestHarness();
  });
}
