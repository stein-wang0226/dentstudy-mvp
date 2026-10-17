import 'dart:convert';
import 'dart:ui' as ui;

/// Native fallback. The web implementation uses canvas JPEG encoding so the
/// browser-local preference remains compact; native platforms can keep PNG.
Future<String> encodeBackgroundImage(ui.Image image,
    {required double quality}) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) throw Exception('背景图片处理失败，请换一张图片重试');
  return 'data:image/png;base64,${base64Encode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes))}';
}
