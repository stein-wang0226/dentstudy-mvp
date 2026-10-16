import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Transient blur only: remove the compositing layer at rest so clear glass
/// keeps sampling the real backdrop. Accessibility disables all extra motion.
class MotionReveal extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  const MotionReveal({super.key, required this.animation, required this.child});
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final t = animation.value.clamp(0.0, 1.0);
          if (t == 1) return child!;
          final eased = Curves.easeOutCubic.transform(t);
          final spring = Curves.easeOutBack.transform(t);
          return Opacity(
              opacity: eased,
              child: Transform.translate(
                  offset: Offset(0, 18 * (1 - eased)),
                  child: Transform.scale(
                      scale: .96 + .04 * spring,
                      child: ImageFiltered(
                          imageFilter: ui.ImageFilter.blur(
                              sigmaX: 2.5 * (1 - eased),
                              sigmaY: 2.5 * (1 - eased)),
                          child: child))));
        });
  }
}

class StudyPageTransitions extends PageTransitionsBuilder {
  const StudyPageTransitions();
  @override
  Widget buildTransitions<T>(
          PageRoute<T> route,
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child) =>
      MotionReveal(animation: animation, child: child);
}

/// Listener adds tactile movement without owning taps, focus, or semantics.
class PressFeedback extends StatefulWidget {
  final Widget child;
  const PressFeedback({super.key, required this.child});
  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback> {
  bool pressed = false;
  void change(bool value) {
    if (pressed != value) setState(() => pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Listener(
        onPointerDown: (_) => change(true),
        onPointerUp: (_) => change(false),
        onPointerCancel: (_) => change(false),
        child: AnimatedScale(
            scale: pressed && !reduced ? .975 : 1,
            duration: reduced
                ? Duration.zero
                : Duration(milliseconds: pressed ? 90 : 240),
            curve: pressed ? Curves.easeOutCubic : Curves.easeOutBack,
            child: widget.child));
  }
}
