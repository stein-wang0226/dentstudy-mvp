import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Refracts and diffuses the entire backdrop, not a dark perimeter ring.
/// Foreground text is painted separately and is never transformed or blurred.
/// Matrix backdrop filters work in CanvasKit without Impeller-only shaders.
class GlassRefraction extends StatelessWidget {
  final double radius;
  final double blurSigma;
  const GlassRefraction({super.key, required this.radius, this.blurSigma = 18});

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
        // A single continuous lens has no concentric bands or dark seams.
        // Bound the magnification in pixels so desktop cards remain subtle.
        final displacement = (w < h ? w : h).clamp(0.0, 60.0) / 10;
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
        return ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: BackdropFilter(
                filter: ui.ImageFilter.compose(
                    outer: ui.ImageFilter.blur(
                        sigmaX: blurSigma, sigmaY: blurSigma),
                    inner: ui.ImageFilter.matrix(matrix,
                        filterQuality: FilterQuality.high)),
                child: const SizedBox.expand()));
      })));
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
