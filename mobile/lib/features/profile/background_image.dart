import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../../app/theme_palette.dart';
import 'background_image_encoder.dart';

const maxBackgroundSourceBytes = 8 * 1024 * 1024;
const maxStoredBackgroundBytes = 1200 * 1024;
const maxBackgroundDimension = 1280;

class PreparedBackgroundImage {
  final String dataUri;
  final String suggestedThemeKey;
  final int bytes, width, height;
  const PreparedBackgroundImage({
    required this.dataUri,
    required this.suggestedThemeKey,
    required this.bytes,
    required this.width,
    required this.height,
  });
}

int backgroundDataUriBytes(String value) {
  final comma = value.indexOf(',');
  if (comma < 0) return -1;
  try {
    return base64Decode(value.substring(comma + 1)).length;
  } on FormatException {
    return -1;
  }
}

bool isStoredBackgroundDataUri(String? value) =>
    value != null &&
    RegExp(r'^data:image/(?:jpeg|png|webp);base64,[A-Za-z0-9+/=]+$')
        .hasMatch(value) &&
    backgroundDataUriBytes(value) > 0 &&
    backgroundDataUriBytes(value) <= maxStoredBackgroundBytes;

Future<ui.Image> _scaledImage(ui.Image source, int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImageRect(
      source,
      ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.high);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

Future<String> _suggestTheme(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return 'teal';
  final rgba = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final side = max(1, sqrt(image.width * image.height / 4200).round());
  var red = 0.0, green = 0.0, blue = 0.0, weight = 0.0;
  for (var y = 0; y < image.height; y += side) {
    for (var x = 0; x < image.width; x += side) {
      final offset = (y * image.width + x) * 4;
      final alpha = rgba[offset + 3] / 255;
      if (alpha < .5) continue;
      final r = rgba[offset].toDouble(), g = rgba[offset + 1].toDouble();
      final b = rgba[offset + 2].toDouble();
      final high = max(r, max(g, b)), low = min(r, min(g, b));
      final saturation = high == 0 ? 0 : (high - low) / high;
      // Prefer the actual colored portions of a photograph. Neutral pixels
      // still participate lightly so grayscale backgrounds map to graphite.
      final pixelWeight = saturation < .08 ? .25 : .5 + saturation;
      red += r * alpha * pixelWeight;
      green += g * alpha * pixelWeight;
      blue += b * alpha * pixelWeight;
      weight += alpha * pixelWeight;
    }
  }
  if (weight == 0) return 'teal';
  final average = ui.Color.fromARGB(255, (red / weight).round(),
      (green / weight).round(), (blue / weight).round());
  String? closest;
  var distance = double.infinity;
  for (final entry in themeColors.entries) {
    final color = entry.value;
    final candidate = pow(color.r * 255 - average.r * 255, 2) +
        pow(color.g * 255 - average.g * 255, 2) +
        pow(color.b * 255 - average.b * 255, 2);
    if (candidate < distance) {
      distance = candidate.toDouble();
      closest = entry.key;
    }
  }
  return closest ?? 'teal';
}

/// Downscale and encode a user-selected wallpaper for safe device-local use.
/// It is deliberately not uploaded or included in account sync.
Future<PreparedBackgroundImage> prepareBackgroundImage(Uint8List source) async {
  if (source.isEmpty || source.length > maxBackgroundSourceBytes) {
    throw Exception('请选择 8 MB 以内的 JPG、PNG 或 WebP 图片');
  }
  ui.Codec? codec;
  ui.Image? original;
  try {
    codec = await ui.instantiateImageCodec(source);
  } catch (_) {
    throw Exception('图片无法读取，请选择 JPG、PNG 或 WebP 文件');
  }
  try {
    original = (await codec.getNextFrame()).image;
    final longest = max(original.width, original.height);
    final factor = min(1, maxBackgroundDimension / longest);
    var width = max(1, (original.width * factor).round());
    var height = max(1, (original.height * factor).round());
    var quality = .82;
    String? dataUri;
    int outputBytes = 0;
    for (var attempt = 0; attempt < 5; attempt++) {
      final rendered = await _scaledImage(original, width, height);
      try {
        dataUri = await encodeBackgroundImage(rendered, quality: quality);
      } finally {
        rendered.dispose();
      }
      outputBytes = backgroundDataUriBytes(dataUri);
      if (outputBytes > 0 && outputBytes <= maxStoredBackgroundBytes) break;
      quality -= .1;
      if (quality < .5) {
        width = max(1, (width * .72).round());
        height = max(1, (height * .72).round());
        quality = .72;
      }
    }
    if (dataUri == null ||
        outputBytes < 1 ||
        outputBytes > maxStoredBackgroundBytes) {
      throw Exception('图片细节过多，压缩后仍偏大，请换一张更简单的图片');
    }
    final rendered = await _scaledImage(original, width, height);
    try {
      return PreparedBackgroundImage(
          dataUri: dataUri,
          suggestedThemeKey: await _suggestTheme(rendered),
          bytes: outputBytes,
          width: width,
          height: height);
    } finally {
      rendered.dispose();
    }
  } finally {
    original?.dispose();
    codec.dispose();
  }
}
