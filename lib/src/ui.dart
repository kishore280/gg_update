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
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)), // M3 Expressive: larger radius
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
    if (_downloading) return 'Cancel';
    if (_filePath != null) return 'Install now';
    if (_error != null) return 'Retry';
    return 'Download update';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIdle = !_downloading && _filePath == null;

    return Padding(
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
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
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
                Text(
                  'v${widget.info.latestVersion}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                if (widget.info.fileSize != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    formatBytes(widget.info.fileSize!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
                if (widget.info.changelog != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'What\'s new',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Text(
                        widget.info.changelog!,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ],
                if (widget.info.message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    widget.info.message!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],

                // Animated error text (M3 effects spring)
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: _effectsDefault,
                  child: _error != null
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _error!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),

                const SizedBox(height: 20),

                // Animated progress section (M3 spatial spring — bouncy)
                AnimatedSize(
                  duration: const Duration(milliseconds: 500),
                  curve: _spatialDefault,
                  child: _downloading
                      ? Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: _progress),
                                duration: const Duration(milliseconds: 350),
                                curve: _spatialFast,
                                builder: (_, value, __) => LinearProgressIndicator(value: value),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Downloading... ${(_progress * 100).toStringAsFixed(0)}%',
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),

                // Action button with shimmer + animated text
                SizedBox(
                  width: double.infinity,
                  child: _ButtonWithShimmer(
                    showShimmer: isIdle,
                    child: FilledButton(
                      onPressed: _downloading
                          ? _cancelDownload
                          : _filePath != null
                              ? _install
                              : _startDownload,
                      style: _downloading
                          ? FilledButton.styleFrom(backgroundColor: theme.colorScheme.error)
                          : null,
                      child: _AnimatedButtonText(label: _buttonLabel),
                    ),
                  ),
                ),

                const SizedBox(height: 8),
                AnimatedSize(
                  duration: const Duration(milliseconds: 350),
                  curve: _spatialFast,
                  child: _downloading
                      ? const SizedBox.shrink()
                      : SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Later'),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── FORCE UPDATE SCREEN ────────────────────────────────────────────
// Fullscreen. Non-dismissible. Like AyuGram's BlockingUpdateView.
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
  int _tapCount = 0; // AyuGram's 10-tap escape hatch
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
    if (_downloading) return 'Cancel';
    if (_filePath != null) return 'Install now';
    if (_error != null) return 'Retry';
    return 'Download update';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIdle = !_downloading && _filePath == null;

    return PopScope(
      canPop: false, // Block back button
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // Tap 10 times to bypass (dev escape hatch)
                GestureDetector(
                  onTap: () {
                    _tapCount++;
                    if (_tapCount >= 10) {
                      widget.service.clearPendingUpdate();
                      Navigator.of(context).pop();
                    }
                  },
                  child: Icon(
                    Icons.system_update,
                    size: 80,
                    color: theme.colorScheme.primary,
                  ),
                ),

                const SizedBox(height: 24),
                Text(
                  'Update required',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.info.message ?? 'Please update to version ${widget.info.latestVersion} to continue using the app.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),

                if (widget.info.changelog != null) ...[
                  const SizedBox(height: 20),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: SingleChildScrollView(
                      child: Text(
                        widget.info.changelog!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ],

                // Animated error text (M3 effects spring)
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: _effectsDefault,
                  child: _error != null
                      ? Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            _error!,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),

                const Spacer(),

                // Animated progress section (M3 spatial spring — bouncy)
                AnimatedSize(
                  duration: const Duration(milliseconds: 500),
                  curve: _spatialDefault,
                  child: _downloading
                      ? Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: _progress),
                                duration: const Duration(milliseconds: 350),
                                curve: _spatialFast,
                                builder: (_, value, __) => LinearProgressIndicator(value: value),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text('Downloading... ${(_progress * 100).toStringAsFixed(0)}%'),
                            const SizedBox(height: 20),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),

                // Action button with shimmer + animated text
                SizedBox(
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
                      style: _downloading
                          ? FilledButton.styleFrom(backgroundColor: theme.colorScheme.error)
                          : null,
                      child: _AnimatedButtonText(
                        label: _buttonLabel,
                        style: const TextStyle(fontSize: 16),
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
                    Icons.construction,
                    size: 80,
                    color: theme.colorScheme.tertiary,
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
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
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

// ─── ANIMATED BUTTON TEXT ────────────────────────────────────────────
// Telegram-style crossfade with M3 Expressive motion:
// old text slides up + fades out, new text slides up from below + fades in.
// Uses spatial spring for position (bouncy) and effects spring for opacity.

class _AnimatedButtonText extends StatelessWidget {
  final String label;
  final TextStyle? style;

  const _AnimatedButtonText({required this.label, this.style});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: _spatialFast,
      switchOutCurve: _effectsFast,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: _effectsFast),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.5),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: _spatialFast)),
            child: child,
          ),
        );
      },
      child: Text(
        label,
        key: ValueKey(label),
        style: style,
      ),
    );
  }
}

// ─── BUTTON SHIMMER ─────────────────────────────────────────────────
// Matches Telegram's CellFlickerDrawable:
// - Flat horizontal sweep (no diagonal)
// - 1200ms sweep + ~240ms pause (repeatProgress 1.2)
// - Fill layer (alpha 64) + brighter outline stroke (alpha 204)
// - 160dp-wide gradient band, enters/exits off-screen

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

  // repeatProgress > 1.0 adds a pause between sweeps (Telegram uses 1.2)
  static const _repeatProgress = 1.2;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      // Total cycle = sweep + pause. Sweep is 1200ms, full cycle = 1200 * 1.2 = 1440ms
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

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        // Map progress so shimmer only moves during 0..1/repeatProgress of the cycle
        final raw = _controller.value * _repeatProgress;
        final progress = raw.clamp(0.0, 1.0);

        // Sweep from off-screen left to off-screen right (like Telegram)
        // pos goes from -1.5 to 2.5 so the 160dp band fully enters and exits
        final pos = progress * 4.0 - 1.5;

        return Stack(
          children: [
            child!,
            // Fill layer (alpha 64)
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(pos - 0.4, 0),
                        end: Alignment(pos + 0.4, 0),
                        colors: const [
                          Color(0x00FFFFFF),
                          Color(0x40FFFFFF), // alpha 64
                          Color(0x00FFFFFF),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Outline layer (alpha 204) — brighter stroke on edges
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ShimmerOutlinePainter(
                    progress: progress,
                    pos: pos,
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

  _ShimmerOutlinePainter({required this.progress, required this.pos});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(100),
    );

    final gradient = LinearGradient(
      begin: Alignment(pos - 0.4, 0),
      end: Alignment(pos + 0.4, 0),
      colors: const [
        Color(0x00FFFFFF),
        Color(0xCCFFFFFF), // alpha 204
        Color(0x00FFFFFF),
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

