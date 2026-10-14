import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'shared.dart';

/// A static web welcome screen. The application is already built underneath,
/// so either action opens immediately without a second loading step.
class Entrance extends StatefulWidget {
  final Widget child;
  final void Function(BuildContext context) onLogin;
  const Entrance({super.key, required this.child, required this.onLogin});

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> {
  bool opened = false;

  void _start() => setState(() => opened = true);

  void _login() {
    setState(() => opened = true);
    widget.onLogin(context);
  }

  @override
  Widget build(BuildContext context) {
    // Native keeps the direct-to-app behavior it had before the web welcome
    // screen was introduced.
    if (!kIsWeb || opened) return widget.child;
    return Stack(children: [
      widget.child,
      _WelcomeLayer(onStart: _start, onLogin: _login),
    ]);
  }
}

class _WelcomeLayer extends StatelessWidget {
  final VoidCallback onStart;
  final VoidCallback onLogin;
  const _WelcomeLayer({required this.onStart, required this.onLogin});

  @override
  Widget build(BuildContext context) => Material(
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
                            Container(
                                width: 78,
                                height: 78,
                                decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          teal,
                                          Color.lerp(teal,
                                              const Color(0xFF2764A8), .55)!
                                        ]),
                                    borderRadius: BorderRadius.circular(22),
                                    boxShadow: [
                                      BoxShadow(
                                          color: teal.withAlpha(50),
                                          blurRadius: 18,
                                          offset: const Offset(0, 8))
                                    ]),
                                child: const Icon(Icons.auto_stories_rounded,
                                    color: Colors.white, size: 42)),
                            const SizedBox(height: 22),
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
                                    color: Colors.blueGrey, fontSize: 14)),
                            const SizedBox(height: 42),
                            SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                    onPressed: onStart,
                                    icon: const Icon(Icons.play_arrow_rounded),
                                    label: const Text('开始学习'))),
                            const SizedBox(height: 10),
                            SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                    onPressed: onLogin,
                                    icon: const Icon(Icons.person_outline),
                                    label: const Text('登录 / 注册')))
                          ]))))));
}
