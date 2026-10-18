import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentstudy/app/app.dart';
import 'package:dentstudy/app/shared.dart' as app;
import 'package:dentstudy/app/motion.dart';
import 'package:dentstudy/models.dart';
import 'package:dentstudy/features/today/today_plan.dart';
import 'package:dentstudy/features/practice/deep_session.dart';
import 'package:dentstudy/features/practice/batch_session.dart';
import 'package:dentstudy/features/practice/speed_session.dart';
import 'package:dentstudy/features/practice/mode_picker.dart';

Future<void> prepare() async {
  SharedPreferences.setMockInitialValues({});
  app.store.prefs = await SharedPreferences.getInstance();
  app.store.token = '';
  app.store.mode = '考研';
  app.store.events = [];
  app.store.pending = [];
  app.store.sessions = [];
  app.store.drafts = {};
  app.store.dailyPlan = null;
  app.store.activeSessionId = null;
  app.store.questions = List.generate(
      50,
      (i) => Question({
            'id': 'motion-$i',
            'stem': '模式测试题 $i',
            'subject': '口腔修复学',
            'chapter': '测试章',
            'type': 'A1',
            'modes': ['考研'],
            'isDemo': false,
            'options': {'A': '甲', 'B': '乙', 'C': '丙', 'D': '丁'},
            'answer': 'A',
            'explanation': '测试解析',
            'reference': '软件测试',
            'tags': <String>[],
          }));
  await TodayPlan(app.store).ensure();
}

void main() {
  testWidgets('mode picker fits small screens, large text and reduced motion',
      (tester) async {
    if (const bool.fromEnvironment('MODE_PREVIEW')) {
      await tester.runAsync(() async {
        await (FontLoader('DentStudySans')
              ..addFont(
                  rootBundle.load('assets/fonts/DentStudySans-Regular.otf')))
            .load();
        await (FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
            .load();
      });
    }
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    String? result;
    const preview = ValueKey('mode-preview');
    await tester.pumpWidget(RepaintBoundary(
        key: preview,
        child: MaterialApp(
            theme: ThemeData(
                fontFamily: 'DentStudySans', colorSchemeSeed: Colors.teal),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                    textScaler: const TextScaler.linear(1.3)),
                child: child!),
            home: Builder(
                builder: (context) => Scaffold(
                    body: Center(
                        child: FilledButton(
                            onPressed: () async => result =
                                await chooseStudyMode(context,
                                    review: false, count: 10),
                            child: const Text('开始学习'))))))));
    await tester.tap(find.text('开始学习'));
    await tester.pumpAndSettle();
    expect(find.byType(ImageFiltered), findsNothing);
    if (const bool.fromEnvironment('MODE_PREVIEW')) {
      await expectLater(find.byKey(preview),
          matchesGoldenFile('/tmp/dentstudy-mode-picker.png'));
    }
    tester.view.physicalSize = const Size(320, 640);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('study-mode-speed')));
    await tester.tap(find.byKey(const ValueKey('study-mode-speed')));
    await tester.pumpAndSettle();
    expect(result, 'speed');
    expect(tester.takeException(), isNull);
  });

  testWidgets('all three modes start and resume; cancel and repeat are safe',
      (tester) async {
    // The app singleton's serialized writes stay in one fake-async zone.
    for (final mode in ['deep', 'batch', 'speed']) {
      await prepare();
      await tester.pumpWidget(const MaterialApp(home: Home()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('today-plan-action')));
      await tester.pumpAndSettle();
      expect(find.text('选择练习模式'), findsOneWidget);
      expect(find.textContaining('逐题查看解析'), findsOneWidget);
      expect(find.textContaining('先集中作答'), findsOneWidget);
      expect(find.textContaining('答对自动'), findsOneWidget);
      expect(app.store.drafts, isEmpty);
      await tester.tap(find.byKey(ValueKey('study-mode-$mode')));
      await tester.pumpAndSettle();
      final type = mode == 'deep'
          ? StudySession
          : mode == 'batch'
              ? BatchStudySession
              : SpeedStudySession;
      expect(find.byType(type), findsOneWidget);
      expect(app.store.drafts.values.single['practiceMode'], mode);
      expect(app.store.events, isEmpty);
      Navigator.of(tester.element(find.byType(type))).pop();
      await tester.pumpAndSettle();
      final id = app.store.drafts.keys.single;
      await tester.tap(find.byKey(const ValueKey('today-plan-action')));
      await tester.pumpAndSettle();
      expect(find.text('选择练习模式'), findsNothing);
      expect(find.byType(type), findsOneWidget);
      expect(app.store.drafts.keys.single, id);
      Navigator.of(tester.element(find.byType(type))).pop();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    }
    await prepare();
    await tester.pumpWidget(const MaterialApp(home: Home()));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('today-plan-action')),
    );
    button.onPressed!();
    button.onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('选择练习模式'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(app.store.drafts, isEmpty);
    expect(app.store.events, isEmpty);
    expect(app.store.sessions, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('motion blur disappears at rest and reduced motion bypasses it',
      (tester) async {
    final controller = AnimationController(
        vsync: tester, duration: const Duration(milliseconds: 300));
    addTearDown(controller.dispose);
    Widget demo(bool reduced) => MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: MotionReveal(
                animation: controller, child: const Text('动态测试'))));
    await tester.pumpWidget(demo(false));
    controller.forward();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(ImageFiltered), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(ImageFiltered), findsNothing);
    controller.value = .25;
    await tester.pumpWidget(demo(true));
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byType(Opacity), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('press scales once and cancellation restores it without a tap',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: PressFeedback(
                child: FilledButton(
                    onPressed: () => taps++, child: const Text('点击'))))));
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('点击')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, .975);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    expect(taps, 0);
    await tester.tap(find.text('点击'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });
}
