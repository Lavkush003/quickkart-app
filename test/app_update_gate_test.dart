import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/app_config/presentation/app_config_controller.dart';
import 'package:quickkart/features/app_config/presentation/app_update_gate.dart';

import 'helpers/test_harness.dart';

void main() {
  late TestHarness harness;
  final navigatorKey = GlobalKey<NavigatorState>();

  setUp(() => harness = TestHarness());
  tearDown(() => harness.dispose());

  testWidgets('required update gates normal app content and applies live',
      (tester) async {
    final controller = harness.read(appConfigControllerProvider.notifier);
    await _pumpGate(tester, harness, navigatorKey);
    expect(find.text('Normal app'), findsOneWidget);

    controller.hydrate(_config(minimum: '2.0.0', latest: '2.1.0'));
    await tester.pump();

    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('Normal app'), findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
  });

  testWidgets('malformed configured version does not lock out the app',
      (tester) async {
    final controller = harness.read(appConfigControllerProvider.notifier);
    controller.hydrate(_config(minimum: 'not-a-version', latest: '2.0.0'));

    await _pumpGate(tester, harness, navigatorKey);

    expect(find.text('Normal app'), findsOneWidget);
    expect(find.text('Update required'), findsNothing);
  });

  testWidgets('optional update can be dismissed for the same latest version',
      (tester) async {
    final controller = harness.read(appConfigControllerProvider.notifier);
    controller.hydrate(_config(minimum: '1.0.0', latest: '1.5.0'));

    await _pumpGate(tester, harness, navigatorKey);
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsNothing);
    expect(
      harness.store.snapshot['app_config.dismissed_optional_update.v1'],
      '1.5.0',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpGate(tester, harness, navigatorKey);
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
  });
}

Future<void> _pumpGate(
  WidgetTester tester,
  TestHarness harness,
  GlobalKey<NavigatorState> navigatorKey,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) => AppUpdateGate(
          navigatorKey: navigatorKey,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const Scaffold(body: Text('Normal app')),
      ),
    ),
  );
  await tester.pump();
}

AppConfig _config({required String minimum, required String latest}) {
  return AppConfig.fromValues({
    'min_supported_version': minimum,
    'latest_version': latest,
    'update_url': 'https://updates.example.com/quickkart',
  });
}
