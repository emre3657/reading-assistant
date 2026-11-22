import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as image;

// Run from the project root: dart run tool/generate_app_icons.dart
const sourcePath = 'assets/branding/app_icon.png';
const androidPath = 'android/app/src/main/res';
const iosPath = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
const adaptiveScale = 0.68;

void main() {
  final source = image.decodePng(File(sourcePath).readAsBytesSync());
  if (source == null || source.width != source.height) {
    throw StateError('The source icon must be a square PNG.');
  }

  final foreground = image.Image(
    width: source.width,
    height: source.height,
    numChannels: 4,
  );
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final pixel = source.getPixel(x, y);
      // The source is cream artwork over a dark teal background.
      final alpha = ((pixel.r - 3) / 248).clamp(0.0, 1.0);
      if (alpha < 0.06) continue;
      int unblend(num channel, int background) =>
          ((channel - background * (1 - alpha)) / alpha).round().clamp(0, 255);
      foreground.setPixelRgba(
        x,
        y,
        unblend(pixel.r, 3),
        unblend(pixel.g, 74),
        unblend(pixel.b, 74),
        (alpha * 255).round(),
      );
    }
  }

  const densities = {
    'mdpi': 1,
    'hdpi': 1.5,
    'xhdpi': 2,
    'xxhdpi': 3,
    'xxxhdpi': 4,
  };
  for (final entry in densities.entries) {
    final size = (48 * entry.value).round();
    final adaptiveSize = (108 * entry.value).round();
    _write(
      '$androidPath/mipmap-${entry.key}/ic_launcher.png',
      _resize(source, size),
    );
    final layer = image.Image(
      width: adaptiveSize,
      height: adaptiveSize,
      numChannels: 4,
    );
    final art = _resize(foreground, (adaptiveSize * adaptiveScale).round());
    final offset = (adaptiveSize - art.width) ~/ 2;
    image.compositeImage(layer, art, dstX: offset, dstY: offset);
    _write(
      '$androidPath/mipmap-${entry.key}/ic_launcher_foreground.png',
      layer,
    );
  }

  for (final scale in [1, 2, 3]) {
    final size = 168 * scale;
    final layer = image.Image(width: size, height: size, numChannels: 4);
    final art = _resize(foreground, (size * adaptiveScale).round());
    final offset = (size - art.width) ~/ 2;
    image.compositeImage(layer, art, dstX: offset, dstY: offset);
    final suffix = scale == 1 ? '' : '@${scale}x';
    _write(
      'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage$suffix.png',
      layer,
    );
  }

  final catalog = jsonDecode(
    File('$iosPath/Contents.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  for (final item in catalog['images'] as List<dynamic>) {
    final entry = item as Map<String, dynamic>;
    final points = double.parse((entry['size'] as String).split('x').first);
    final scale = int.parse((entry['scale'] as String).replaceAll('x', ''));
    final size = (points * scale).round();
    final resized = _resize(source, size);
    final opaque = image.Image(width: size, height: size, numChannels: 3);
    image.compositeImage(opaque, resized);
    _write('$iosPath/${entry['filename']}', opaque);
  }
}

image.Image _resize(image.Image source, int size) => image.copyResize(
  source,
  width: size,
  height: size,
  interpolation: image.Interpolation.average,
);

void _write(String path, image.Image icon) {
  if (icon.width != icon.height || icon.width <= 0) {
    throw StateError('Invalid icon size: $path');
  }
  File(path).writeAsBytesSync(image.encodePng(icon));
}
