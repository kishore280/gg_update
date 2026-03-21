# gg_updater

In-app update system for sideloaded Flutter apps. **Check -> Download -> Install.**

Inspired by [AyuGram/exteraGram](https://github.com/AyuGram/AyuGram4A) and [Telegram for Android](https://github.com/DrKLO/Telegram)'s update systems -- but in Flutter.

## Features

- **Version check** from your own REST API (Frappe, Go, static JSON, anything)
- **In-app APK download** with progress bar and cancel (using dio)
- **SHA256 checksum** validation on downloads (optional, catches corrupted APKs)
- **Native APK install** via custom FileProvider + PackageInstaller
- **Soft update** -- dismissible bottom sheet with changelog
- **Force update** -- fullscreen blocking screen, persists across app restarts
- **Maintenance mode** -- app-wide block screen
- **Download caching** -- skips re-download if APK already exists
- **1-hour cooldown** -- doesn't spam the server
- **10-tap escape hatch** -- bypass force update during dev/QA
- **Permission handling** -- "Install unknown apps" settings redirect
- **No FileProvider conflicts** -- uses own `GgUpdaterFileProvider` subclass
- **Memory safe** -- WeakReference for Activity, stream subscription cleanup

## Setup

### 1. Add to pubspec.yaml

```yaml
dependencies:
  gg_updater:
    git:
      url: https://your-git-repo.com/gg_updater
```

### 2. That's it. No AndroidManifest edits needed.

The package bundles its own FileProvider, permissions, and provider paths.

## Usage

### One-liner (recommended)

```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    GgUpdater.checkAndPrompt(context,
      endpoint: 'https://your-server.com/api/method/check_update',
    );
  });
}
```

Done. It checks the server, compares versions, and shows:
- Nothing if up to date
- Bottom sheet if soft update available (with cancel + retry)
- Fullscreen block if force update required (persists across app kills)
- Maintenance screen if server says so

### With init (for multiple screens)

```dart
void main() {
  GgUpdater.init(
    endpoint: 'https://your-server.com/api/method/check_update',
    headers: {'Authorization': 'token xxx:yyy'},
  );
  runApp(MyApp());
}

// Then anywhere:
await GgUpdater.checkAndPrompt(context);
```

### Manual control

```dart
// Check without UI
final info = await GgUpdater.check();
print(info.status);        // none, soft, hard, maintenance
print(info.latestVersion); // "2.1.0"

// Download with progress + checksum verification
GgUpdater.service.download(
  info.downloadUrl!,
  info.latestVersion!,
  sha256Checksum: info.sha256,
).listen((p) {
  print('${p.percentText} downloaded');
  if (p.isComplete) {
    UpdateService.install(p.filePath!);
  }
  if (p.error != null) {
    print('Error: ${p.error}');
  }
});

// Cancel download
GgUpdater.service.cancelDownload();

// Cache management
await GgUpdater.clearCache();
print(await GgUpdater.service.cacheSize); // "12.3 MB"
```

## Server API

The package expects this JSON response from your endpoint:

```
GET /your/endpoint?platform=android&version=1.2.0
```

```json
{
  "status": "hard",
  "latest_version": "2.1.0",
  "min_version": "1.8.0",
  "download_url": "https://cdn.example.com/app-2.1.0.apk",
  "file_size": 45678901,
  "sha256": "a1b2c3d4e5f6...",
  "changelog": "- Fixed POS crash\n- Added offline mode",
  "message": "Critical security update required",
  "maintenance_message": null
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `status` | Yes | `none` \| `soft` \| `hard` \| `maintenance` |
| `latest_version` | For soft/hard | Semver string |
| `min_version` | For hard | Versions below this get force update |
| `download_url` | For soft/hard | Direct URL to APK file |
| `file_size` | No | Bytes, shown in UI |
| `sha256` | No | SHA256 hex hash for integrity check |
| `changelog` | No | Shown in update UI |
| `message` | No | Custom message per update type |
| `maintenance_message` | For maintenance | Shown on maintenance screen |

**Frappe users:** See `server/frappe_endpoint.py` for a ready-to-use endpoint + Single DocType schema.

## How it works

Based on AyuGram's UpdaterUtils.java + Telegram's BlockingUpdateView.java:

1. `dio.get()` hits your endpoint -> parses response -> returns `UpdateInfo`
2. `dio.download()` saves APK to `<app_docs>/ota_updates/<version>/update.apk`
3. If `sha256` provided, verifies checksum after download (deletes on mismatch)
4. If file already exists, skips download (cache hit)
5. Kotlin plugin: `GgUpdaterFileProvider.getUriForFile()` -> `Intent(ACTION_VIEW)` -> native installer
6. Checks `canRequestPackageInstalls()` on Android 8+ -> redirects to settings if needed
7. Force updates persist to `pending_update.json` -> re-shown after app restart (like Telegram's `pendingAppUpdate`)

## Architecture

```
lib/
  gg_updater.dart           # barrel export
  src/
    models.dart             # UpdateStatus, UpdateInfo, DownloadProgress
    update_service.dart     # check, download, install, cache, persistence
    apk_installer.dart      # MethodChannel bridge to Kotlin
    gg_updater.dart         # GgUpdater facade (one-liner API)
    ui.dart                 # SoftUpdateSheet, ForceUpdateScreen, MaintenanceScreen

android/
  src/main/kotlin/com/gg/updater/
    GgUpdaterPlugin.kt      # MethodChannel handler (install, permissions)
    GgUpdaterFileProvider.kt # Own FileProvider subclass (avoids conflicts)

server/
  frappe_endpoint.py        # Reference Frappe/ERPNext endpoint
```

## Credits

Update flow reverse-engineered from:
- [AyuGram4A](https://github.com/AyuGram/AyuGram4A) -- `UpdaterUtils.java`, `UpdaterBottomSheet.java`
- [exteraGram](https://github.com/exteraSquad/exteraGram) -- original update system
- [Telegram for Android](https://github.com/DrKLO/Telegram) -- `BlockingUpdateView.java`, `UpdateAppAlertDialog.java`

Patterns borrowed from pub.dev packages: `in_app_update`, `ota_update`, `install_plugin`, `r_upgrade`, `upgrader`.
