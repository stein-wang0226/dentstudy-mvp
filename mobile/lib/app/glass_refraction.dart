import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Clear thick glass: a mild full-pane lens with stronger rounded shoulders.
/// All regions sample the actual backdrop, with no tint, blur or dark bands.
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
        final shoulder = (w < h ? w : h).clamp(0.0, 80.0) / 8;
        Widget region(double inset, double? width, double displacement) {
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
                  clipper: GlassLensRegion(radius, inset: inset, width: width),
                  child: BackdropFilter(
                      filter: ui.ImageFilter.matrix(matrix,
                          filterQuality: FilterQuality.high),
                      child: const SizedBox.expand())));
        }

        // Non-overlapping regions avoid repeatedly filtering the same pixels.
        // Curvature is approximated with stepped magnification, not dark strokes.
        return Stack(children: [
          region(0, shoulder * .4, shoulder * 1.6),
          region(shoulder * .4, shoulder * .6, shoulder * .9),
          region(shoulder, null, shoulder * .4),
        ]);
      })));
}

class GlassLensRegion extends CustomClipper<Path> {
  final double radius, inset;
  final double? width;
  const GlassLensRegion(this.radius, {required this.inset, this.width});
  @override
  Path getClip(Size size) {
    RRect shape(double d) => RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(d),
        Radius.circular((radius - d).clamp(0, radius)));
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(shape(inset));
    if (width != null) path.addRRect(shape(inset + width!));
    return path;
  }

  @override
  bool shouldReclip(GlassLensRegion old) =>
      old.radius != radius || old.inset != inset || old.width != width;
}

/// Keeps scrolling text from colliding with transparent navigation labels.
/// A clip preserves access to the real backdrop for nested glass lenses, unlike
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
