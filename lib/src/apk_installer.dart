import 'package:flutter/services.dart';

/// Result of an APK installation attempt, received via [EventChannel].
class InstallResult {
  final bool success;
  final String message;

  const InstallResult({required this.success, required this.message});

  factory InstallResult.fromMap(Map<dynamic, dynamic> map) {
    return InstallResult(
      success: map['status'] == 'success',
      message: (map['message'] as String?) ?? '',
    );
  }

  @override
  String toString() => 'InstallResult(success: $success, message: $message)';
}

/// Wraps the native Kotlin plugin for APK installation.
class ApkInstaller {
  static const _channel = MethodChannel('com.gg.updater');
  static const _statusChannel = EventChannel('com.gg.updater/installStatus');

  /// Stream of install results from the native [PackageInstaller].
  ///
  /// Emits an [InstallResult] after each installation attempt completes
  /// (success or failure). Listen to this before calling [install] to
  /// capture the outcome.
  static Stream<InstallResult> get installStatus {
    return _statusChannel.receiveBroadcastStream().map(
          (event) => InstallResult.fromMap(event as Map<dynamic, dynamic>),
        );
  }

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

  /// Verify file checksum via native (faster than Dart). Returns (ok, computedHash).
  static Future<({bool ok, String? computedHash})> verifyChecksum(
    String filePath,
    String expected,
    bool useSha256,
  ) async {
    final r = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'verifyChecksum',
      {
        'filePath': filePath,
        'expected': expected.toLowerCase().trim(),
        'algorithm': useSha256 ? 'SHA-256' : 'SHA-1',
      },
    );
    if (r == null) return (ok: false, computedHash: null);
    return (
      ok: r['ok'] as bool? ?? false,
      computedHash: r['computedHash'] as String?,
    );
  }
}
