import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import 'models.dart';
import 'update_service.dart';
import 'ui.dart';

/// One-liner update system.
///
/// ```dart
/// await GgUpdater.checkAndPrompt(context,
///   endpoint: 'https://erp.myapp.com/api/method/myapp.api.check_update',
/// );
/// ```
class GgUpdater {
  static UpdateService? _service;
  static Duration _cooldown = const Duration(hours: 1);
  static int _lastCheckMs = 0;
  static bool _cooldownLoaded = false;

  /// Initialize once, reuse everywhere.
  static void init({
    required String endpoint,
    Map<String, String>? headers,
    Dio? dio,
    Duration cooldown = const Duration(hours: 1),
  }) {
    _service = UpdateService(
      endpoint: endpoint,
      headers: headers,
      dio: dio,
    );
    _cooldown = cooldown;
  }

  /// Get the service instance (for manual use).
  ///
  /// Returns `null` if [init] has not been called.
  static UpdateService? get service => _service;

  /// Check for updates and show the right UI automatically.
  ///
  /// This is the one-liner you call on app startup.
  /// - [UpdateStatus.none] → does nothing
  /// - [UpdateStatus.soft] → shows dismissible bottom sheet
  /// - [UpdateStatus.hard] → pushes fullscreen blocking view
  /// - [UpdateStatus.maintenance] → pushes maintenance screen
  ///
  /// Returns the [UpdateInfo] so you can do extra stuff if needed.
  /// Never throws — returns [UpdateInfo.none] on any failure.
  static Future<UpdateInfo> checkAndPrompt(
    BuildContext context, {
    String? endpoint,
    Map<String, String>? headers,
    Dio? dio,
    bool respectCooldown = true,
  }) async {
    try {
      return await _checkAndPromptInner(
        context,
        endpoint: endpoint,
        headers: headers,
        dio: dio,
        respectCooldown: respectCooldown,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('GgUpdater: checkAndPrompt failed: $e');
      return UpdateInfo.none();
    }
  }

  static Future<UpdateInfo> _checkAndPromptInner(
    BuildContext context, {
    String? endpoint,
    Map<String, String>? headers,
    Dio? dio,
    bool respectCooldown = true,
  }) async {
    if (_service == null && endpoint == null) {
      throw StateError(
        'Either call GgUpdater.init() first, or pass endpoint to checkAndPrompt().',
      );
    }
    final svc = _service ??
        UpdateService(
          endpoint: endpoint!,
          headers: headers,
          dio: dio,
        );

    // Re-show persisted blocking state (survives app kill, like Telegram's pendingAppUpdate)
    final pending = await svc.loadPendingUpdate();
    if (pending != null && context.mounted) {
      if (pending.status == UpdateStatus.hard) {
        Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => ForceUpdateScreen(info: pending, service: svc),
          ),
        );
        return pending;
      }
      if (pending.status == UpdateStatus.maintenance) {
        Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => MaintenanceScreen(info: pending),
          ),
        );
        return pending;
      }
    }

    // Cooldown check — persisted to disk like AyuGram's lastUpdateCheckTime
    if (respectCooldown) {
      if (!_cooldownLoaded) {
        _lastCheckMs = await svc.loadLastCheckTime();
        _cooldownLoaded = true;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastCheckMs < _cooldown.inMilliseconds) {
        return UpdateInfo.none();
      }
      _lastCheckMs = now;
      await svc.saveLastCheckTime(now);
    }

    final info = await svc.check();

    if (!context.mounted) return info;

    // Persist blocking states so they survive app kill; clear stale ones
    if (info.status == UpdateStatus.hard || info.status == UpdateStatus.maintenance) {
      await svc.savePendingUpdate(info);
    } else {
      await svc.clearPendingUpdate();
    }

    switch (info.status) {
      case UpdateStatus.none:
        break;

      case UpdateStatus.soft:
        SoftUpdateSheet.show(context, info, svc);
        break;

      case UpdateStatus.hard:
        Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => ForceUpdateScreen(info: info, service: svc),
          ),
        );
        break;

      case UpdateStatus.maintenance:
        Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => MaintenanceScreen(info: info),
          ),
        );
        break;
    }

    return info;
  }

  /// Check only, no UI. For manual handling.
  /// Never throws — returns [UpdateInfo.none] on failure.
  static Future<UpdateInfo> check() async {
    try {
      if (_service == null) {
        throw StateError('Call GgUpdater.init() first');
      }
      return await _service!.check();
    } catch (e) {
      if (kDebugMode) debugPrint('GgUpdater: check failed: $e');
      return UpdateInfo.none();
    }
  }

  /// Clear all cached APKs.
  /// Never throws — silently fails on error.
  static Future<void> clearCache() async {
    try {
      await _service?.clearCache();
    } catch (e) {
      if (kDebugMode) debugPrint('GgUpdater: clearCache failed: $e');
    }
  }
}
