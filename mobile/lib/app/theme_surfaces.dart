import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// The blur is clipped to each visible surface, not the entire scrolling page.
class StudySurface extends StatelessWidget {
  final Widget child;
  final bool glass;
  final Color tint, borderColor, color;
  final double radius;
  final double blurSigma;
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
      this.blurSigma = 3,
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
                  color: const Color(0xFF26313D).withAlpha(18),
                  blurRadius: 16,
                  offset: const Offset(0, 6)),
              BoxShadow(color: tint.withAlpha(8), blurRadius: 24)
            ]),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: BackdropFilter(
                filter:
                    ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                child: CustomPaint(
                    foregroundPainter: _GlassRim(radius),
                    child: DecoratedBox(
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
                              Colors.white.withAlpha(navigation ? 28 : 40),
                              color.withAlpha(navigation ? 3 : 7),
                              Colors.white.withAlpha(navigation ? 16 : 24)
                            ])),
                        child: content)))));
  }
}

/// Edge-only optical highlights: the center stays clear. This approximates a
/// curved lens visually; it does not claim physical refraction of page pixels.
class _GlassRim extends CustomPainter {
  final double radius;
  const _GlassRim(this.radius);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(.75);
    if (radius == 0) {
      // Full-width headers have a polished lower lip, not a white picture frame.
      canvas.drawRect(
          Rect.fromLTWH(0, size.height - 3, size.width, 3),
          Paint()
            ..shader = const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x00FFFFFF),
                  Color(0xBFFFFFFF),
                  Color(0x1826313D)
                ]).createShader(
                Rect.fromLTWH(0, size.height - 3, size.width, 3)));
      return;
    }
    final lens = rect.deflate(3);
    if (lens.width > 0 && lens.height > 0) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              lens, Radius.circular((radius - 3).clamp(0, radius))),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..shader = const SweepGradient(center: Alignment.center, colors: [
              Color(0x08FFFFFF),
              Color(0x7FFFFFFF),
              Color(0x1526313D),
              Color(0x00FFFFFF),
              Color(0xA6FFFFFF),
              Color(0x304BC6CE),
              Color(0x08FFFFFF)
            ], stops: [
              0,
              .16,
              .3,
              .45,
              .64,
              .82,
              1
            ]).createShader(rect));
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withAlpha(250),
            Colors.white.withAlpha(20),
            Colors.white.withAlpha(210)
          ]).createShader(rect);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)), paint);
    // A second, inset edge gives the rim thickness without tinting the content.
    final inner = rect.deflate(1.5);
    if (inner.width > 0 && inner.height > 0) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              inner, Radius.circular((radius - 1.5).clamp(0, radius))),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..shader = LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withAlpha(100),
                  const Color(0xFF26313D).withAlpha(38),
                  Colors.white.withAlpha(190)
                ]).createShader(inner));
    }
  }

  @override
  bool shouldRepaint(_GlassRim oldDelegate) => oldDelegate.radius != radius;
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
                  colors: [tint.withAlpha(110), tint.withAlpha(0)])
              .createShader(rect));
    canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
                  center: const Alignment(1, .8),
                  radius: 1.1,
                  colors: [tint.withAlpha(90), tint.withAlpha(0)])
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
                Colors.white.withAlpha(175),
                Colors.white.withAlpha(45),
                tint.withAlpha(40),
                Colors.white.withAlpha(155)
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
          ..strokeWidth = 1.5
          ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withAlpha(150),
                Colors.white.withAlpha(0),
                Colors.white.withAlpha(115)
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
          blurSigma: 5,
          navigation: true,
          padding: EdgeInsets.zero,
          child: child)
      : child;
}
