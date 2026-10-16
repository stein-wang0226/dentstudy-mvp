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
      // A retained offset layer anchors the matrix at this surface, not at the
      // page origin. Unlike an opacity layer it still samples the real backdrop.
      IgnorePointer(child:
          RepaintBoundary(child: LayoutBuilder(builder: (context, constraints) {
        final w = constraints.maxWidth, h = constraints.maxHeight;
        if (!w.isFinite || !h.isFinite || w < 12 || h < 12) {
          return const SizedBox.shrink();
        }
        // Two non-overlapping optical bands approximate a convex lip: the
        // outer band bends more strongly, then relaxes toward the clear center.
        // Keep displacement bounded in pixels even on wide desktop cards.
        final band = (w < h ? w : h).clamp(0.0, 20.0) / 4;
        Widget lens(double inset, double displacement, int smoke) {
          final matrix = Float64List.fromList([
            1 + displacement * 2 / w,
            0,
            0,
            0,
            0,
            1 + displacement * 2 / h,
            0,
            0,
            0,
            0,
            1,
            0,
            -displacement,
            -displacement,
            0,
            1,
          ]);
          return Positioned.fill(
              child: ClipPath(
                  clipper: GlassEdgeClipper(radius, inset: inset, width: band),
                  child: BackdropFilter(
                      filter: ui.ImageFilter.matrix(matrix,
                          filterQuality: FilterQuality.high),
                      // Absorption belongs to the sampled backdrop, never the text.
                      child:
                          ColoredBox(color: Colors.black.withAlpha(smoke)))));
        }

        return Stack(children: [
          lens(0, band * 2, 6),
          lens(band, band * .8, 2),
        ]);
      })));
}

class GlassEdgeClipper extends CustomClipper<Path> {
  final double radius;
  final double inset, width;
  const GlassEdgeClipper(this.radius, {this.inset = 0, this.width = 10});
  @override
  Path getClip(Size size) {
    final rect = (Offset.zero & size).deflate(inset);
    if (radius == 0) {
      return Path()
        ..addRect(
            Rect.fromLTWH(0, size.height - inset - width, size.width, width));
    }
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(RRect.fromRectAndRadius(
          rect, Radius.circular((radius - inset).clamp(0, radius))))
      ..addRRect(RRect.fromRectAndRadius(rect.deflate(width),
          Radius.circular((radius - inset - width).clamp(0, radius))));
  }

  @override
  bool shouldReclip(GlassEdgeClipper oldClipper) =>
      oldClipper.radius != radius ||
      oldClipper.inset != inset ||
      oldClipper.width != width;
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
