import 'package:flutter/material.dart';

/// Shows [image] at full width, keeping its aspect ratio, rotated clockwise by
/// [quarterTurns] * 90 degrees.
///
/// The image is decoded no larger than the displayed size; the source file is
/// never modified. [onError] is called at most once per preview instance, and
/// never after the preview has been removed.
class ImagePreview extends StatefulWidget {
  const ImagePreview({
    super.key,
    required this.image,
    required this.onError,
    this.quarterTurns = 0,
  });

  final ImageProvider image;
  final VoidCallback onError;
  final int quarterTurns;

  @override
  State<ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<ImagePreview> {
  bool _errorReported = false;

  void _reportError() {
    if (_errorReported) return;
    _errorReported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onError();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final target = constraints.maxWidth.isFinite
            ? (constraints.maxWidth * pixelRatio).round()
            : null;
        // For sideways turns the displayed width is the image's height.
        final sideways = widget.quarterTurns.isOdd;
        return RotatedBox(
          quarterTurns: widget.quarterTurns,
          child: Image(
            image: ResizeImage.resizeIfNeeded(
              sideways ? null : target,
              sideways ? target : null,
              widget.image,
            ),
            fit: BoxFit.contain,
            semanticLabel: 'Seçilen görselin önizlemesi',
            errorBuilder: (context, error, stackTrace) {
              _reportError();
              return const SizedBox.shrink();
            },
          ),
        );
      },
    );
  }
}
