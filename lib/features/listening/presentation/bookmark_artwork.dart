import 'package:flutter/material.dart';

import 'reading_preferences.dart';

class BookmarkArtwork extends StatelessWidget {
  const BookmarkArtwork({super.key, required this.shape, required this.color});

  final BookmarkShape shape;
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: const Size(32, 52),
      painter: _BookmarkPainter(shape, color),
    ),
  );
}

class _BookmarkPainter extends CustomPainter {
  const _BookmarkPainter(this.shape, this.color);

  final BookmarkShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    switch (shape) {
      case BookmarkShape.strip:
        path.addRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(7, 0, size.width - 14, size.height - 7),
            const Radius.circular(2),
          ),
        );
      case BookmarkShape.ribbon:
        path
          ..moveTo(5, 0)
          ..lineTo(size.width - 5, 0)
          ..lineTo(size.width - 5, size.height - 2)
          ..lineTo(size.width / 2, size.height - 12)
          ..lineTo(5, size.height - 2)
          ..close();
      case BookmarkShape.corner:
        path
          ..moveTo(0, 0)
          ..lineTo(size.width, 0)
          ..lineTo(size.width, size.width)
          ..close();
    }
    canvas.drawShadow(path, Colors.black54, 2, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_BookmarkPainter oldDelegate) =>
      shape != oldDelegate.shape || color != oldDelegate.color;
}
