import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// The blur is clipped to each visible surface, not the entire scrolling page.
class StudySurface extends StatelessWidget {
  final Widget child;
  final bool glass;
  final Color tint, borderColor, color;
  final double radius;
  final EdgeInsetsGeometry padding;
  const StudySurface(
      {super.key,
      required this.child,
      required this.glass,
      required this.tint,
      required this.borderColor,
      this.color = Colors.white,
      this.radius = 22,
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
                  color: const Color(0xFF26313D).withAlpha(14),
                  blurRadius: 22,
                  offset: const Offset(0, 8)),
              BoxShadow(color: tint.withAlpha(10), blurRadius: 28)
            ]),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
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
                              Colors.white.withAlpha(145),
                              color.withAlpha(42),
                              Colors.white.withAlpha(100)
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
                              tint.withAlpha(65),
                              tint.withAlpha(0)
                            ])),
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                gradient: RadialGradient(
                                    center: const Alignment(.9, .65),
                                    radius: 1.05,
                                    colors: [
                                  tint.withAlpha(55),
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
  const FrostedChrome({super.key, required this.enabled, required this.child});
  @override
  Widget build(BuildContext context) => enabled
      ? ClipRect(
          child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withAlpha(100),
                            Colors.white.withAlpha(25)
                          ]),
                      border: Border(
                          top: BorderSide(color: Colors.white.withAlpha(190)))),
                  child: child)))
      : child;
}
