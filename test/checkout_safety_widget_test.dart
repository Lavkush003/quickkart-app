import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/presentation/app_config_controller.dart';
import 'package:quickkart/features/app_config/presentation/app_update_gate.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart';
import 'package:quickkart/features/cart/presentation/cart_screen.dart';

import 'helpers/test_harness.dart';

void main() {
  late TestHarness harness;
  final navigatorKey = GlobalKey<NavigatorState>();

  setUp(() => harness = TestHarness());
  tearDown(() => harness.dispose());

  Future<void> prepareCart() async {
    final product =
        (await harness.read(catalogApiProvider).getProductsByIds(['fruits-01']))
            .products
            .single;
    await harness.read(cartControllerProvider.notifier).replace(
          Cart(lines: [CartLine.fromProduct(product)]),
        );
  }

  Future<void> pumpCartScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          builder: (context, child) => AppUpdateGate(
            navigatorKey: navigatorKey,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const CartScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('unknown order result prompts safe status retry', (tester) async {
    await prepareCart();
    harness.server.chaos.loseNextOrderResponses = 2;
    await pumpCartScreen(tester);

    await tester.tap(find.text('Place order  ▶'));
    await tester.pumpAndSettle();

    expect(find.text('Check order status  ▶'), findsOneWidget);
    expect(find.textContaining('order request timed out'), findsOneWidget);
    expect(find.textContaining('status is unknown'), findsOneWidget);
    expect(harness.server.orderCount, 1);

    await tester.tap(find.text('Check order status  ▶'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Order QK-'), findsOneWidget);
    expect(harness.server.orderCount, 1);
  });

  testWidgets('offline checkout shows a connectivity message', (tester) async {
    await prepareCart();
    harness.server.chaos.offline = true;
    await pumpCartScreen(tester);

    await tester.tap(find.text('Place order  ▶'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No internet connection'), findsOneWidget);
    expect(harness.server.orderCount, 0);
  });

  testWidgets('closed store message is shown before checkout', (tester) async {
    await prepareCart();
    harness.server.publishConfig({
      'store_open': false,
      'store_closed_message': 'Closed for inventory',
    });
    await harness.read(appConfigControllerProvider.notifier).refresh();
    await pumpCartScreen(tester);

    expect(find.text('Closed for inventory'), findsOneWidget);
    expect(find.text('Store closed'), findsOneWidget);
    final checkoutButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Store closed'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(checkoutButton.onPressed, isNull);
    expect(harness.server.orderCount, 0);
  });

  testWidgets('store close and reopen update checkout without restart',
      (tester) async {
    await prepareCart();
    await pumpCartScreen(tester);
    expect(find.text('Place order  ▶'), findsOneWidget);

    harness.server.publishConfig({
      'store_open': false,
      'store_closed_message': 'Closed for weather',
    });
    for (var attempt = 0;
        attempt < 20 && find.text('Closed for weather').evaluate().isEmpty;
        attempt++) {
      await tester.pump(const Duration(milliseconds: 5));
    }

    expect(find.text('Closed for weather'), findsOneWidget);
    expect(find.text('Store closed'), findsOneWidget);
    expect(harness.server.orderCount, 0);

    harness.server.publishConfig({
      'store_open': true,
      'store_closed_message': 'We are open',
    });
    for (var attempt = 0;
        attempt < 20 && find.text('We are open').evaluate().isEmpty;
        attempt++) {
      await tester.pump(const Duration(milliseconds: 5));
    }

    expect(find.text('We are open'), findsNothing);
    expect(find.text('Place order  ▶'), findsOneWidget);
    final checkoutButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Place order  ▶'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(checkoutButton.onPressed, isNotNull);
  });
}
