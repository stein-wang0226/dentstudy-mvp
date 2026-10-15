import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Glossy, translucent surfaces avoid a blur layer for every scrolling card.
/// Real backdrop blur is reserved for the fixed navigation chrome.
class StudySurface extends StatelessWidget {
  final Widget child;
  final bool glass;
  final Color accent, borderColor, color;
  final double radius;
  final EdgeInsetsGeometry padding;
  const StudySurface(
      {super.key,
      required this.child,
      required this.glass,
      required this.accent,
      required this.borderColor,
      this.color = Colors.white,
      this.radius = 22,
      this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
          color: glass ? null : color,
          gradient: glass
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                      Color.lerp(color, Colors.white, .5)!.withAlpha(225),
                      color.withAlpha(155)
                    ])
              : null,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
              color: glass ? Colors.white.withAlpha(220) : borderColor),
          boxShadow: glass
              ? [
                  BoxShadow(
                      color: accent.withAlpha(16),
                      blurRadius: 24,
                      offset: const Offset(0, 8)),
                  BoxShadow(
                      color: Colors.white.withAlpha(150),
                      blurRadius: 2,
                      offset: const Offset(-1, -1))
                ]
              : []),
      child: Material(type: MaterialType.transparency, child: child));
}

class StudyBackdrop extends StatelessWidget {
  final Widget child;
  final bool glass;
  final Color background, tint, accent;
  const StudyBackdrop(
      {super.key,
      required this.child,
      required this.glass,
      required this.background,
      required this.tint,
      required this.accent});
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
                                radius: 1.3,
                                colors: [
                              accent.withAlpha(28),
                              accent.withAlpha(0)
                            ])),
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                gradient: RadialGradient(
                                    center: const Alignment(.9, .65),
                                    radius: 1.15,
                                    colors: [
                              tint.withAlpha(35),
                              tint.withAlpha(0)
                            ]))))
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
              filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: DecoratedBox(
                  decoration: BoxDecoration(
                      border: Border(
                          top: BorderSide(color: Colors.white.withAlpha(190)))),
                  child: child)))
      : child;
}
