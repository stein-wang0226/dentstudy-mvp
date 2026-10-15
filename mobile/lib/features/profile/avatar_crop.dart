import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Decode through the codec API supported by both browsers and native apps.
/// ImageDescriptor.width/height are intentionally avoided on the web.
Future<ui.Image> decodeAvatarImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

Rect avatarCropRect(ui.Image image, double zoom, Offset position) {
  final side = (image.width < image.height ? image.width : image.height) / zoom;
  return Rect.fromLTWH((image.width - side) * position.dx.clamp(0, 1),
      (image.height - side) * position.dy.clamp(0, 1), side, side);
}

Future<String> encodeAvatarCrop(ui.Image image, Rect rect) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(image, rect, const Rect.fromLTWH(0, 0, 256, 256),
      Paint()..filterQuality = FilterQuality.high);
  final picture = recorder.endRecording();
  ui.Image? cropped;
  try {
    cropped = await picture.toImage(256, 256);
    final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw Exception('头像生成失败，请重新选择图片');
    return 'data:image/png;base64,${base64Encode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes))}';
  } finally {
    cropped?.dispose();
    picture.dispose();
  }
}

class AvatarCropPage extends StatefulWidget {
  final ui.Image image;
  const AvatarCropPage({super.key, required this.image});
  @override
  State<AvatarCropPage> createState() => _AvatarCropPageState();
}

class _AvatarCropPageState extends State<AvatarCropPage> {
  double zoom = 1, startZoom = 1;
  Offset position = const Offset(.5, .5);
  bool saving = false;
  String? error;

  Future<void> save() async {
    setState(() => saving = true);
    try {
      final value = await encodeAvatarCrop(
          widget.image, avatarCropRect(widget.image, zoom, position));
      if (mounted) Navigator.pop(context, value);
    } catch (_) {
      if (mounted)
        setState(() {
          error = '裁剪失败，请重试或换一张图片';
          saving = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('裁剪头像')),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView(padding: const EdgeInsets.all(24), children: [
                const Text('拖动照片调整位置，双指或滑块缩放。', textAlign: TextAlign.center),
                const SizedBox(height: 20),
                AspectRatio(
                    aspectRatio: 1,
                    child: LayoutBuilder(
                        builder: (context, constraints) => GestureDetector(
                            onScaleStart: (_) => startZoom = zoom,
                            onScaleUpdate: saving
                                ? null
                                : (details) => setState(() {
                                      zoom = (startZoom * details.scale)
                                          .clamp(1, 4);
                                      final side = avatarCropRect(
                                              widget.image, zoom, position)
                                          .width;
                                      final remainingX =
                                          widget.image.width - side;
                                      final remainingY =
                                          widget.image.height - side;
                                      position = Offset(
                                          remainingX <= 0
                                              ? .5
                                              : (position.dx -
                                                      details.focalPointDelta
                                                              .dx *
                                                          side /
                                                          constraints.maxWidth /
                                                          remainingX)
                                                  .clamp(0, 1),
                                          remainingY <= 0
                                              ? .5
                                              : (position.dy -
                                                      details.focalPointDelta
                                                              .dy *
                                                          side /
                                                          constraints.maxWidth /
                                                          remainingY)
                                                  .clamp(0, 1));
                                    }),
                            child: CustomPaint(
                                painter: _CropPainter(
                                    widget.image,
                                    avatarCropRect(
                                        widget.image, zoom, position)),
                                child: const SizedBox.expand())))),
                const SizedBox(height: 16),
                Row(children: [
                  const Icon(Icons.zoom_out),
                  Expanded(
                      child: Slider(
                          value: zoom,
                          min: 1,
                          max: 4,
                          label: '${zoom.toStringAsFixed(1)}×',
                          onChanged: saving
                              ? null
                              : (value) => setState(() => zoom = value))),
                  const Icon(Icons.zoom_in)
                ]),
                TextButton(
                    onPressed: saving
                        ? null
                        : () => setState(() {
                              zoom = 1;
                              position = const Offset(.5, .5);
                            }),
                    child: const Text('重新居中')),
                if (error != null)
                  Text(error!,
                      style: const TextStyle(color: Colors.deepOrange)),
                const Text('头像将保存为正方形，展示时使用圆形外观。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
              ]))),
      bottomNavigationBar: SafeArea(
          child: Padding(
              padding: const EdgeInsets.all(20),
              child: FilledButton(
                  onPressed: saving ? null : save,
                  child: Text(saving ? '正在裁剪…' : '使用此头像')))));
}

class _CropPainter extends CustomPainter {
  final ui.Image image;
  final Rect crop;
  _CropPainter(this.image, this.crop);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFF1F3F3));
    canvas.drawImageRect(image, crop, Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium);
    final line = Paint()
      ..color = Colors.white.withAlpha(130)
      ..strokeWidth = 1;
    for (var step = 1; step < 3; step++) {
      canvas.drawLine(Offset(size.width * step / 3, 0),
          Offset(size.width * step / 3, size.height), line);
      canvas.drawLine(Offset(0, size.height * step / 3),
          Offset(size.width, size.height * step / 3), line);
    }
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _CropPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.crop != crop;
}
