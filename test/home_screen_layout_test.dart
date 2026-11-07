import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/app_config/presentation/app_config_controller.dart';
import 'package:quickkart/features/catalog/presentation/home_screen.dart';

import 'helpers/test_harness.dart';

void main() {
  late TestHarness harness;

  setUp(() => harness = TestHarness());
  tearDown(() => harness.dispose());

  testWidgets('renders home sections in live configured order', (tester) async {
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = harness.read(appConfigControllerProvider.notifier);
    controller.hydrate(_config([
      'deals',
      'banner',
      'categories',
      'all_products',
    ]));
    await _pumpHome(tester, harness);

    expect(find.text('Featured promotion'), findsOneWidget);
    expect(find.text('Deals'), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('All products'), findsOneWidget);
    _expectSectionOrder(
        tester, ['deals', 'banner', 'categories', 'all-products']);

    controller.hydrate(_config([
      'categories',
      'all_products',
      'banner',
      'deals',
    ]));
    await tester.pumpAndSettle();
    _expectSectionOrder(
        tester, ['categories', 'all-products', 'banner', 'deals']);
  });

  testWidgets('configured banner without content is safely omitted',
      (tester) async {
    final controller = harness.read(appConfigControllerProvider.notifier);
    controller.hydrate(
      AppConfig.fromValues({
        'home_sections': jsonEncode(['banner'])
      }),
    );
    await _pumpHome(tester, harness);

    expect(find.text('Search "milk", "chips"…'), findsOneWidget);
    expect(find.text('Featured promotion'), findsNothing);
  });
}

AppConfig _config(List<String> sections) => AppConfig.fromValues({
      'home_sections': jsonEncode(sections),
      'home_banner': jsonEncode({
        'title': 'Featured promotion',
        'subtitle': 'Seasonal offers',
        'color': '#FF6F00',
      }),
    });

Future<void> _pumpHome(WidgetTester tester, TestHarness harness) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectSectionOrder(WidgetTester tester, List<String> sectionIds) {
  const labels = {
    'banner': 'Featured promotion',
    'categories': 'Categories',
    'deals': 'Deals',
    'all-products': 'All products',
  };
  final positions = [
    for (final sectionId in sectionIds)
      tester.getTopLeft(find.text(labels[sectionId]!)).dy,
  ];
  for (var index = 1; index < positions.length; index++) {
    expect(positions[index], greaterThan(positions[index - 1]));
  }
}
