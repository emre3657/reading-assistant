import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

image.Image _readIcon(String path) {
  final icon = image.decodePng(File(path).readAsBytesSync());
  if (icon == null) throw StateError('Invalid PNG: $path');
  return icon;
}

void main() {
  test('Android launcher layers fit the adaptive safe circle', () {
    const root = 'android/app/src/main';
    expect(
      File('$root/AndroidManifest.xml').readAsStringSync(),
      contains('android:icon="@mipmap/ic_launcher"'),
    );
    final adaptive = File('$root/res/mipmap-anydpi-v26/ic_launcher.xml')
        .readAsStringSync();
    expect(adaptive, contains('@color/ic_launcher_background'));
    expect(adaptive, contains('@mipmap/ic_launcher_foreground'));
    expect(
      File('$root/res/values/ic_launcher_background.xml').readAsStringSync(),
      contains('#034A4A'),
    );
    for (final entry in {
      'mdpi': 1.0,
      'hdpi': 1.5,
      'xhdpi': 2.0,
      'xxhdpi': 3.0,
      'xxxhdpi': 4.0,
    }.entries) {
      final directory = '$root/res/mipmap-${entry.key}';
      final legacy = _readIcon('$directory/ic_launcher.png');
      expect(legacy.width, (48 * entry.value).round());
      expect(legacy.height, legacy.width);
      for (final (x, y) in [
        (0, 0),
        (legacy.width - 1, 0),
        (0, legacy.height - 1),
        (legacy.width - 1, legacy.height - 1),
      ]) {
        final corner = legacy.getPixel(x, y);
        expect(corner.r, lessThan(30));
        expect(corner.g, greaterThan(50));
        expect(corner.a, 255);
      }
      final foreground = _readIcon('$directory/ic_launcher_foreground.png');
      expect(foreground.width, (108 * entry.value).round());
      expect(foreground.height, foreground.width);
      var hasArtwork = false;
      var maxRadius = 0.0;
      for (var y = 0; y < foreground.height; y++) {
        for (var x = 0; x < foreground.width; x++) {
          if (foreground.getPixel(x, y).a <= 8) continue;
          hasArtwork = true;
          final dx = x + 0.5 - foreground.width / 2;
          final dy = y + 0.5 - foreground.height / 2;
          maxRadius = math.max(maxRadius, math.sqrt(dx * dx + dy * dy));
        }
      }
      expect(hasArtwork, isTrue);
      expect(maxRadius, lessThanOrEqualTo(foreground.width * 33 / 108));
    }
  });

  test('iOS AppIcon images are opaque squares with unrounded teal corners', () {
    const root = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    final catalog = jsonDecode(
      File('$root/Contents.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final raw in catalog['images'] as List<dynamic>) {
      final entry = raw as Map<String, dynamic>;
      final size =
          (double.parse((entry['size'] as String).split('x').first) *
                  int.parse((entry['scale'] as String).replaceAll('x', '')))
              .round();
      final icon = _readIcon('$root/${entry['filename']}');
      expect(icon.width, size);
      expect(icon.height, size);
      expect(icon.numChannels, 3);
      for (final (x, y) in [
        (0, 0),
        (size - 1, 0),
        (0, size - 1),
        (size - 1, size - 1),
      ]) {
        final corner = icon.getPixel(x, y);
        expect(corner.r, lessThan(30));
        expect(corner.g, greaterThan(50));
        expect(corner.a, 255);
      }
    }
  });
}
