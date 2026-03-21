import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'apk_installer.dart';
import 'models.dart';

/// Core update service. Check → Download → Install.
///
/// Equivalent of AyuGram's UpdaterUtils.java — but in ~120 lines of Dart.
class UpdateService {
  final Dio _dio;
  final String endpoint;
  final Map<String, String>? headers;

  String? _currentVersion;
  CancelToken? _cancelToken;

  UpdateService({
    required this.endpoint,
    this.headers,
    Dio? dio,
  }) : _dio = dio ?? Dio();

  // ─── CHECK ────────────────────────────────────────────────────────

  /// Hit the server, get update status.
  Future<UpdateInfo> check() async {
    _currentVersion ??= (await PackageInfo.fromPlatform()).version;

    try {
      final response = await _dio.get(
        endpoint,
        queryParameters: {
          'platform': 'android',
          'version': _currentVersion,
        },
        options: Options(headers: headers),
      );

      var data = response.data as Map<String, dynamic>;
      // Frappe wraps responses in {message: ...} — unwrap if needed
      if (data.containsKey('message') && data['message'] is Map<String, dynamic>) {
        data = data['message'] as Map<String, dynamic>;
      }

      return UpdateInfo.fromJson(data);
    } catch (e) {
      return UpdateInfo.none();
    }
  }

  // ─── DOWNLOAD ─────────────────────────────────────────────────────

  /// Download APK with progress. Returns a stream of [DownloadProgress].
  ///
  /// If the APK for this version is already cached, emits a single
  /// complete event immediately (like AyuGram's updateDownloaded check).
  Stream<DownloadProgress> download(String url, String version, {String? sha256Checksum}) async* {
    final dir = await _otaDir(version);
    final file = File('${dir.path}/update.apk');

    // Cache hit — already downloaded
    if (file.existsSync()) {
      final len = await file.length();
      yield DownloadProgress(
        received: len,
        total: len,
        isComplete: true,
        filePath: file.path,
      );
      return;
    }

    _cancelToken = CancelToken();

    try {
      final controller = StreamController<DownloadProgress>();

      _dio.download(
        url,
        file.path,
        deleteOnError: true,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          controller.add(DownloadProgress(
            received: received,
            total: total,
          ));
        },
      ).then((_) async {
        // Verify SHA256 if provided (like ota_update package)
        if (sha256Checksum != null) {
          final bytes = await file.readAsBytes();
          final hash = sha256.convert(bytes).toString();
          if (hash != sha256Checksum.toLowerCase()) {
            file.deleteSync();
            controller.add(DownloadProgress(
              received: 0,
              total: 0,
              error: 'SHA256 checksum mismatch: expected $sha256Checksum, got $hash',
            ));
            controller.close();
            return;
          }
        }
        controller.add(DownloadProgress(
          received: 1,
          total: 1,
          isComplete: true,
          filePath: file.path,
        ));
        controller.close();
      }).catchError((e) {
        controller.add(DownloadProgress(
          received: 0,
          total: 0,
          error: e.toString(),
        ));
        controller.close();
      });

      yield* controller.stream;
    } catch (e) {
      yield DownloadProgress(received: 0, total: 0, error: e.toString());
    }
  }

  /// Cancel an in-progress download.
  void cancelDownload() {
    _cancelToken?.cancel('User cancelled');
    _cancelToken = null;
  }

  // ─── INSTALL ──────────────────────────────────────────────────────

  /// Trigger native APK install. Checks permission first.
  static Future<bool> install(String filePath) async {
    if (!await ApkInstaller.canInstall()) {
      await ApkInstaller.openInstallPermissionSettings();
      return false;
    }
    return ApkInstaller.install(filePath);
  }

  // ─── CACHE ────────────────────────────────────────────────────────

  /// Check if an APK is already downloaded for this version.
  Future<bool> isCached(String version) async {
    final dir = await _otaDir(version);
    return File('${dir.path}/update.apk').existsSync();
  }

  /// Delete all cached APKs.
  Future<void> clearCache() async {
    final base = await _otaBaseDir();
    if (base.existsSync()) {
      base.deleteSync(recursive: true);
    }
  }

  /// Get total cache size as formatted string.
  Future<String> get cacheSize async {
    final base = await _otaBaseDir();
    if (!base.existsSync()) return '0 B';
    int total = 0;
    base.listSync(recursive: true).whereType<File>().forEach((f) {
      total += f.lengthSync();
    });
    return formatBytes(total);
  }

  // ─── FORCE UPDATE PERSISTENCE ────────────────────────────────────
  // Like Telegram's SharedConfig.pendingAppUpdate — survives app kill.

  /// Persist a force update so it re-shows after app restart.
  Future<void> savePendingUpdate(UpdateInfo info) async {
    _currentVersion ??= (await PackageInfo.fromPlatform()).version;
    final base = await _otaBaseDir();
    if (!base.existsSync()) base.createSync(recursive: true);
    final file = File('${base.path}/pending_update.json');
    file.writeAsStringSync(jsonEncode({
      'status': info.status.name,
      'latest_version': info.latestVersion,
      'min_version': info.minVersion,
      'download_url': info.downloadUrl,
      'file_size': info.fileSize,
      'sha256': info.sha256,
      'changelog': info.changelog,
      'message': info.message,
      'maintenance_message': info.maintenanceMessage,
      'checked_at_version': _currentVersion,
    }));
  }

  /// Load persisted force update. Returns null if none or stale.
  Future<UpdateInfo?> loadPendingUpdate() async {
    _currentVersion ??= (await PackageInfo.fromPlatform()).version;
    final file = File('${(await _otaBaseDir()).path}/pending_update.json');
    if (!file.existsSync()) return null;
    try {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      // Stale: app was updated since we saved this
      if (data['checked_at_version'] != _currentVersion) {
        file.deleteSync();
        return null;
      }
      return UpdateInfo.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  /// Clear persisted force update (called on 10-tap escape or server says none).
  Future<void> clearPendingUpdate() async {
    final file = File('${(await _otaBaseDir()).path}/pending_update.json');
    if (file.existsSync()) file.deleteSync();
  }

  // ─── INTERNAL ─────────────────────────────────────────────────────

  Future<Directory> _otaBaseDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}/ota_updates');
  }

  Future<Directory> _otaDir(String version) async {
    // Sanitize version to prevent path traversal (e.g. "../../evil")
    final safe = version.replaceAll(RegExp(r'[^a-zA-Z0-9._\-+]'), '_');
    final dir = Directory('${(await _otaBaseDir()).path}/$safe');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }
}
