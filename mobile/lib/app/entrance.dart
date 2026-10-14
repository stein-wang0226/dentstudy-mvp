import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'shared.dart';

/// A short, web-only welcome layer.  The application underneath is already
/// built, so choosing either action never waits for another page to load.
class Entrance extends StatefulWidget {
  final Widget child;
  final void Function(BuildContext context) onLogin;
  const Entrance({super.key, required this.child, required this.onLogin});

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1350));
  bool opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context)) {
      controller.value = 1;
    } else if (!controller.isAnimating && controller.value == 0) {
      controller.forward();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _start() => setState(() => opened = true);

  void _login() {
    setState(() => opened = true);
    widget.onLogin(context);
  }

  @override
  Widget build(BuildContext context) {
    // Native starts directly in the app, retaining the small transition that
    // existed before the web welcome layer was introduced.
    if (!kIsWeb) {
      return FadeTransition(
          opacity: CurvedAnimation(parent: controller, curve: Curves.easeOut),
          child: SlideTransition(
              position: Tween(begin: const Offset(0, .015), end: Offset.zero)
                  .animate(CurvedAnimation(
                      parent: controller, curve: Curves.easeOutCubic)),
              child: widget.child));
    }
    return Stack(children: [
      widget.child,
      IgnorePointer(
          ignoring: opened,
          child: AnimatedOpacity(
              opacity: opened ? 0 : 1,
              duration: const Duration(milliseconds: 180),
              child: _WelcomeLayer(
                  controller: controller, onStart: _start, onLogin: _login)))
    ]);
  }
}

class _WelcomeLayer extends StatelessWidget {
  final Animation<double> controller;
  final VoidCallback onStart, onLogin;
  const _WelcomeLayer(
      {required this.controller, required this.onStart, required this.onLogin});

  Animation<double> _curve(double begin, double end, Curve curve) =>
      CurvedAnimation(
          parent: controller, curve: Interval(begin, end, curve: curve));

  @override
  Widget build(BuildContext context) {
    final title = _curve(.28, .66, Curves.easeOutCubic);
    final actions = _curve(.60, 1, Curves.easeOutCubic);
    return Material(
        color: paper,
        child: SafeArea(
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 390),
                    child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedBuilder(
                                  animation: controller,
                                  builder: (_, __) => _AssembledMark(
                                      progress: controller.value)),
                              const SizedBox(height: 22),
                              FadeTransition(
                                  opacity: title,
                                  child: SlideTransition(
                                      position: Tween(
                                              begin: const Offset(0, .18),
                                              end: Offset.zero)
                                          .animate(title),
                                      child: Column(children: [
                                        Text('齿间',
                                            style: TextStyle(
                                                color: ink,
                                                fontSize: 31,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 2)),
                                        const SizedBox(height: 6),
                                        Text('DENTSTUDY',
                                            style: TextStyle(
                                                color: teal,
                                                fontSize: 12,
                                                letterSpacing: 4,
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 12),
                                        const Text('每天学一点，记牢一点。',
                                            style: TextStyle(
                                                color: Colors.blueGrey,
                                                fontSize: 14))
                                      ]))),
                              const SizedBox(height: 42),
                              FadeTransition(
                                  opacity: actions,
                                  child: SlideTransition(
                                      position: Tween(
                                              begin: const Offset(0, .12),
                                              end: Offset.zero)
                                          .animate(actions),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            FilledButton.icon(
                                                onPressed: onStart,
                                                icon: const Icon(
                                                    Icons.play_arrow_rounded),
                                                label: const Text('开始学习')),
                                            const SizedBox(height: 10),
                                            OutlinedButton.icon(
                                                onPressed: onLogin,
                                                icon: const Icon(
                                                    Icons.person_outline),
                                                label: const Text('登录 / 注册'))
                                          ])))
                            ]))))));
  }
}

/// Three book parts travel in from different directions before the logo's
/// background settles in.  The whole sequence ends in under 0.7 seconds.
class _AssembledMark extends StatelessWidget {
  final double progress;
  const _AssembledMark({required this.progress});

  double _part(double from, double to) => Curves.easeOutBack
      .transform(((progress - from) / (to - from)).clamp(0, 1))
      .clamp(0, 1)
      .toDouble();

  @override
  Widget build(BuildContext context) {
    final shell = Curves.easeOut.transform((progress / .34).clamp(0, 1));
    final left = _part(.12, .52);
    final right = _part(.2, .60);
    final ribbon = _part(.30, .70);
    return Transform.scale(
        scale: .78 + shell * .22,
        child: Opacity(
            opacity: shell,
            child: SizedBox(
                width: 78,
                height: 78,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: teal, borderRadius: BorderRadius.circular(22)),
                    child: Stack(children: [
                      _bookPart(
                          left: 13 - (1 - left) * 22,
                          top: 26,
                          width: 22,
                          height: 28,
                          radius: const BorderRadius.only(
                              topLeft: Radius.circular(4),
                              bottomLeft: Radius.circular(4))),
                      _bookPart(
                          left: 43 + (1 - right) * 22,
                          top: 26,
                          width: 22,
                          height: 28,
                          radius: const BorderRadius.only(
                              topRight: Radius.circular(4),
                              bottomRight: Radius.circular(4))),
                      Positioned(
                          left: 36,
                          top: 15 - (1 - ribbon) * 18,
                          child: Opacity(
                              opacity: ribbon,
                              child: Container(
                                  width: 7,
                                  height: 28,
                                  decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(2)))))
                    ])))));
  }

  Widget _bookPart(
          {required double left,
          required double top,
          required double width,
          required double height,
          required BorderRadius radius}) =>
      Positioned(
          left: left,
          top: top,
          child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: radius,
                  border: Border.all(color: teal.withAlpha(45), width: 1))));
}
