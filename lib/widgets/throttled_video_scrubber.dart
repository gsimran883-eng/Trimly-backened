import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

Duration scrubPositionForOffset({
  required double dx,
  required double width,
  required Duration duration,
}) {
  if (width <= 0 || duration.inMilliseconds <= 0) {
    return Duration.zero;
  }

  final ratio = (dx / width).clamp(0.0, 1.0);
  return Duration(
    milliseconds: (duration.inMilliseconds * ratio).round(),
  );
}

class ThrottledVideoScrubber extends StatefulWidget {
  final VideoPlayerController controller;
  final double height;
  final List<int> markerMs;
  final Color playedColor;
  final Color bufferedColor;
  final Color backgroundColor;
  final Color markerColor;
  final Duration dragSnapInterval;

  const ThrottledVideoScrubber({
    super.key,
    required this.controller,
    this.height = 16,
    this.markerMs = const [],
    this.playedColor = const Color(0xFF2563EB),
    this.bufferedColor = Colors.white24,
    this.backgroundColor = Colors.white10,
    this.markerColor = const Color(0xFFFFD84D),
    this.dragSnapInterval = const Duration(milliseconds: 250),
  });

  @override
  State<ThrottledVideoScrubber> createState() => _ThrottledVideoScrubberState();
}

class _ThrottledVideoScrubberState extends State<ThrottledVideoScrubber> {
  static const Duration _seekThrottle = Duration(milliseconds: 50);

  Timer? _scrubTimer;
  Timer? _hapticThrottle;
  Duration? _pendingSeek;
  Duration? _previewPosition;
  bool _isScrubbing = false;

  @override
  void dispose() {
    _scrubTimer?.cancel();
    _hapticThrottle?.cancel();
    super.dispose();
  }

  void _pulseScrubHaptic() {
    if (_hapticThrottle?.isActive ?? false) {
      return;
    }
    HapticFeedback.selectionClick();
    _hapticThrottle = Timer(_seekThrottle, () {});
  }

  void _queueSeek(Duration position) {
    _pendingSeek = _snapForDrag(position);
    if (_scrubTimer?.isActive ?? false) {
      return;
    }

    _scrubTimer = Timer(_seekThrottle, _flushQueuedSeek);
  }

  Duration _snapForDrag(Duration position) {
    final intervalMs = widget.dragSnapInterval.inMilliseconds;
    if (intervalMs <= 0) {
      return position;
    }
    final snappedMs = (position.inMilliseconds / intervalMs).round() * intervalMs;
    final durationMs = widget.controller.value.duration.inMilliseconds;
    return Duration(milliseconds: snappedMs.clamp(0, durationMs));
  }

  Future<void> _flushQueuedSeek() async {
    final position = _pendingSeek;
    _pendingSeek = null;
    if (position == null) {
      return;
    }
    await widget.controller.seekTo(position);
  }

  Future<void> _finishSeek(Duration position) async {
    _scrubTimer?.cancel();
    _pendingSeek = null;
    HapticFeedback.lightImpact();
    await widget.controller.seekTo(position);
    if (mounted) {
      setState(() {
        _isScrubbing = false;
        _previewPosition = null;
      });
    }
  }

  Duration _positionForLocalDx(double dx, double width) {
    return scrubPositionForOffset(
      dx: dx,
      width: width,
      duration: widget.controller.value.duration,
    );
  }

  void _previewAndQueue(Duration position) {
    _pulseScrubHaptic();
    setState(() {
      _isScrubbing = true;
      _previewPosition = position;
    });
    _queueSeek(position);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('throttled-video-scrubber'),
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.max(1.0, constraints.maxWidth);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              final position = _positionForLocalDx(
                details.localPosition.dx,
                width,
              );
              _finishSeek(position);
            },
            onHorizontalDragStart: (details) {
              _previewAndQueue(
                _positionForLocalDx(details.localPosition.dx, width),
              );
            },
            onHorizontalDragUpdate: (details) {
              _previewAndQueue(
                _positionForLocalDx(details.localPosition.dx, width),
              );
            },
            onHorizontalDragEnd: (_) {
              final position = _pendingSeek ?? _previewPosition;
              if (position != null) {
                _finishSeek(position);
              }
            },
            onHorizontalDragCancel: () {
              _scrubTimer?.cancel();
              _hapticThrottle?.cancel();
              _pendingSeek = null;
              setState(() {
                _isScrubbing = false;
                _previewPosition = null;
              });
            },
            child: AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) {
                final durationMs =
                    widget.controller.value.duration.inMilliseconds;
                final positionMs = (_isScrubbing
                            ? _previewPosition
                            : widget.controller.value.position)
                        ?.inMilliseconds ??
                    0;
                final progress = durationMs <= 0
                    ? 0.0
                    : (positionMs / durationMs).clamp(0.0, 1.0);
                final buffered =
                    widget.controller.value.buffered.isEmpty || durationMs <= 0
                        ? 0.0
                        : (widget.controller.value.buffered.last.end
                                    .inMilliseconds /
                                durationMs)
                            .clamp(0.0, 1.0);

                return Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: widget.backgroundColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: buffered,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: widget.bufferedColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: progress,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: widget.playedColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Positioned(
                      left: (width * progress).clamp(0.0, width - 18),
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: widget.playedColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: widget.playedColor.withValues(alpha: 0.34),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                    ...widget.markerMs.map((markerMs) {
                      final ratio = durationMs <= 0
                          ? 0.0
                          : (markerMs / durationMs).clamp(0.0, 1.0);
                      return Positioned(
                        left: width * ratio,
                        child: Container(
                          width: 2,
                          height: math.min(widget.height, 12),
                          color: widget.markerColor,
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}
