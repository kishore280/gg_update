/// Status returned by the update server.
enum UpdateStatus {
  none,
  soft,
  hard,
  maintenance;

  static UpdateStatus fromString(String? value) {
    if (value == null) return UpdateStatus.none;
    final lower = value.toLowerCase();
    return UpdateStatus.values.firstWhere(
      (e) => e.name == lower,
      orElse: () => UpdateStatus.none,
    );
  }
}

/// Response from the update check endpoint.
class UpdateInfo {
  final UpdateStatus status;
  final String? latestVersion;
  final String? minVersion;
  final String? downloadUrl;
  final int? fileSize;
  final String? sha256;
  final String? changelog;
  final String? message;
  final String? maintenanceMessage;

  const UpdateInfo({
    required this.status,
    this.latestVersion,
    this.minVersion,
    this.downloadUrl,
    this.fileSize,
    this.sha256,
    this.changelog,
    this.message,
    this.maintenanceMessage,
  });

  factory UpdateInfo.none() => const UpdateInfo(status: UpdateStatus.none);

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      status: UpdateStatus.fromString(json['status'] as String?),
      latestVersion: json['latest_version'] as String?,
      minVersion: json['min_version'] as String?,
      downloadUrl: json['download_url'] as String?,
      fileSize: json['file_size'] as int?,
      sha256: json['sha256'] as String?,
      changelog: json['changelog'] as String?,
      message: json['message'] as String?,
      maintenanceMessage: json['maintenance_message'] as String?,
    );
  }
}

/// Download progress events.
class DownloadProgress {
  final int received;
  final int total;
  final bool isComplete;
  final String? filePath;
  final String? error;

  const DownloadProgress({
    required this.received,
    required this.total,
    this.isComplete = false,
    this.filePath,
    this.error,
  });

  double get percent => total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
  String get percentText => '${(percent * 100).toStringAsFixed(0)}%';
}

/// Format byte count as human-readable string.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
