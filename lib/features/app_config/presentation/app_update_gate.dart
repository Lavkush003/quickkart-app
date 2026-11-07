import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers.dart';
import '../domain/app_config.dart';
import '../domain/update_policy.dart';
import 'app_config_controller.dart';

const _dismissedOptionalUpdateKey = 'app_config.dismissed_optional_update.v1';

class AppUpdateGate extends ConsumerStatefulWidget {
  const AppUpdateGate({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  ConsumerState<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends ConsumerState<AppUpdateGate> {
  String? _dismissedVersion;
  String? _promptedVersion;
  bool _dismissalLoaded = false;
  bool _dialogShowing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDismissedVersion());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppConfig>(appConfigControllerProvider, (previous, next) {
      final currentVersion = ref.read(appVersionProvider);
      final requirement = _requirement(next, currentVersion);
      if (_dialogShowing &&
          (requirement != UpdateRequirement.optional ||
              next.latestVersion != _promptedVersion)) {
        _closeOptionalPrompt();
      }
    });

    final config = ref.watch(appConfigControllerProvider);
    final currentVersion = ref.watch(appVersionProvider);
    final requirement = _requirement(config, currentVersion);

    if (requirement == UpdateRequirement.optional) {
      _scheduleOptionalPrompt(config);
    }

    final required = requirement == UpdateRequirement.required;
    return Column(
      children: [
        if (!config.storeOpen)
          _StoreClosedBanner(message: config.storeClosedMessage),
        Expanded(
          child: PopScope(
            canPop: !required,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ExcludeSemantics(
                  excluding: required,
                  child:
                      AbsorbPointer(absorbing: required, child: widget.child),
                ),
                if (required)
                  Positioned.fill(
                    child: _UpdateRequiredPage(
                      onUpdate: () =>
                          unawaited(_openUpdateUrl(config.updateUrl)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _loadDismissedVersion() async {
    String? dismissedVersion;
    try {
      dismissedVersion = await ref
          .read(keyValueStoreProvider)
          .getString(_dismissedOptionalUpdateKey);
    } on Exception catch (error) {
      debugPrint('Could not restore dismissed update version: $error');
    }

    if (!mounted) return;
    setState(() {
      _dismissedVersion = dismissedVersion;
      _dismissalLoaded = true;
    });
  }

  void _scheduleOptionalPrompt(AppConfig config) {
    final version = config.latestVersion;
    if (!_dismissalLoaded ||
        _dismissedVersion == version ||
        _promptedVersion == version) {
      return;
    }

    _promptedVersion = version;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final currentConfig = ref.read(appConfigControllerProvider);
      if (_requirement(currentConfig, ref.read(appVersionProvider)) !=
              UpdateRequirement.optional ||
          currentConfig.latestVersion != version ||
          _dismissedVersion == version) {
        _promptedVersion = null;
        return;
      }

      final navigatorContext = widget.navigatorKey.currentContext;
      if (navigatorContext == null) {
        _promptedVersion = null;
        return;
      }
      unawaited(_showOptionalPrompt(navigatorContext, currentConfig));
    });
  }

  Future<void> _showOptionalPrompt(
    BuildContext navigatorContext,
    AppConfig config,
  ) async {
    _dialogShowing = true;
    final shouldUpdate = await showDialog<bool>(
      context: navigatorContext,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Update available'),
        content: Text('Version ${config.latestVersion} is available.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    _dialogShowing = false;

    if (shouldUpdate == true) {
      await _openUpdateUrl(config.updateUrl);
      return;
    }

    _dismissedVersion = config.latestVersion;
    try {
      await ref.read(keyValueStoreProvider).setString(
            _dismissedOptionalUpdateKey,
            config.latestVersion,
          );
    } on Exception catch (error) {
      debugPrint('Could not persist dismissed update version: $error');
    }
    if (mounted) setState(() {});
  }

  void _closeOptionalPrompt() {
    if (!_dialogShowing) return;
    _dialogShowing = false;
    widget.navigatorKey.currentState?.pop();
  }

  Future<void> _openUpdateUrl(String updateUrl) async {
    final uri = Uri.tryParse(updateUrl.trim());
    if (uri == null || !uri.hasScheme) {
      _showLaunchError('The configured update link is invalid.');
      return;
    }

    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _showLaunchError('Could not open the update link.');
      }
    } on PlatformException catch (error) {
      debugPrint('Could not launch update URL: $error');
      _showLaunchError('Could not open the update link.');
    } on MissingPluginException catch (error) {
      debugPrint('URL launcher plugin is unavailable: $error');
      _showLaunchError('Could not open the update link.');
    }
  }

  void _showLaunchError(String message) {
    final navigatorContext = widget.navigatorKey.currentContext;
    if (navigatorContext == null) return;
    ScaffoldMessenger.maybeOf(navigatorContext)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  UpdateRequirement _requirement(AppConfig config, String currentVersion) {
    return UpdatePolicy.evaluate(
      currentVersion: currentVersion,
      minSupportedVersion: config.minSupportedVersion,
      latestVersion: config.latestVersion,
    );
  }
}

class _UpdateRequiredPage extends StatelessWidget {
  const _UpdateRequiredPage({
    required this.onUpdate,
  });

  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.system_update_alt, size: 56),
                const SizedBox(height: 16),
                Text(
                  'Update required',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Update QuickKart to continue using the app.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onUpdate,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Update now'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StoreClosedBanner extends StatelessWidget {
  const _StoreClosedBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final visibleMessage =
        message.trim().isEmpty ? 'The store is temporarily closed.' : message;
    return Material(
      color: Colors.amber.shade100,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.brown.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    visibleMessage,
                    style: TextStyle(
                      color: Colors.brown.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
