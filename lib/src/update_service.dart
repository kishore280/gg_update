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
  String? _activeDownloadVersion;

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

    // Cache hit — already downloaded (like AyuGram's updateDownloaded check)
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

    // Clean old version caches before downloading new one
    await _cleanOldVersions(version);

    _cancelToken = CancelToken();
    _activeDownloadVersion = version;

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
        final len = await file.length();
        controller.add(DownloadProgress(
          received: len,
          total: len,
          isComplete: true,
          filePath: file.path,
        ));
        controller.close();
      }).catchError((e) {
        controller.add(DownloadProgress(
          received: 0,
          total: 0,
          error: _friendlyError(e),
        ));
        controller.close();
      });

      yield* controller.stream;
    } catch (e) {
      yield DownloadProgress(received: 0, total: 0, error: _friendlyError(e));
    } finally {
      _activeDownloadVersion = null;
    }
  }

  /// Cancel an in-progress download and clean up partial file.
  Future<void> cancelDownload() async {
    _cancelToken?.cancel('User cancelled');
    _cancelToken = null;
    // Clean partial file (deleteOnError handles Dio errors, but belt-and-suspenders)
    if (_activeDownloadVersion != null) {
      final versionToClean = _activeDownloadVersion!;
      try {
        final dir = await _otaDir(versionToClean);
        final file = File('${dir.path}/update.apk');
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Errors during cleanup can be ignored.
      } finally {
        // Only clear if no new download has started for a different version.
        if (_activeDownloadVersion == versionToClean) {
          _activeDownloadVersion = null;
        }
      }
    }
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

  // ─── COOLDOWN PERSISTENCE ────────────────────────────────────────
  // Like AyuGram's ExteraConfig.lastUpdateCheckTime in SharedPreferences.
  // Survives app restart so we don't spam the server on every cold start.

  /// Save the last check timestamp to disk.
  Future<void> saveLastCheckTime(int timestampMs) async {
    final base = await _otaBaseDir();
    if (!base.existsSync()) base.createSync(recursive: true);
    File('${base.path}/last_check.txt').writeAsStringSync('$timestampMs');
  }

  /// Load the last check timestamp from disk. Returns 0 if none.
  Future<int> loadLastCheckTime() async {
    final file = File('${(await _otaBaseDir()).path}/last_check.txt');
    if (!file.existsSync()) return 0;
    try {
      return int.parse(file.readAsStringSync().trim());
    } catch (_) {
      return 0;
    }
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

  /// Delete cached APKs for versions other than [keepVersion].
  Future<void> _cleanOldVersions(String keepVersion) async {
    final base = await _otaBaseDir();
    if (!base.existsSync()) return;
    final safe = keepVersion.replaceAll(RegExp(r'[^a-zA-Z0-9._\-+]'), '_');
    for (final entity in base.listSync()) {
      if (entity is Directory && entity.path.split('/').last != safe) {
        try {
          entity.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }

  /// Convert raw errors to user-friendly messages.
  static String _friendlyError(dynamic e) {
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Connection timed out. Please check your internet and try again.';
        case DioExceptionType.connectionError:
          return 'No internet connection. Please check your network and try again.';
        case DioExceptionType.cancel:
          return 'Download cancelled.';
        case DioExceptionType.badResponse:
          return 'Server error (${e.response?.statusCode ?? 'unknown'}). Please try again later.';
        default:
          return 'Download failed. Please try again.';
      }
    }
    return 'Download failed. Please try again.';
  }
}
