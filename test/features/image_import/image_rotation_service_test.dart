import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reading_assistant/features/image_import/services/image_rotation_service.dart';

/// Left half red, right half blue.
img.Image _redBlue({int width = 32, int height = 16}) {
  final image = img.Image(width: width, height: height);
  for (final pixel in image) {
    pixel.setRgb(
      pixel.x < width ~/ 2 ? 255 : 0,
      0,
      pixel.x < width ~/ 2 ? 0 : 255,
    );
  }
  return image;
}

bool _isRed(img.Pixel p) => p.r > 150 && p.b < 100;

/// Inserts a minimal big-endian EXIF APP1 segment with Orientation = 6 right
/// after the JPEG start marker.
Uint8List _withOrientation6(Uint8List jpeg) {
  const segment = [
    0xFF, 0xE1, 0x00, 0x22, // APP1, length 34
    0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // "Exif\0\0"
    0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08, // TIFF header, IFD0 at 8
    0x00, 0x01, // one entry
    0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, 0x06, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, // no next IFD
  ];
  return Uint8List.fromList([
    ...jpeg.sublist(0, 2),
    ...segment,
    ...jpeg.sublist(2),
  ]);
}

bool _isBlue(img.Pixel p) => p.b > 150 && p.r < 100;

void main() {
  const service = ImageRotationService();
  late Directory sourceDir;

  setUp(() => sourceDir = Directory.systemTemp.createTempSync('rotation_src_'));
  tearDown(() => sourceDir.deleteSync(recursive: true));

  File writeSource(img.Image image, {String name = 'source.jpg'}) {
    final file = File('${sourceDir.path}/$name');
    file.writeAsBytesSync(img.encodeJpg(image, quality: 100));
    return file;
  }

  test('rotates clockwise and leaves the source untouched', () async {
    final source = writeSource(_redBlue());
    final before = source.readAsBytesSync();

    final path = await service.createRotatedCopy(source.path, 1);
    final out = img.decodeJpg(File(path).readAsBytesSync())!;

    expect((out.width, out.height), (16, 32));
    expect(_isRed(out.getPixel(8, 4)), isTrue);
    expect(_isBlue(out.getPixel(8, 28)), isTrue);
    expect(source.readAsBytesSync(), before);
    await service.deleteCopy(path);
  });

  test(
    'left (3 turns) and 180 degrees (2 turns) give the right pixels',
    () async {
      final source = writeSource(_redBlue());

      final left = await service.createRotatedCopy(source.path, 3);
      final leftImage = img.decodeJpg(File(left).readAsBytesSync())!;
      expect(_isBlue(leftImage.getPixel(8, 4)), isTrue);
      expect(_isRed(leftImage.getPixel(8, 28)), isTrue);

      final flipped = await service.createRotatedCopy(source.path, 2);
      final flippedImage = img.decodeJpg(File(flipped).readAsBytesSync())!;
      expect((flippedImage.width, flippedImage.height), (32, 16));
      expect(_isBlue(flippedImage.getPixel(4, 8)), isTrue);
      expect(_isRed(flippedImage.getPixel(28, 8)), isTrue);

      await service.deleteCopy(left);
      await service.deleteCopy(flipped);
    },
  );

  test('applies EXIF orientation once and writes no orientation tag', () async {
    // Raw pixels are 32x16 and EXIF says "rotate 90 clockwise to display",
    // so the displayed image is 16x32. One more turn makes it 32x16 again.
    final source = File('${sourceDir.path}/exif.jpg')
      ..writeAsBytesSync(
        _withOrientation6(img.encodeJpg(_redBlue(), quality: 100)),
      );
    // The decoder applies the EXIF orientation itself; the result must not be
    // rotated a second time.
    final path = await service.createRotatedCopy(source.path, 1);
    final out = img.decodeJpg(File(path).readAsBytesSync())!;

    expect((out.width, out.height), (32, 16));
    expect(out.exif.imageIfd.orientation, isNull);
    // Display order after EXIF: red on top. One clockwise turn: red on the right.
    expect(_isRed(out.getPixel(28, 8)), isTrue);
    expect(_isBlue(out.getPixel(4, 8)), isTrue);
    await service.deleteCopy(path);
  });

  test('deleteCopy removes the copy directory only', () async {
    final source = writeSource(_redBlue());
    final path = await service.createRotatedCopy(source.path, 1);
    expect(File(path).existsSync(), isTrue);

    await service.deleteCopy(path);

    expect(File(path).existsSync(), isFalse);
    expect(Directory(File(path).parent.path).existsSync(), isFalse);
    expect(source.existsSync(), isTrue);
  });

  test('deleteCopy ignores files it did not create', () async {
    final foreign = writeSource(_redBlue(), name: 'foreign.jpg');

    await service.deleteCopy(foreign.path);

    expect(foreign.existsSync(), isTrue);
  });

  test('an undecodable file fails and leaves no temporary directory', () async {
    final bad = File('${sourceDir.path}/bad.jpg')..writeAsStringSync('nope');
    final before = Directory.systemTemp
        .listSync()
        .where((e) => e.path.contains('reading_assistant_ocr_'))
        .length;

    await expectLater(
      service.createRotatedCopy(bad.path, 1),
      throwsA(anything),
    );

    final after = Directory.systemTemp
        .listSync()
        .where((e) => e.path.contains('reading_assistant_ocr_'))
        .length;
    expect(after, before);
  });
}
