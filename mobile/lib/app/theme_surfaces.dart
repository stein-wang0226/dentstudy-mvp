import 'package:flutter/material.dart';
import 'glass_refraction.dart';

/// Warm translucent acrylic: full-surface diffusion with a fine lit rim.
class StudySurface extends StatelessWidget {
  final Widget child;
  final bool glass;
  final Color tint, borderColor, color;
  final double radius;
  final bool navigation;
  final EdgeInsetsGeometry padding;
  const StudySurface(
      {super.key,
      required this.child,
      required this.glass,
      required this.tint,
      required this.borderColor,
      this.color = Colors.white,
      this.radius = 22,
      this.navigation = false,
      this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) {
    final content = Padding(
        padding: padding,
        child: Material(type: MaterialType.transparency, child: child));
    if (!glass) {
      return Container(
          width: double.infinity,
          decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: borderColor)),
          child: content);
    }
    return Container(
        width: double.infinity,
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xff49372a).withAlpha(6),
                  blurRadius: 24,
                  offset: const Offset(0, 6))
            ]),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: CustomPaint(
                foregroundPainter:
                    _GlassRim(radius, Theme.of(context).colorScheme.primary),
                child: Stack(children: [
                  Positioned.fill(
                      child: GlassRefraction(
                          radius: radius, blurSigma: navigation ? 22 : 18)),
                  // Bronze absorption is uniform across the entire pane; it
                  // never becomes a dark border or affects foreground content.
                  Positioned.fill(
                      child: ColoredBox(
                          color: const Color(0xff8c6844).withAlpha(24))),
                  DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              stops: const [
                            0,
                            .48,
                            1
                          ],
                              colors: [
                            Colors.white.withAlpha(36),
                            Colors.white.withAlpha(2),
                            Colors.white.withAlpha(8)
                          ])),
                      child: content)
                ]))));
  }
}

/// A hairline reflection, independent of the actual backdrop deformation.
class _GlassRim extends CustomPainter {
  final double radius;
  final Color accent;
  const _GlassRim(this.radius, this.accent);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(.35);
    if (radius == 0) {
      canvas.drawLine(
          Offset(0, size.height - .35),
          Offset(size.width, size.height - .35),
          Paint()
            ..strokeWidth = .7
            ..color = Colors.white.withAlpha(100));
      return;
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7
      ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withAlpha(220),
            Colors.white.withAlpha(60),
            Colors.white.withAlpha(8)
          ]).createShader(rect);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)), paint);
    // Sparse luminous side arcs follow the selected theme, not fixed blue/pink.
    // There is no colored bottom stroke or shaded perimeter band.
    final r = radius.clamp(0.0, size.shortestSide / 2);
    final glint = Path()
      ..moveTo(.6, r + 20)
      ..lineTo(.6, r)
      ..quadraticBezierTo(.6, .6, r, .6)
      ..moveTo(size.width - .6, size.height - r - 20)
      ..lineTo(size.width - .6, size.height - r)
      ..quadraticBezierTo(
          size.width - .6, size.height - .6, size.width - r, size.height - .6);
    canvas.drawPath(
        glint,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = accent.withAlpha(42)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
  }

  @override
  bool shouldRepaint(_GlassRim oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.accent != accent;
}

class StudyBackdrop extends StatelessWidget {
  final Widget child;
  final bool glass;
  // Deliberately no primary/accent input: the backdrop only uses its own hue.
  final Color background, tint;
  const StudyBackdrop(
      {super.key,
      required this.child,
      required this.glass,
      required this.background,
      required this.tint});
  @override
  Widget build(BuildContext context) => Stack(children: [
        Positioned.fill(
            child: ColoredBox(
                color: background,
                child:
                    glass ? CustomPaint(painter: _GlassBackdrop(tint)) : null)),
        child
      ]);
}

/// Static, soft ribbons make transmission visible without an animated wallpaper
/// or a full-screen blur. Only the independently selected background hue is used.
class _GlassBackdrop extends CustomPainter {
  final Color tint;
  const _GlassBackdrop(this.tint);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
                  center: const Alignment(-.9, -.85),
                  radius: 1.25,
                  colors: [tint.withAlpha(32), tint.withAlpha(0)])
              .createShader(rect));
    canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
                  center: const Alignment(1, .8),
                  radius: 1.1,
                  colors: [tint.withAlpha(24), tint.withAlpha(0)])
              .createShader(rect));
    final w = size.width, h = size.height;
    final ribbon = Path()
      ..moveTo(w * .52, -h * .1)
      ..cubicTo(w * 1.05, h * .12, -w * .35, h * .52, w * .3, h * 1.1)
      ..lineTo(w * .72, h * 1.1)
      ..cubicTo(-w * .05, h * .58, w * 1.48, h * .23, w * .88, -h * .1)
      ..close();
    canvas.drawPath(
        ribbon,
        Paint()
          ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withAlpha(110),
                Colors.white.withAlpha(30),
                tint.withAlpha(8),
                Colors.white.withAlpha(95)
              ],
              stops: const [
                0,
                .38,
                .68,
                1
              ]).createShader(rect));
    final glint = Path()
      ..moveTo(w * .52, -h * .1)
      ..cubicTo(w * 1.05, h * .12, -w * .35, h * .52, w * .3, h * 1.1);
    canvas.drawPath(
        glint,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .75
          ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withAlpha(100),
                Colors.white.withAlpha(0),
                Colors.white.withAlpha(75)
              ]).createShader(rect));
  }

  @override
  bool shouldRepaint(_GlassBackdrop oldDelegate) => oldDelegate.tint != tint;
}

class FrostedChrome extends StatelessWidget {
  final bool enabled;
  final Widget child;
  final double radius;
  const FrostedChrome(
      {super.key, required this.enabled, required this.child, this.radius = 0});
  @override
  Widget build(BuildContext context) => enabled
      ? StudySurface(
          glass: true,
          tint: Colors.transparent,
          borderColor: Colors.transparent,
          radius: radius,
          navigation: true,
          padding: EdgeInsets.zero,
          child: child)
      : child;
}
