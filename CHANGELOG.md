# Changelog

All notable changes to `gg_updater` will be documented in this file.

This project follows [Semantic Versioning](https://semver.org/).

## [1.3.5] - 2026-03-23

### Fixed
- Copy `_dio.options.headers` to `_downloadDio` — downloads to auth-protected servers (401/403) now include Authorization, cookies, and other default headers from the caller's Dio instance

## [1.3.4] - 2026-03-23

### Fixed
- **SHA1 checksum mismatch after download** — root causes addressed:
  - Use dedicated `_downloadDio` (no interceptors) for file download; app's `LogInterceptor(responseBody: true)` can consume/corrupt response stream
  - Add `Accept-Encoding: identity` to disable gzip; server checksum is for raw bytes, compression causes mismatch
- Improve mismatch logging: include file size and expected/got hashes when available

## [1.3.3] - 2026-03-23

### Added
- `debugPrint` on checksum mismatch (download + cache restore) for logcat/console debugging

### Fixed
- Trim whitespace from sha1/sha256 from server (fixes mismatch when sha1_file has newline)

## [1.3.2] - 2026-03-23

### Added
- Native (Kotlin) checksum verification — uses MessageDigest for faster SHA1/SHA256 on Android

### Fixed
- "Checking..." state to prevent Download→Install flicker during cache verification

### Fixed
- Checksum verification in cache-restore path (Install Now) — previously trusted cached file without verifying

### Changed
- Extracted `_verifyChecksum` helper to avoid duplication; restore detailed "expected/got" error message

## [1.3.0] - 2026-03-23

### Added
- SHA1 checksum support as fallback when SHA256 unavailable
- Frappe endpoint: `sha1_file` (Attach) option to read SHA1 from uploaded file

## [1.2.0] - 2026-03-23

### Added
- GitHub Actions workflow for automatic releases on tag push

## [1.1.0] - 2026-03-23

### Added
- PackageInstaller session API for seamless installs
- HTTP Range header support for resumable downloads
- Download state persistence across UI lifecycle
- Shared download state mixin for consistent state management

### Fixed
- Security vulnerability: input validation and safe file I/O
- OOM risk from unbounded buffering during download
- Corrupt cache bug on interrupted downloads
- Race condition in `download()` and `cancelDownload()`
- Subscription leak and null safety issues
- FileProvider path resolution for Flutter documents directory
- Button sizing and spinner centering in update UI
- Kotlin lifecycle cleanup for Android plugin

### Changed
- Hardened file I/O across Dart and Kotlin layers

## [1.0.0] - 2026-03-01

### Added
- Initial release of `gg_updater` Flutter plugin
- Version check against remote server
- APK download with progress tracking
- Blocking and non-blocking update UI (Telegram-inspired)
- Shimmer effect matching Telegram's CellFlickerDrawable
- `active_release` control for server-side update management
- Android FileProvider integration for install
- Server example with Node.js/Express
