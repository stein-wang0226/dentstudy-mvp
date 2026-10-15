import 'package:flutter/material.dart';
import '../store.dart';
import '../reminders.dart';
import 'theme_palette.dart';
import 'theme_surfaces.dart';
export 'theme_palette.dart';

final store = StudyStore();
final reminders = Reminders();
Color get teal =>
    themeColors[store.themeColorKey == 'custom'
        ? store.customPrimaryKey
        : store.themeColorKey] ??
    themeColors['teal']!;
Color get activeThemeColor => teal;
Color get ink => Color.lerp(const Color(0xFF253238), teal, .18)!;
// A constant tint ratio preserves the light/dark hierarchy across hues.
Color get backgroundTint =>
    themeColors[store.themeColorKey == 'custom'
        ? store.customBackgroundKey
        : store.themeColorKey] ??
    themeColors['teal']!;
Color get paper => Color.lerp(Colors.white, backgroundTint, .045)!;
void message(BuildContext c, String text) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(text)));
Future<void> safely(BuildContext c, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (c.mounted) message(c, e.toString());
  }
}

Widget box(Widget child, {Color? color}) => StudySurface(
    glass: store.glassEnabled,
    tint: backgroundTint,
    borderColor: ink.withAlpha(12),
    color: color ?? Colors.white,
    child: child);
Widget studyCard({required Widget child}) => store.glassEnabled
    ? Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: StudySurface(
            glass: true,
            tint: backgroundTint,
            borderColor: Colors.transparent,
            radius: 18,
            padding: EdgeInsets.zero,
            child: child))
    : Card(child: child);
Widget heading(String text, {String? sub}) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(text,
          style:
              TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: ink)),
      if (sub != null)
        Text(sub, style: const TextStyle(color: Colors.blueGrey, fontSize: 13))
    ]));
Widget pill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
        color: teal.withAlpha(16), borderRadius: BorderRadius.circular(8)),
    child: Text(text, style: TextStyle(fontSize: 12, color: teal)));

class PageBody extends StatelessWidget {
  final List<Widget> children;
  const PageBody({super.key, required this.children});
  @override
  Widget build(BuildContext context) => SafeArea(
      child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  children: children))));
}
