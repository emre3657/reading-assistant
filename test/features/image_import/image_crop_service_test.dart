import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reading_assistant/features/image_import/services/image_crop_service.dart';

Uint8List _orientation6(Uint8List jpeg) => Uint8List.fromList([
  ...jpeg.sublist(0, 2),
  0xff,
  0xe1,
  0,
  0x22,
  0x45,
  0x78,
  0x69,
  0x66,
  0,
  0,
  0x4d,
  0x4d,
  0,
  0x2a,
  0,
  0,
  0,
  8,
  0,
  1,
  1,
  0x12,
  0,
  3,
  0,
  0,
  0,
  1,
  0,
  6,
  0,
  0,
  0,
  0,
  0,
  0,
  ...jpeg.sublist(2),
]);

void main() {
  const service = ImageCropService();
  late Directory directory;
  late File source;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('crop_test_');
    final image = img.Image(width: 80, height: 40);
    for (final pixel in image) {
      pixel.setRgb(pixel.x < 40 ? 255 : 0, 0, pixel.x < 40 ? 0 : 255);
    }
    source = File('${directory.path}${Platform.pathSeparator}source.png')
      ..writeAsBytesSync(img.encodePng(image));
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test(
    'crops full resolution and retains shared files until last release',
    () async {
      final original = source.readAsBytesSync();
      final crop = await service.createCrop(
        source.path,
        0,
        const Rect.fromLTRB(0, 0, .5, 1),
      );
      final image = img.decodePng(File(crop.path).readAsBytesSync())!;
      expect((image.width, image.height), (40, 40));
      expect(image.exif.imageIfd.orientation, isNull);
      expect(image.getPixel(20, 20).r, 255);
      expect(source.readAsBytesSync(), original);
      crop.retain();
      await crop.release();
      expect(File(crop.path).existsSync(), isTrue);
      await crop.release();
      expect(File(crop.path).existsSync(), isFalse);
      expect(source.existsSync(), isTrue);
    },
  );

  test('EXIF and additional turns match displayed coordinates', () async {
    final decoded = img.decodePng(source.readAsBytesSync())!;
    final jpeg = File('${directory.path}${Platform.pathSeparator}exif.jpg')
      ..writeAsBytesSync(_orientation6(img.encodeJpg(decoded, quality: 100)));
    for (final (turns, redOnTop) in [(0, true), (2, false)]) {
      final crop = await service.createCrop(
        jpeg.path,
        turns,
        const Rect.fromLTRB(0, 0, 1, .5),
      );
      final image = img.decodePng(File(crop.path).readAsBytesSync())!;
      expect((image.width, image.height), (40, 40));
      final pixel = image.getPixel(20, 20);
      expect(redOnTop ? pixel.r > 150 : pixel.b > 150, isTrue);
      await crop.release();
    }
    for (final turns in [1, 3]) {
      final crop = await service.createCrop(
        jpeg.path,
        turns,
        const Rect.fromLTRB(0, 0, .5, 1),
      );
      final image = img.decodePng(File(crop.path).readAsBytesSync())!;
      expect((image.width, image.height), (40, 40));
      final pixel = image.getPixel(20, 20);
      expect(turns == 1 ? pixel.b > 150 : pixel.r > 150, isTrue);
      await crop.release();
    }
  });

  test('repeated crops remain lossless and failures preserve source', () async {
    final first = await service.createCrop(
      source.path,
      0,
      const Rect.fromLTRB(0, 0, 1, .5),
    );
    final second = await service.createCrop(
      first.path,
      0,
      const Rect.fromLTRB(.5, 0, 1, 1),
    );
    final image = img.decodePng(File(second.path).readAsBytesSync())!;
    expect((image.width, image.height), (40, 20));
    expect(image.getPixel(10, 10).b, 255);
    await first.release();
    await second.release();
    await expectLater(
      service.createCrop(source.path, 0, const Rect.fromLTRB(0, 0, 2, 1)),
      throwsArgumentError,
    );
    final bad = File('${directory.path}${Platform.pathSeparator}bad')
      ..writeAsStringSync('invalid');
    await expectLater(
      service.createCrop(bad.path, 0, const Rect.fromLTRB(0, 0, 1, 1)),
      throwsFormatException,
    );
    expect(source.existsSync(), isTrue);
  });
}
