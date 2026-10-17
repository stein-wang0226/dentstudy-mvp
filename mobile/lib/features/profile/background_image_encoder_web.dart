// ignore_for_file: deprecated_member_use

import 'dart:typed_data';
import 'dart:html' as html;
import 'dart:ui' as ui;

/// Canvas JPEG export substantially reduces the space used in Safari's local
/// storage without sending the chosen photo to the server.
Future<String> encodeBackgroundImage(ui.Image image,
    {required double quality}) async {
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (pixels == null) throw Exception('背景图片处理失败，请换一张图片重试');
  final bytes =
      pixels.buffer.asUint8List(pixels.offsetInBytes, pixels.lengthInBytes);
  final canvas = html.CanvasElement(width: image.width, height: image.height);
  canvas.context2D.putImageData(
      html.ImageData(
          Uint8ClampedList.fromList(bytes), image.width, image.height),
      0,
      0);
  return canvas.toDataUrl('image/jpeg', quality.clamp(.45, .88).toDouble());
}
