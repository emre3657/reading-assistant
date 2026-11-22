import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

class CropScreen extends StatefulWidget {
  const CropScreen({
    super.key,
    required this.image,
    required this.quarterTurns,
  });

  final ImageProvider image;
  final int quarterTurns;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  late final ImageProvider _preview = ResizeImage(
    widget.image,
    width: 1200,
    height: 1200,
    policy: ResizeImagePolicy.fit,
  );
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Size? _imageSize;
  Rect _bounds = const Rect.fromLTRB(0, 0, 1, 1);
  bool _error = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stream != null) return;
    _listener = ImageStreamListener(
      (info, _) {
        final size = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
        info.dispose();
        if (!mounted) return;
        setState(() {
          _imageSize = widget.quarterTurns.isOdd
              ? Size(size.height, size.width)
              : size;
          _error = false;
        });
      },
      onError: (error, stack) {
        debugPrint('Kırpma önizlemesi yüklenemedi: $error\n$stack');
        if (mounted) setState(() => _error = true);
      },
    );
    _stream = _preview.resolve(createLocalImageConfiguration(context));
    _stream!.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    super.dispose();
  }

  void _move(int horizontal, int vertical, Offset delta, Size size) {
    final minimumX = 1 / _imageSize!.width;
    final minimumY = 1 / _imageSize!.height;
    var left = _bounds.left;
    var top = _bounds.top;
    var right = _bounds.right;
    var bottom = _bounds.bottom;
    if (horizontal < 0) {
      left = (left + delta.dx / size.width).clamp(0, right - minimumX);
    } else if (horizontal > 0) {
      right = (right + delta.dx / size.width).clamp(left + minimumX, 1);
    }
    if (vertical < 0) {
      top = (top + delta.dy / size.height).clamp(0, bottom - minimumY);
    } else if (vertical > 0) {
      bottom = (bottom + delta.dy / size.height).clamp(top + minimumY, 1);
    }
    setState(() => _bounds = Rect.fromLTRB(left, top, right, bottom));
  }

  void _apply() {
    final size = _imageSize;
    if (size == null) return;
    double snap(double value, double pixels) =>
        (value * pixels).round() / pixels;
    final result = Rect.fromLTRB(
      snap(_bounds.left, size.width),
      snap(_bounds.top, size.height),
      snap(_bounds.right, size.width),
      snap(_bounds.bottom, size.height),
    );
    Navigator.of(context).pop(result);
  }

  Widget _handle(int horizontal, int vertical, Size size) {
    final x = horizontal < 0
        ? _bounds.left
        : horizontal > 0
        ? _bounds.right
        : _bounds.center.dx;
    final y = vertical < 0
        ? _bounds.top
        : vertical > 0
        ? _bounds.bottom
        : _bounds.center.dy;
    final label = [
      if (vertical < 0) 'Üst',
      if (vertical > 0) 'Alt',
      if (horizontal < 0) 'sol',
      if (horizontal > 0) 'sağ',
      if (horizontal == 0 || vertical == 0) 'kenar' else 'köşe',
    ].join(' ');
    return Positioned(
      left: x * size.width,
      top: y * size.height,
      child: Semantics(
        label: '$label kırpma tutamacı',
        onIncrease: () => _move(horizontal, vertical, const Offset(4, 4), size),
        onDecrease: () =>
            _move(horizontal, vertical, const Offset(-4, -4), size),
        child: GestureDetector(
          key: ValueKey('crop-handle-$horizontal-$vertical'),
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) =>
              _move(horizontal, vertical, details.delta, size),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.onPrimary,
                    width: 2,
                  ),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _editor(double height) {
    if (_error) {
      return const Center(
        child: Text('Görsel yüklenemedi. Geri dönüp tekrar deneyebilirsin.'),
      );
    }
    final imageSize = _imageSize;
    if (imageSize == null) {
      return const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Görsel yükleniyor'),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = math.max(1.0, constraints.maxWidth - 48);
        final maxHeight = math.max(1.0, height - 48);
        final scale = math.min(
          maxWidth / imageSize.width,
          maxHeight / imageSize.height,
        );
        final size = Size(imageSize.width * scale, imageSize.height * scale);
        return InteractiveViewer(
          key: const ValueKey('crop-zoom'),
          minScale: 1,
          maxScale: 5,
          boundaryMargin: const EdgeInsets.all(100),
          child: SizedBox(
            width: constraints.maxWidth,
            height: height,
            child: Center(
              child: SizedBox(
                width: size.width + 48,
                height: size.height + 48,
                child: Stack(
                  children: [
                    Positioned(
                      left: 24,
                      top: 24,
                      width: size.width,
                      height: size.height,
                      child: RotatedBox(
                        quarterTurns: widget.quarterTurns,
                        child: Image(
                          image: _preview,
                          fit: BoxFit.fill,
                          semanticLabel: 'Kırpılacak görsel',
                        ),
                      ),
                    ),
                    Positioned(
                      left: 24,
                      top: 24,
                      width: size.width,
                      height: size.height,
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _CropOverlay(
                            _bounds,
                            Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    for (final (horizontal, vertical) in const [
                      (-1, -1),
                      (0, -1),
                      (1, -1),
                      (-1, 0),
                      (1, 0),
                      (-1, 1),
                      (0, 1),
                      (1, 1),
                    ])
                      _handle(horizontal, vertical, size),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Görseli kırp')),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = math.max(180.0, constraints.maxHeight - 130);
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: height, child: _editor(height)),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Vazgeç'),
                      ),
                      FilledButton(
                        onPressed: _imageSize == null || _error ? null : _apply,
                        child: const Text('Uygula'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _CropOverlay extends CustomPainter {
  _CropOverlay(this.bounds, this.color);
  final Rect bounds;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final selected = Rect.fromLTRB(
      bounds.left * size.width,
      bounds.top * size.height,
      bounds.right * size.width,
      bounds.bottom * size.height,
    );
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(full)
      ..addRect(selected);
    canvas.drawPath(path, Paint()..color = const Color(0x99000000));
    canvas.drawRect(
      selected,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CropOverlay oldDelegate) =>
      bounds != oldDelegate.bounds || color != oldDelegate.color;
}
