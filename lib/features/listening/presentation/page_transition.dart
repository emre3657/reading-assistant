import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';

import 'reading_preferences.dart';

Duration pageTransitionDuration(PageAnimationEffect effect) => switch (effect) {
  PageAnimationEffect.fade => const Duration(milliseconds: 500),
  PageAnimationEffect.slide => const Duration(milliseconds: 500),
  PageAnimationEffect.turn => const Duration(milliseconds: 800),
};

Future<ui.Image> capturePage(GlobalKey key, double pixelRatio) async {
  await WidgetsBinding.instance.endOfFrame;
  final boundary = key.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary || !boundary.attached) {
    throw StateError('Page capture boundary is unavailable.');
  }
  return boundary.toImage(pixelRatio: pixelRatio.clamp(1.0, 2.0));
}

class ReadingPageTransition extends StatelessWidget {
  const ReadingPageTransition({
    super.key,
    required this.animation,
    required this.effect,
    required this.forward,
    required this.previous,
    required this.child,
    this.snapshot,
    this.paperColor,
  });

  final Animation<double> animation;
  final PageAnimationEffect effect;
  final bool forward;
  final Widget? previous;
  final Widget child;
  final ui.Image? snapshot;
  final Color? paperColor;

  @override
  Widget build(BuildContext context) {
    if (previous == null) return child;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, current) {
        final t = Curves.easeInOut.transform(animation.value);
        final direction = forward ? 1.0 : -1.0;
        Widget layer(Widget page, bool old) {
          switch (effect) {
            case PageAnimationEffect.fade:
              return Opacity(opacity: old ? 1 - t : t, child: page);
            case PageAnimationEffect.slide:
              return FractionalTranslation(
                translation: Offset(
                  0,
                  old ? -direction * t : direction * (1 - t),
                ),
                child: page,
              );
            case PageAnimationEffect.turn:
              return page;
          }
        }

        return ClipRect(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Stack(
                fit: StackFit.expand,
                children: effect == PageAnimationEffect.turn && snapshot != null
                    ? [
                        current!,
                        CustomPaint(
                          painter: _PageCurlPainter(
                            image: snapshot!,
                            progress: t,
                            forward: forward,
                            paperColor:
                                paperColor ??
                                Theme.of(context).colorScheme.surface,
                          ),
                        ),
                      ]
                    : [layer(previous!, true), layer(current!, false)],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PageCurlPainter extends CustomPainter {
  _PageCurlPainter({
    required this.image,
    required this.progress,
    required this.forward,
    required this.paperColor,
  });

  final ui.Image image;
  final double progress;
  final bool forward;
  final Color paperColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || progress >= 1) return;
    final width = size.width;
    final height = size.height;
    final fold = width * (1 - progress);
    final radius = math.min(width * 0.12, 48.0) * math.sin(math.pi * progress);
    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();

    Rect horizontal(double left, double right) => Rect.fromLTRB(
      forward ? left : width - right,
      0,
      forward ? right : width - left,
      height,
    );
    Rect source(double left, double right) {
      final rect = horizontal(left, right);
      return Rect.fromLTRB(
        rect.left / width * imageWidth,
        0,
        rect.right / width * imageWidth,
        imageHeight,
      );
    }

    if (radius > 0) {
      final shadow = horizontal(fold, math.min(width, fold + radius * 2));
      canvas.drawRect(
        shadow,
        Paint()
          ..shader = LinearGradient(
            begin: forward ? Alignment.centerLeft : Alignment.centerRight,
            end: forward ? Alignment.centerRight : Alignment.centerLeft,
            colors: [
              Colors.black.withValues(
                alpha: 0.24 * math.sin(math.pi * progress),
              ),
              Colors.transparent,
            ],
          ).createShader(shadow),
      );
    }
    if (fold > 0) {
      canvas.drawImageRect(
        image,
        source(0, fold),
        horizontal(0, fold),
        Paint(),
      );
    }
    if (radius <= 0.01) return;

    // Project successive image strips onto the front half of a cylinder.
    // Mirroring coordinates rather than the canvas keeps the text readable.
    const strips = 32;
    final extent = math.min(width - fold, radius * math.pi / 2);
    for (var i = 0; i < strips; i++) {
      final start = extent * i / strips;
      final end = extent * (i + 1) / strips;
      final left = fold + radius * math.sin(start / radius);
      final right = fold + radius * math.sin(end / radius);
      if (right <= left) continue;
      final rect = horizontal(left, right);
      canvas.drawImageRect(
        image,
        source(fold + start, fold + end),
        rect,
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = Colors.black.withValues(
            alpha: 0.18 * (start / (radius * math.pi / 2)),
          ),
      );
    }

    final backWidth = math.min(radius * 0.38, fold);
    if (backWidth > 0) {
      final back = horizontal(fold - backWidth, fold);
      canvas.drawRect(
        back,
        Paint()
          ..shader = LinearGradient(
            begin: forward ? Alignment.centerLeft : Alignment.centerRight,
            end: forward ? Alignment.centerRight : Alignment.centerLeft,
            colors: [
              Color.alphaBlend(
                Colors.black.withValues(alpha: 0.18),
                paperColor,
              ),
              paperColor,
              Color.alphaBlend(
                Colors.white.withValues(alpha: 0.16),
                paperColor,
              ),
            ],
          ).createShader(back),
      );
    }
  }

  @override
  bool shouldRepaint(_PageCurlPainter oldDelegate) =>
      image != oldDelegate.image ||
      progress != oldDelegate.progress ||
      forward != oldDelegate.forward ||
      paperColor != oldDelegate.paperColor;
}
