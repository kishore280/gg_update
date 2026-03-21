import 'package:flutter/services.dart';

/// Wraps the native Kotlin plugin for APK installation.
class ApkInstaller {
  static const _channel = MethodChannel('com.gg.updater');

  /// Install an APK from a local file path.
  /// Triggers Android's native package installer.
  static Future<bool> install(String filePath) async {
    final result = await _channel.invokeMethod<bool>(
      'installApk',
      {'filePath': filePath},
    );
    return result ?? false;
  }

  /// Check if the app has permission to install unknown APKs (Android 8+).
  static Future<bool> canInstall() async {
    final result = await _channel.invokeMethod<bool>('canInstallApks');
    return result ?? true;
  }

  /// Open the system settings page for "Install unknown apps" permission.
  static Future<void> openInstallPermissionSettings() async {
    await _channel.invokeMethod('openInstallPermissionSettings');
  }
}
