import 'dart:async';

import 'package:flutter/material.dart';

import 'models.dart';
import 'update_service.dart';

// ─── M3 EXPRESSIVE MOTION CURVES ────────────────────────────────────
// From Material 3 Expressive spec — spring physics as cubic-bezier.
// Spatial springs: for position/size changes (bouncy overshoot).
// Effects springs: for color/opacity changes (subtle).

const _spatialFast = Cubic(0.42, 1.85, 0.21, 0.90);     // 350ms
const _spatialDefault = Cubic(0.38, 1.21, 0.22, 1.00);   // 500ms
const _effectsFast = Cubic(0.31, 0.94, 0.34, 1.00);      // 150ms
const _effectsDefault = Cubic(0.34, 0.80, 0.34, 1.00);   // 200ms

// ─── SOFT UPDATE BOTTOM SHEET ───────────────────────────────────────
// Dismissible. User can tap "Later". Like AyuGram's UpdaterBottomSheet.

class SoftUpdateSheet extends StatefulWidget {
  final UpdateInfo info;
  final UpdateService service;

  const SoftUpdateSheet({
    super.key,
    required this.info,
    required this.service,
  });

  static Future<void> show(BuildContext context, UpdateInfo info, UpdateService service) {
    return showModalBottomSheet(
      context: context,
      isDismissible: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => SoftUpdateSheet(info: info, service: service),
    );
  }

  @override
  State<SoftUpdateSheet> createState() => _SoftUpdateSheetState();
}

class _SoftUpdateSheetState extends State<SoftUpdateSheet> {
  bool _downloading = false;
  double _progress = 0;
  String? _filePath;
  String? _error;
  StreamSubscription<DownloadProgress>? _downloadSub;

  @override
  void dispose() {
    _downloadSub?.cancel();
    super.dispose();
  }

  void _startDownload() {
    setState(() {
      _downloading = true;
      _error = null;
    });

    _downloadSub = widget.service
        .download(widget.info.downloadUrl!, widget.info.latestVersion!, sha256Checksum: widget.info.sha256)
        .listen(
      (p) {
        if (!mounted) return;
        setState(() {
          _progress = p.percent;
          if (p.isComplete) {
            _filePath = p.filePath;
            _downloading = false;
          }
          if (p.error != null) {
            _error = p.error;
            _downloading = false;
          }
        });
      },
    );
  }

  void _cancelDownload() {
    widget.service.cancelDownload();
    _downloadSub?.cancel();
    setState(() {
      _downloading = false;
      _progress = 0;
    });
  }

  void _install() {
    if (_filePath != null) {
      UpdateService.install(_filePath!);
    }
  }

  String get _buttonLabel {
    if (_filePath != null) return 'Install now';
    if (_error != null) return 'Retry';
    final size = widget.info.fileSize != null ? ' (${formatBytes(widget.info.fileSize!)})' : '';
    return 'Download update$size';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isIdle = !_downloading && _filePath == null;
    final version = _stripVersionPrefix(widget.info.latestVersion);

    return PopScope(
      // Block dismiss during download (like Telegram's setCanceledOnTouchOutside(false))
      canPop: !_downloading,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Update available',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  // Version + size on one line (like Telegram's subtitle)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: version),
                        if (widget.info.fileSize != null)
                          TextSpan(
                            text: '  ·  ${formatBytes(widget.info.fileSize!)}',
                            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5)),
                          ),
                      ],
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),

                  if (widget.info.changelog != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      'What\'s new',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    // Changelog with gradient scroll fade (like Telegram's gradientDrawable)
                    _ScrollFadeBox(
                      maxHeight: 200,
                      child: Text(
                        widget.info.changelog!,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],

                  if (widget.info.message != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      widget.info.message!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.primary,
                      ),
                    ),
                  ],

                  // Animated error text
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: _effectsDefault,
                    child: _error != null
                        ? Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _error!,
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),

                  const SizedBox(height: 20),

                  // Action button — progress inside button (like Telegram's BlockingUpdateView)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: _ButtonWithShimmer(
                      showShimmer: isIdle,
                      child: FilledButton(
                        onPressed: _downloading
                            ? _cancelDownload
                            : _filePath != null
                                ? _install
                                : _startDownload,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _InButtonProgress(
                          downloading: _downloading,
                          progress: _progress,
                          label: _buttonLabel,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),
                  // "Later" button — accent text, no background (like Telegram's scheduleButton)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 350),
                    curve: _spatialFast,
                    child: _downloading
                        ? const SizedBox.shrink()
                        : SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: TextButton(
                              onPressed: () => Navigator.pop(context),
                              style: TextButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: Text(
                                'Later',
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: cs.primary,
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── FORCE UPDATE SCREEN ────────────────────────────────────────────
// Fullscreen. Non-dismissible. Like Telegram's BlockingUpdateView.
// Back button disabled. Only way out is to install.

class ForceUpdateScreen extends StatefulWidget {
  final UpdateInfo info;
  final UpdateService service;

  const ForceUpdateScreen({
    super.key,
    required this.info,
    required this.service,
  });

  @override
  State<ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends State<ForceUpdateScreen> {
  bool _downloading = false;
  double _progress = 0;
  String? _filePath;
  String? _error;
  int _tapCount = 0;
  StreamSubscription<DownloadProgress>? _downloadSub;

  @override
  void initState() {
    super.initState();
    // Like Telegram's BlockingUpdateView.show(check=true):
    // Re-check server — if the update is no longer forced, auto-dismiss.
    _recheckServer();
  }

  /// Re-check the server to see if the force update is still required.
  /// Telegram does this so the server can un-block clients remotely.
  Future<void> _recheckServer() async {
    try {
      final fresh = await widget.service.check();
      if (!mounted) return;
      if (fresh.status != UpdateStatus.hard) {
        await widget.service.clearPendingUpdate();
        if (mounted) Navigator.of(context).pop();
      }
    } catch (_) {
      // Network error — stay on the force update screen (safe default)
    }
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    super.dispose();
  }

  void _startDownload() {
    setState(() {
      _downloading = true;
      _error = null;
    });

    _downloadSub = widget.service
        .download(widget.info.downloadUrl!, widget.info.latestVersion!, sha256Checksum: widget.info.sha256)
        .listen(
      (p) {
        if (!mounted) return;
        setState(() {
          _progress = p.percent;
          if (p.isComplete) {
            _filePath = p.filePath;
            _downloading = false;
          }
          if (p.error != null) {
            _error = p.error;
            _downloading = false;
          }
        });
      },
    );
  }

  void _cancelDownload() {
    widget.service.cancelDownload();
    _downloadSub?.cancel();
    setState(() {
      _downloading = false;
      _progress = 0;
    });
  }

  void _install() {
    if (_filePath != null) {
      UpdateService.install(_filePath!);
    }
  }

  String get _buttonLabel {
    if (_filePath != null) return 'Install now';
    if (_error != null) return 'Retry';
    final size = widget.info.fileSize != null ? ' (${formatBytes(widget.info.fileSize!)})' : '';
    return 'Update$size';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isIdle = !_downloading && _filePath == null;
    final version = _stripVersionPrefix(widget.info.latestVersion);

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // Tap 10 times to bypass (dev escape hatch, like Telegram's BlockingUpdateView)
                GestureDetector(
                  onTap: () {
                    _tapCount++;
                    if (_tapCount >= 10) {
                      widget.service.clearPendingUpdate();
                      Navigator.of(context).pop();
                    }
                  },
                  // Larger icon like Telegram's 108dp Lottie
                  child: Icon(
                    Icons.system_update_rounded,
                    size: 108,
                    color: cs.primary,
                  ),
                ),

                const SizedBox(height: 24),
                Text(
                  'Update required',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                // Version subtitle (like Telegram's version + size line)
                Text(
                  '$version${widget.info.fileSize != null ? '  ·  ${formatBytes(widget.info.fileSize!)}' : ''}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.info.message ?? 'Please update to continue using the app.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.7),
                  ),
                ),

                if (widget.info.changelog != null) ...[
                  const SizedBox(height: 20),
                  // Changelog with gradient scroll fade (like Telegram's top/bottom gradients)
                  _ScrollFadeBox(
                    maxHeight: 180,
                    child: Text(
                      widget.info.changelog!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],

                // Animated error text
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: _effectsDefault,
                  child: _error != null
                      ? Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            _error!,
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),

                const Spacer(),

                // Action button — in-button progress (like Telegram's radialProgress crossfade)
                // Telegram clamps button to 320dp max on wide screens
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: _ButtonWithShimmer(
                        showShimmer: isIdle,
                        child: FilledButton(
                          onPressed: _downloading
                              ? _cancelDownload
                              : _filePath != null
                                  ? _install
                                  : _startDownload,
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _InButtonProgress(
                            downloading: _downloading,
                            progress: _progress,
                            label: _buttonLabel,
                            textStyle: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const Spacer(flex: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── MAINTENANCE SCREEN ─────────────────────────────────────────────
// Fullscreen. App is offline.

class MaintenanceScreen extends StatelessWidget {
  final UpdateInfo info;

  const MaintenanceScreen({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.construction_rounded,
                    size: 108,
                    color: cs.tertiary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Under maintenance',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    info.maintenanceMessage ?? 'The app is currently under maintenance. Please try again later.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── IN-BUTTON PROGRESS ─────────────────────────────────────────────
// Like Telegram's BlockingUpdateView: button text crossfades to circular
// progress indicator, then back to "Install" when done.
// Crossfade: 150ms (Telegram uses 150ms with linear interpolator).

class _InButtonProgress extends StatelessWidget {
  final bool downloading;
  final double progress;
  final String label;
  final TextStyle? textStyle;

  const _InButtonProgress({
    required this.downloading,
    required this.progress,
    required this.label,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      switchInCurve: _effectsFast,
      switchOutCurve: _effectsFast,
      transitionBuilder: (child, animation) {
        // Telegram uses scale 0.1↔1.0 for dramatic crossfade between text and spinner
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.1, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: _effectsFast),
            ),
            child: child,
          ),
        );
      },
      child: downloading
          ? Center(
              key: const ValueKey('progress'),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  value: progress > 0 ? progress : null,
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
            )
          : Text(
              label,
              key: ValueKey(label),
              style: textStyle,
            ),
    );
  }
}

// ─── SCROLL FADE BOX ────────────────────────────────────────────────
// Like Telegram's gradientDrawableTop/Bottom on BlockingUpdateView.
// Renders top and bottom gradient fades over scrollable content.

class _ScrollFadeBox extends StatelessWidget {
  final double maxHeight;
  final Widget child;

  const _ScrollFadeBox({
    required this.maxHeight,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ShaderMask(
        shaderCallback: (bounds) {
          return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: const [0.0, 0.06, 0.92, 1.0],
          ).createShader(bounds);
        },
        blendMode: BlendMode.dstIn,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: child,
        ),
      ),
    );
  }
}

// ─── BUTTON SHIMMER ─────────────────────────────────────────────────
// Matches Telegram's CellFlickerDrawable:
// - Flat horizontal sweep (no diagonal)
// - 1200ms sweep + ~240ms pause (repeatProgress 1.2)
// - Fill layer + brighter outline stroke
// - 160dp-wide gradient band, enters/exits off-screen
// Now theme-aware: uses primary color tint instead of hardcoded white.

class _ButtonWithShimmer extends StatefulWidget {
  final Widget child;
  final bool showShimmer;

  const _ButtonWithShimmer({required this.child, required this.showShimmer});

  @override
  State<_ButtonWithShimmer> createState() => _ButtonWithShimmerState();
}

class _ButtonWithShimmerState extends State<_ButtonWithShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _repeatProgress = 1.2;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1440),
    );
    if (widget.showShimmer) _controller.repeat();
  }

  @override
  void didUpdateWidget(_ButtonWithShimmer old) {
    super.didUpdateWidget(old);
    if (widget.showShimmer && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.showShimmer && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showShimmer) return widget.child;

    // Theme-aware shimmer: use onPrimary color (works in both light/dark mode)
    final shimmerColor = Theme.of(context).colorScheme.onPrimary;

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final raw = _controller.value * _repeatProgress;
        final progress = raw.clamp(0.0, 1.0);
        final pos = progress * 4.0 - 1.5;

        return Stack(
          fit: StackFit.expand,
          children: [
            child!,
            // Fill layer (alpha ~25%)
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(pos - 0.4, 0),
                        end: Alignment(pos + 0.4, 0),
                        colors: [
                          shimmerColor.withValues(alpha: 0),
                          shimmerColor.withValues(alpha: 0.25),
                          shimmerColor.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Outline layer (alpha ~80%)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ShimmerOutlinePainter(
                    progress: progress,
                    pos: pos,
                    color: shimmerColor,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ShimmerOutlinePainter extends CustomPainter {
  final double progress;
  final double pos;
  final Color color;

  _ShimmerOutlinePainter({required this.progress, required this.pos, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(12),
    );

    final gradient = LinearGradient(
      begin: Alignment(pos - 0.4, 0),
      end: Alignment(pos + 0.4, 0),
      colors: [
        color.withValues(alpha: 0),
        color.withValues(alpha: 0.8),
        color.withValues(alpha: 0),
      ],
    );

    final paint = Paint()
      ..shader = gradient.createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawRRect(rect, paint);
  }

  @override
  bool shouldRepaint(_ShimmerOutlinePainter old) =>
      old.progress != progress;
}

// ─── HELPERS ─────────────────────────────────────────────────────────

/// Strip "v" or "V" prefix from version strings for display.
String _stripVersionPrefix(String? version) {
  if (version == null) return '';
  final v = version.trim();
  if (v.startsWith('v') || v.startsWith('V')) return v.substring(1);
  return v;
}
