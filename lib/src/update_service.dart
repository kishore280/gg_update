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

  // ─── GLOBAL DOWNLOAD STATE (like Telegram's FileLoader) ──────────
  // Download runs independently of UI lifecycle. UI subscribes/unsubscribes.
  StreamController<DownloadProgress>? _broadcastController;
  DownloadProgress? _lastProgress;

  /// Current download state. UI can check this on open to resume display.
  DownloadProgress? get lastProgress => _lastProgress;

  /// Whether a download is currently in progress.
  bool get isDownloading => _activeDownloadVersion != null && _cancelToken != null && !_cancelToken!.isCancelled;

  /// Subscribe to the active download's progress stream.
  /// Returns null if no download is active.
  Stream<DownloadProgress>? get progressStream => _broadcastController?.stream;

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

  /// Download APK with progress. Returns a broadcast stream of [DownloadProgress].
  ///
  /// Like Telegram's FileLoader: the download runs globally in the service.
  /// Multiple UI screens can subscribe/unsubscribe without affecting the download.
  /// If the APK for this version is already cached, emits a single
  /// complete event immediately (like AyuGram's updateDownloaded check).
  Stream<DownloadProgress> download(String url, String version, {String? sha256Checksum}) async* {
    final dir = await _otaDir(version);
    final file = File('${dir.path}/update.apk');

    // Cache hit — already downloaded (like AyuGram's updateDownloaded check)
    // Verify integrity if checksum is available to catch corrupt/partial files.
    if (await file.exists()) {
      if (sha256Checksum != null) {
        final digest = await sha256.bind(file.openRead()).first;
        if (digest.toString() != sha256Checksum.toLowerCase()) {
          // Corrupt cache — delete and re-download
          try { await file.delete(); } catch (_) {}
        }
      }
      // Re-check existence after possible deletion above
      if (await file.exists()) {
        final len = await file.length();
        final complete = DownloadProgress(
          received: len,
          total: len,
          isComplete: true,
          filePath: file.path,
        );
        _lastProgress = complete;
        yield complete;
        return;
      }
    }

    // If a download is already in progress
    if (isDownloading) {
      if (_activeDownloadVersion == version && _broadcastController != null) {
        // For the same version, just subscribe to the existing stream
        yield* _broadcastController!.stream;
      } else {
        // For a different version, report an error as we can't handle concurrent downloads.
        yield DownloadProgress(
          received: 0,
          total: 0,
          error: 'Another download for version $_activeDownloadVersion is in progress.',
        );
      }
      return;
    }

    // Clean old version caches before downloading new one
    await _cleanOldVersions(version);

    _cancelToken = CancelToken();
    _activeDownloadVersion = version;
    _lastProgress = const DownloadProgress(received: 0, total: 0);

    // Broadcast controller — multiple listeners can subscribe/unsubscribe
    _broadcastController?.close();
    _broadcastController = StreamController<DownloadProgress>.broadcast();

    void _emit(DownloadProgress p) {
      _lastProgress = p;
      final controller = _broadcastController;
      if (controller != null && !controller.isClosed) {
        controller.add(p);
      }
    }

    // Check for partial download to resume via HTTP Range header.
    // Dio's download() overwrites the target file, so when resuming we
    // download the remaining chunk to a separate .chunk file and then
    // append it to the existing .partial file.
    final partialFile = File('${file.path}.partial');
    final chunkFile = File('${file.path}.chunk');
    int resumeOffset = 0;
    if (await partialFile.exists()) {
      resumeOffset = await partialFile.length();
    }

    // When resuming, Dio writes only the new bytes to chunkFile.
    // For fresh downloads, Dio writes directly to partialFile.
    final downloadTarget = resumeOffset > 0 ? chunkFile.path : partialFile.path;

    try {
      int effectiveOffset = resumeOffset;

      _dio.download(
        url,
        downloadTarget,
        deleteOnError: false,
        cancelToken: _cancelToken,
        options: resumeOffset > 0
            ? Options(headers: {'Range': 'bytes=$resumeOffset-'})
            : null,
        onReceiveProgress: (received, total) {
          final actualReceived = received + effectiveOffset;
          final actualTotal = total > 0 ? total + effectiveOffset : total;
          _emit(DownloadProgress(received: actualReceived, total: actualTotal));
        },
      ).then((response) async {
        if (resumeOffset > 0) {
          if (response.statusCode == 200) {
            // Server ignored Range — chunkFile has the full content.
            // Replace partial with it.
            effectiveOffset = 0;
            if (await partialFile.exists()) await partialFile.delete();
            await chunkFile.rename(partialFile.path);
          } else {
            // Server honoured Range (206) — append chunk to partial.
            final raf = await partialFile.open(mode: FileMode.writeOnlyAppend);
            try {
              await raf.writeFrom(await chunkFile.readAsBytes());
            } finally {
              await raf.close();
            }
            await chunkFile.delete();
          }
        }
        // Rename partial file to final name on success
        await partialFile.rename(file.path);
        // Verify SHA256 if provided (like ota_update package)
        // Use streaming hash to avoid loading entire APK into memory.
        if (sha256Checksum != null) {
          final digest = await sha256.bind(file.openRead()).first;
          final hash = digest.toString();
          if (hash != sha256Checksum.toLowerCase()) {
            await file.delete();
            _emit(DownloadProgress(
              received: 0,
              total: 0,
              error: 'SHA256 checksum mismatch: expected $sha256Checksum, got $hash',
            ));
            _cleanup();
            return;
          }
        }
        final len = await file.length();
        _emit(DownloadProgress(
          received: len,
          total: len,
          isComplete: true,
          filePath: file.path,
        ));
        _cleanup();
      }).catchError((e) {
        _emit(DownloadProgress(
          received: 0,
          total: 0,
          error: _friendlyError(e),
        ));
        _cleanup();
      });

      yield* _broadcastController!.stream;
    } catch (e) {
      yield DownloadProgress(received: 0, total: 0, error: _friendlyError(e));
      _cleanup();
    }
  }

  void _cleanup() {
    _activeDownloadVersion = null;
    _broadcastController?.close();
    _broadcastController = null;
  }

  /// Cancel an in-progress download and clean up partial file.
  Future<void> cancelDownload() async {
    _cancelToken?.cancel('User cancelled');
    _cancelToken = null;
    _lastProgress = null;
    if (_activeDownloadVersion != null) {
      final versionToClean = _activeDownloadVersion!;
      _cleanup();
      try {
        final dir = await _otaDir(versionToClean);
        // Clean partial, chunk, and complete files
        for (final name in ['update.apk.chunk', 'update.apk.partial', 'update.apk']) {
          final f = File('${dir.path}/$name');
          if (await f.exists()) await f.delete();
        }
      } catch (_) {
        // Errors during cleanup can be ignored.
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
    return File('${dir.path}/update.apk').exists();
  }

  /// Get the cached APK file path if it exists, null otherwise.
  Future<String?> cachedFilePath(String version) async {
    final dir = await _otaDir(version);
    final file = File('${dir.path}/update.apk');
    return await file.exists() ? file.path : null;
  }

  /// Delete all cached APKs.
  Future<void> clearCache() async {
    try {
      final base = await _otaBaseDir();
      if (await base.exists()) {
        await base.delete(recursive: true);
      }
    } catch (_) {}
  }

  /// Get total cache size as formatted string.
  Future<String> get cacheSize async {
    try {
      final base = await _otaBaseDir();
      if (!await base.exists()) return '0 B';
      int total = 0;
      await for (final entity in base.list(recursive: true)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return formatBytes(total);
    } catch (_) {
      return '0 B';
    }
  }

  // ─── FORCE UPDATE PERSISTENCE ────────────────────────────────────
  // Like Telegram's SharedConfig.pendingAppUpdate — survives app kill.

  /// Persist a force update so it re-shows after app restart.
  Future<void> savePendingUpdate(UpdateInfo info) async {
    try {
      _currentVersion ??= (await PackageInfo.fromPlatform()).version;
      final base = await _otaBaseDir();
      if (!await base.exists()) {
        await base.create(recursive: true);
      }
      final file = File('${base.path}/pending_update.json');
      await file.writeAsString(jsonEncode({
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
    } catch (_) {
      // Best-effort persistence — don't crash the app if disk write fails.
    }
  }

  /// Load persisted force update. Returns null if none or stale.
  Future<UpdateInfo?> loadPendingUpdate() async {
    _currentVersion ??= (await PackageInfo.fromPlatform()).version;
    final file = File('${(await _otaBaseDir()).path}/pending_update.json');
    if (!await file.exists()) return null;
    try {
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      // Stale: app was updated since we saved this
      if (data['checked_at_version'] != _currentVersion) {
        await file.delete();
        return null;
      }
      return UpdateInfo.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  /// Clear persisted force update (called on 10-tap escape or server says none).
  Future<void> clearPendingUpdate() async {
    try {
      final file = File('${(await _otaBaseDir()).path}/pending_update.json');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  // ─── COOLDOWN PERSISTENCE ────────────────────────────────────────
  // Like AyuGram's ExteraConfig.lastUpdateCheckTime in SharedPreferences.
  // Survives app restart so we don't spam the server on every cold start.

  /// Save the last check timestamp to disk.
  Future<void> saveLastCheckTime(int timestampMs) async {
    try {
      final base = await _otaBaseDir();
      if (!await base.exists()) {
        await base.create(recursive: true);
      }
      await File('${base.path}/last_check.txt').writeAsString('$timestampMs');
    } catch (_) {
      // Best-effort — don't crash the app if disk write fails.
    }
  }

  /// Load the last check timestamp from disk. Returns 0 if none.
  Future<int> loadLastCheckTime() async {
    final file = File('${(await _otaBaseDir()).path}/last_check.txt');
    if (!await file.exists()) return 0;
    try {
      return int.parse((await file.readAsString()).trim());
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
    final base = await _otaBaseDir();
    final dir = Directory('${base.path}/$safe');
    // Belt-and-suspenders: verify resolved path is still under our base dir
    final resolved = dir.uri.normalizePath().toFilePath();
    if (!resolved.startsWith(base.uri.normalizePath().toFilePath())) {
      throw ArgumentError('Version string resolved outside OTA directory: $version');
    }
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Delete cached APKs for versions other than [keepVersion].
  Future<void> _cleanOldVersions(String keepVersion) async {
    final base = await _otaBaseDir();
    if (!await base.exists()) return;
    final safe = keepVersion.replaceAll(RegExp(r'[^a-zA-Z0-9._\-+]'), '_');
    await for (final entity in base.list()) {
      if (entity is Directory && entity.path.split('/').last != safe) {
        try {
          await entity.delete(recursive: true);
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
