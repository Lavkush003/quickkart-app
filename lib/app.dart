import 'package:flutter/material.dart';

import 'features/app_config/presentation/app_update_gate.dart';
import 'features/catalog/presentation/home_screen.dart';

final _appNavigatorKey = GlobalKey<NavigatorState>();

class QuickKartApp extends StatelessWidget {
  const QuickKartApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuickKart',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0C831F),
        scaffoldBackgroundColor: const Color(0xFFF6F7F9),
      ),
      navigatorKey: _appNavigatorKey,
      builder: (context, child) => AppUpdateGate(
        navigatorKey: _appNavigatorKey,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomeScreen(),
    );
  }
}
