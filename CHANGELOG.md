# Changelog

All notable changes to `gg_updater` will be documented in this file.

This project follows [Semantic Versioning](https://semver.org/).

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
