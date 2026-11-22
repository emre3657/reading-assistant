import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const startupBackground = Color(0xff034a4a);
const startupInk = Color(0xfffbf3e6);
const introDuration = Duration(milliseconds: 4000);

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _animation;
  bool _started = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animation = AnimationController(vsync: this, duration: introDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _finish();
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _finish();
      });
    } else if (!_started) {
      _started = true;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle == null || lifecycle == AppLifecycleState.resumed) {
        _animation.forward();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_finished) return;
    if (state == AppLifecycleState.resumed) {
      if (_started && !MediaQuery.disableAnimationsOf(context)) {
        _animation.forward();
      }
    } else {
      _animation.stop(canceled: false);
    }
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _animation.stop();
    widget.onComplete();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: startupBackground,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _finish();
        },
        child: Scaffold(
          backgroundColor: startupBackground,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: TextButton(
                      onPressed: _finish,
                      style: TextButton.styleFrom(
                        foregroundColor: startupInk,
                        minimumSize: const Size(64, 48),
                      ),
                      child: const Text('Atla'),
                    ),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final artworkWidth = math.min(
                        math.max(0.0, constraints.maxWidth - 40),
                        340.0,
                      );
                      final artworkHeight = math.min(
                        artworkWidth * 0.76,
                        260.0,
                      );

                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ExcludeSemantics(
                                  child: SizedBox(
                                    width: artworkWidth,
                                    height: artworkHeight,
                                    child: CustomPaint(
                                      painter: _BookPainter(_animation),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  'Okuma Asistanı',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        color: startupInk,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BookPainter extends CustomPainter {
  _BookPainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  double get progress => animation.value;

  double _phase(double start, double end) => Curves.easeInOut.transform(
    ((progress - start) / (end - start)).clamp(0.0, 1.0),
  );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final waves = _phase(0.64, 0.95);
    final unit = math.min(size.width / 2.8, size.height / 2.2);

    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(unit);

    // Ses dalgaları belirirken toplam çizimin merkezini dengeler.
    canvas.translate(-0.25 * waves, 0);
    final open = _phase(0.08, 0.52);
    final lines = _phase(0.38, 0.7);
    final shadow = Paint()..color = const Color(0x33000000);
    canvas.drawOval(const Rect.fromLTWH(-0.95, 0.64, 1.9, 0.14), shadow);
    final closed = 1 - open;
    final closedCover = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-0.43, -0.7, 0.86, 1.33),
      const Radius.circular(0.06),
    );
    canvas.drawRRect(
      closedCover,
      Paint()..color = const Color(0xffb6d3c7).withValues(alpha: closed),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-0.34, -0.65, 0.73, 1.23),
        const Radius.circular(0.035),
      ),
      Paint()..color = startupInk.withValues(alpha: closed),
    );
    final cover = Paint()
      ..color = const Color(0xffb6d3c7).withValues(alpha: open);
    final paper = Paint()..color = startupInk.withValues(alpha: open);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-0.08, -0.75, 0.83, 1.38),
        const Radius.circular(0.06),
      ),
      cover,
    );
    final right = Path()
      ..moveTo(0, -0.6)
      ..quadraticBezierTo(0.38, -0.82, 0.78, -0.72)
      ..lineTo(0.78, 0.48)
      ..quadraticBezierTo(0.38, 0.38, 0, 0.61)
      ..close();
    canvas.drawPath(right, paper);
    if (open > 0) {
      canvas.save();
      canvas.scale(open, 1);
      final left = Path()
        ..moveTo(0, -0.6)
        ..quadraticBezierTo(-0.38, -0.82, -0.78, -0.72)
        ..lineTo(-0.78, 0.48)
        ..quadraticBezierTo(-0.38, 0.38, 0, 0.61)
        ..close();
      canvas.drawPath(left, paper);
      canvas.restore();
      for (var i = 0; i < 3; i++) {
        final turn = (math.sin((open * 3 - i * 0.3) * math.pi) * (1 - open))
            .clamp(0.0, 1.0);
        final page = Path()
          ..moveTo(0, -0.6)
          ..quadraticBezierTo(-turn * 0.65, -0.83, -turn * 0.72, -0.7)
          ..lineTo(-turn * 0.72, 0.47)
          ..quadraticBezierTo(-turn * 0.3, 0.42, 0, 0.61);
        canvas.drawPath(
          page,
          Paint()
            ..color = const Color(0xffd5e0d3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.025,
        );
      }
    }
    canvas.drawLine(
      const Offset(0, -0.6),
      const Offset(0, 0.61),
      Paint()
        ..color = startupBackground.withValues(alpha: 0.7 * open)
        ..strokeWidth = 0.025,
    );
    final linePaint = Paint()
      ..color = startupBackground.withValues(alpha: lines * 0.7)
      ..strokeWidth = 0.035
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = -0.38 + i * 0.17;
      canvas.drawLine(
        Offset(0.14, y),
        Offset(0.14 + 0.43 * lines, y - 0.035),
        linePaint,
      );
    }
    final wavePaint = Paint()
      ..color = startupInk.withValues(alpha: waves)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.045
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 2; i++) {
      final y = 0.03 + i * 0.16;
      final wave = Path()
        ..moveTo(0.78, y)
        ..cubicTo(
          0.95,
          y - 0.18 * waves,
          1.08,
          y + 0.18 * waves,
          1.28,
          y - 0.03,
        );
      canvas.drawPath(wave, wavePaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BookPainter oldDelegate) =>
      oldDelegate.animation != animation;
}
