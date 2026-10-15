import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dentstudy/features/profile/avatar_crop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('photo decoding and square export work through browser-compatible APIs',
      () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
        const Rect.fromLTWH(0, 0, 640, 320), Paint()..color = Colors.red);
    canvas.drawRect(const Rect.fromLTWH(320, 0, 320, 320),
        Paint()..color = const Color(0xFF0000FF));
    final picture = recorder.endRecording();
    final source = await picture.toImage(640, 320);
    final sourceBytes = await source.toByteData(format: ui.ImageByteFormat.png);
    final decoded = await decodeAvatarImage(sourceBytes!.buffer.asUint8List());
    expect(decoded.width, 640);
    expect(decoded.height, 320);
    final rect = avatarCropRect(decoded, 1, const Offset(1, .5));
    expect(rect, const Rect.fromLTWH(320, 0, 320, 320));
    final result = await encodeAvatarCrop(decoded, rect);
    final output =
        await decodeAvatarImage(base64Decode(result.split(',').last));
    expect(output.width, 256);
    expect(output.height, 256);
    final pixels = await output.toByteData(format: ui.ImageByteFormat.rawRgba);
    // The selected right half is blue; no stretching or wrong-side crop.
    expect(pixels!.getUint8(0), lessThan(10));
    expect(pixels.getUint8(2), greaterThan(240));
    final zoomed = avatarCropRect(decoded, 2, const Offset(0, 0));
    expect(zoomed, const Rect.fromLTWH(0, 0, 160, 160));
    output.dispose();
    decoded.dispose();
    source.dispose();
    picture.dispose();
  });
}
