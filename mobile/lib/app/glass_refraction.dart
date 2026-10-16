import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Samples the real backdrop through a narrow curved lens. Only the perimeter
/// is magnified; foreground text and the clear center are never transformed.
/// Matrix backdrop filters work in CanvasKit without Impeller-only shaders.
class GlassRefraction extends StatelessWidget {
  final double radius;
  const GlassRefraction({super.key, required this.radius});

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: LayoutBuilder(builder: (context, constraints) {
        final w = constraints.maxWidth, h = constraints.maxHeight;
        if (!w.isFinite || !h.isFinite || w < 12 || h < 12) {
          return const SizedBox.shrink();
        }
        // At the outer edge pixels are sampled ~3px inward, like a convex lip.
        // Scaling is bounded by pixel displacement, not by the size of the card.
        final matrix = Float64List.fromList([
          1 + 6 / w,
          0,
          0,
          0,
          0,
          1 + 6 / h,
          0,
          0,
          0,
          0,
          1,
          0,
          -3,
          -3,
          0,
          1,
        ]);
        return ClipPath(
            clipper: GlassEdgeClipper(radius),
            child: BackdropFilter(
                filter: ui.ImageFilter.matrix(matrix,
                    filterQuality: FilterQuality.high),
                child: const SizedBox.expand()));
      }));
}

class GlassEdgeClipper extends CustomClipper<Path> {
  final double radius;
  const GlassEdgeClipper(this.radius);
  @override
  Path getClip(Size size) {
    final rect = Offset.zero & size;
    if (radius == 0) {
      return Path()..addRect(Rect.fromLTWH(0, size.height - 4, size.width, 4));
    }
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)))
      ..addRRect(RRect.fromRectAndRadius(
          rect.deflate(4), Radius.circular((radius - 4).clamp(0, radius))));
  }

  @override
  bool shouldReclip(GlassEdgeClipper oldClipper) => oldClipper.radius != radius;
}

/// Keeps scrolling text from colliding with transparent navigation labels.
/// A clip preserves access to the real backdrop for nested edge lenses, unlike
/// an opacity saveLayer. The wallpaper stays visible behind the navigation.
class GlassContentViewport extends StatelessWidget {
  final bool enabled;
  final Widget child;
  const GlassContentViewport(
      {super.key, required this.enabled, required this.child});
  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final padding = MediaQuery.paddingOf(context);
    return ClipRect(clipper: _ContentInsets(padding), child: child);
  }
}

class _ContentInsets extends CustomClipper<Rect> {
  final EdgeInsets padding;
  const _ContentInsets(this.padding);
  @override
  Rect getClip(Size size) {
    final top = padding.top.clamp(0.0, size.height);
    final bottom = (size.height - padding.bottom).clamp(top, size.height);
    return Rect.fromLTRB(0, top, size.width, bottom);
  }

  @override
  bool shouldReclip(_ContentInsets oldClipper) => oldClipper.padding != padding;
}
