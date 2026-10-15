import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentstudy/store.dart';
import 'package:dentstudy/app/app.dart';
import 'package:dentstudy/app/shared.dart' as app;
import 'package:dentstudy/app/theme_surfaces.dart';
import 'package:dentstudy/features/profile/profile_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
  });

  test('custom appearance survives a restart without changing learning events',
      () async {
    final store = StudyStore();
    await store.init();
    await store.setCustomTheme(primary: 'forest', background: 'rose');
    await store.setGlassEnabled(true);
    final restored = StudyStore();
    await restored.init();
    expect(restored.themeColorKey, 'custom');
    expect(restored.customPrimaryKey, 'forest');
    expect(restored.customBackgroundKey, 'rose');
    expect(restored.glassEnabled, isTrue);
    expect(restored.events, isEmpty);
    await expectLater(
        restored.setCustomTheme(primary: 'invalid', background: 'blue'),
        throwsException);
    expect(restored.customPrimaryKey, 'forest');
    await restored.setThemeColor('blue');
    expect(restored.customBackgroundKey, 'rose');
    await restored.setThemeColor('custom');
    expect(restored.customPrimaryKey, 'forest');
  },
      skip:
          kIsWeb); // Restart/asset loading is covered by the native test runner.

  testWidgets(
      'independent colors and glass apply across tabs without layout errors',
      (tester) async {
    if (kIsWeb) {
      app.store.prefs = await SharedPreferences.getInstance();
      app.store.questions = [];
      app.store.token = '';
    } else {
      await tester.runAsync(() => app.store.init());
    }
    await tester.pumpWidget(const DentStudy());
    await tester.pumpAndSettle();
    if (kIsWeb) {
      await tester.tap(find.text('访客模式'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('自定义'));
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    final primary = find.byKey(const ValueKey('custom-primary-color'));
    await tester.ensureVisible(primary);
    await tester.tap(primary);
    await tester.pumpAndSettle();
    await tester.tap(find.text('松绿').last);
    await tester.pumpAndSettle();
    final background = find.byKey(const ValueKey('custom-background-color'));
    await tester.ensureVisible(background);
    await tester.tap(background);
    await tester.pumpAndSettle();
    await tester.tap(find.text('玫瑰').last);
    await tester.pumpAndSettle();
    expect(app.teal, app.themeColors['forest']);
    expect(app.paper, Color.lerp(Colors.white, app.themeColors['rose'], .045));
    await tester.ensureVisible(find.text('玻璃质感'));
    await tester.tap(find.text('玻璃质感'));
    await tester.pumpAndSettle();
    expect(app.store.glassEnabled, isTrue);
    expect(find.byType(BackdropFilter), findsWidgets);
    expect(tester.widget<FrostedChrome>(find.byType(FrostedChrome)).enabled,
        isTrue);
    await tester.tap(find.text('题库'));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(NavigationBar));
    expect(Theme.of(context).colorScheme.primary, app.themeColors['forest']);
    expect(app.store.prefs.getString('customBackgroundKey'), 'rose');
    expect(app.store.prefs.getBool('glassEnabled'), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('glass backdrop stays rose when primary color changes',
      (tester) async {
    app.store.prefs = await SharedPreferences.getInstance();
    final boundaryKey = GlobalKey();
    Future<List<int>> backgroundPixels(String primary) async {
      await app.store.setCustomTheme(primary: primary, background: 'rose');
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
              child: RepaintBoundary(
                  key: boundaryKey,
                  child: SizedBox(
                      width: 400,
                      height: 400,
                      child: StudyBackdrop(
                          glass: true,
                          background: app.paper,
                          tint: app.backgroundTint,
                          child: const SizedBox.expand()))))));
      await tester.pumpAndSettle();
      final boundary = boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final pixels = (await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final result = List<int>.from(bytes.buffer.asUint8List());
        image.dispose();
        return result;
      }))!;
      // Check the actual upper-left pixels, where the old primary glow leaked.
      final offset = (30 * 400 + 30) * 4;
      expect(pixels[offset], greaterThan(pixels[offset + 1]));
      return pixels;
    }

    final greenPrimary = await backgroundPixels('forest');
    final bluePrimary = await backgroundPixels('blue');
    expect(bluePrimary, orderedEquals(greenPrimary));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('glass cards use clipped backdrop blur; plain cards do not',
      (tester) async {
    Widget surface(bool glass) => MaterialApp(
        home: Scaffold(
            body: StudySurface(
                glass: glass,
                tint: Colors.pink,
                borderColor: Colors.grey,
                child: const Text('今日计划'))));
    await tester.pumpWidget(surface(true));
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(ClipRRect), findsOneWidget);
    await tester.pumpWidget(surface(false));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'profile onboarding preloads data and allows skipping without saving',
      (tester) async {
    bool finished = false;
    Map<String, dynamic>? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await showProfileEditor(context,
                          onboarding: true,
                          initialProfile: {
                            'nickname': '口腔同学',
                            'university': '测试大学',
                            'avatar': 'book'
                          });
                      finished = true;
                    },
                    child: const Text('开始完善'))))));
    await tester.tap(find.text('开始完善'));
    await tester.pumpAndSettle();
    expect(find.text('完善个人资料'), findsOneWidget);
    expect(find.text('口腔同学'), findsOneWidget);
    expect(find.text('测试大学'), findsOneWidget);
    await tester.tap(find.text('跳过，稍后完善'));
    await tester.pumpAndSettle();
    expect(finished, isTrue);
    expect(result, isNull);
    expect(find.text('完善个人资料'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
