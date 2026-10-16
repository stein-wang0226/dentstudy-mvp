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
      this.blurSigma = 18,
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
                  color: const Color(0xFF26313D).withAlpha(22),
                  blurRadius: 24,
                  offset: const Offset(0, 8)),
              BoxShadow(color: tint.withAlpha(10), blurRadius: 28)
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
                              Colors.white.withAlpha(navigation ? 70 : 110),
                              color.withAlpha(navigation ? 12 : 24),
                              Colors.white.withAlpha(navigation ? 38 : 65)
                            ])),
                        child: content)))));
  }
}

/// A bright rim and a quieter lower edge read as glass rather than a white card.
class _GlassRim extends CustomPainter {
  final double radius;
  const _GlassRim(this.radius);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(.75);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withAlpha(250),
            Colors.white.withAlpha(65),
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
            ..strokeWidth = .75
            ..shader = LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withAlpha(100),
                  const Color(0xFF26313D).withAlpha(26),
                  Colors.white.withAlpha(130)
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
                child: glass
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                            gradient: RadialGradient(
                                center: const Alignment(-.85, -.8),
                                radius: .95,
                                colors: [
                              tint.withAlpha(85),
                              tint.withAlpha(0)
                            ])),
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                gradient: RadialGradient(
                                    center: const Alignment(.9, .65),
                                    radius: 1.05,
                                    colors: [
                                  tint.withAlpha(75),
                                  tint.withAlpha(0)
                                ])),
                            child: DecoratedBox(
                                decoration: BoxDecoration(
                                    gradient: RadialGradient(
                                        center: const Alignment(.05, -.1),
                                        radius: .75,
                                        colors: [Colors.white.withAlpha(185), Colors.white.withAlpha(0)])))))
                    : null)),
        child
      ]);
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
          blurSigma: 24,
          navigation: true,
          padding: EdgeInsets.zero,
          child: child)
      : child;
}
