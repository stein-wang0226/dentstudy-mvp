import 'package:flutter/material.dart';
import '../store.dart';
import '../reminders.dart';
import '../purchases.dart';

final store = StudyStore();
final reminders = Reminders();
final purchases = VipPurchases();
const themeColors = <String, Color>{
  'teal': Color(0xFF087F78),
  'blue': Color(0xFF2764A8),
  'purple': Color(0xFF7652A8),
  'orange': Color(0xFFB46824),
  'rose': Color(0xFFB54E6E),
};
const themeNames = {
  'teal': '青绿',
  'blue': '湖蓝',
  'purple': '紫藤',
  'orange': '暖橙',
  'rose': '玫瑰'
};
Color get teal => themeColors[store.themeColorKey] ?? themeColors['teal']!;
Color get activeThemeColor => teal;
Color get ink => Color.lerp(const Color(0xFF253238), teal, .18)!;
// A constant tint ratio preserves the light/dark hierarchy across hues.
Color get paper => Color.lerp(Colors.white, teal, .045)!;
void message(BuildContext c, String text) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(text)));
Future<void> safely(BuildContext c, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (c.mounted) message(c, e.toString());
  }
}

Widget box(Widget child, {Color? color}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ink.withAlpha(12))),
    child: Material(type: MaterialType.transparency, child: child));
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
