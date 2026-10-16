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
import 'package:dentstudy/app/glass_refraction.dart';
import 'package:dentstudy/features/profile/profile_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Opt-in visual snapshots; not golden baselines or production assets.
  if (const bool.fromEnvironment('GLASS_PREVIEW')) {
    testWidgets('render glass preview', (tester) async {
      await tester.runAsync(() async {
        final fonts = FontLoader('DentStudySans')
          ..addFont(rootBundle.load('assets/fonts/DentStudySans-Regular.otf'));
        await fonts.load();
        await (FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
            .load();
        await app.store.init();
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await app.store.setThemeColor('teal');
      await app.store.setGlassEnabled(true);
      const preview = ValueKey('glass-preview');
      await tester
          .pumpWidget(const RepaintBoundary(key: preview, child: DentStudy()));
      await tester.pumpAndSettle();
      await expectLater(find.byKey(preview),
          matchesGoldenFile('/tmp/dentstudy-liquid-glass-mobile.png'));
      await tester.drag(find.byType(ListView).first, const Offset(0, -220));
      await tester.pumpAndSettle();
      await expectLater(find.byKey(preview),
          matchesGoldenFile('/tmp/dentstudy-liquid-glass-scrolled.png'));
      tester.view.physicalSize = const Size(1280, 900);
      await tester.pumpAndSettle();
      await expectLater(find.byKey(preview),
          matchesGoldenFile('/tmp/dentstudy-liquid-glass-desktop.png'));
      await tester.pumpWidget(const SizedBox());
    });
  }

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
    expect(find.byType(FrostedChrome), findsNWidgets(2));
    expect(
        tester
            .widgetList<FrostedChrome>(find.byType(FrostedChrome))
            .every((chrome) => chrome.enabled),
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

  testWidgets('glass chrome overlays scrolling content with safe end padding',
      (tester) async {
    app.store.prefs = await SharedPreferences.getInstance();
    app.store.questions = [];
    app.store.token = '';
    app.store.events = [];
    await app.store.setGlassEnabled(true);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    await tester.pumpWidget(const DentStudy());
    await tester.pumpAndSettle();
    if (kIsWeb) {
      await tester.tap(find.text('访客模式'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.extendBody, isTrue);
    expect(scaffold.extendBodyBehindAppBar, isTrue);
    final bar = tester.element(find.byType(NavigationBar));
    expect(
        Theme.of(bar).navigationBarTheme.backgroundColor, Colors.transparent);
    expect(Theme.of(bar).appBarTheme.backgroundColor, Colors.transparent);
    final scroll = tester.widget<ListView>(find.byType(ListView).first);
    final padding = scroll.padding! as EdgeInsets;
    expect(padding.top, greaterThanOrEqualTo(100));
    expect(padding.bottom, greaterThan(100));
    final navRect = tester.getRect(find.byType(NavigationBar));
    expect(navRect.left, greaterThanOrEqualTo(12));
    expect(navRect.bottom, lessThanOrEqualTo(810));
    await tester.drag(find.byType(ListView).first, const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1280, 900);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(NavigationBar)).width, 720);
    await app.store.setGlassEnabled(false);
    await tester.pumpAndSettle();
    expect(find.byType(FrostedChrome), findsNothing);
    expect(tester.widget<Scaffold>(find.byType(Scaffold).first).extendBody,
        isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('glass cards use clipped backdrop lenses; plain cards do not',
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

  testWidgets('clear glass has no blur and a nearly transparent center',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: FrostedChrome(
                enabled: true,
                radius: 30,
                child: SizedBox(height: 72, child: Text('透明导航'))))));
    final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(filter.filter.toString(), contains('matrix'));
    expect(filter.filter.toString(), isNot(contains('blur')));
    final gradients = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .map((box) => box.gradient)
        .whereType<LinearGradient>();
    expect(gradients, hasLength(1));
    expect(gradients.single.colors[1].a, lessThan(.02));
    expect(gradients.single.colors.every((c) => c.a < .12), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lens changes real edge pixels while leaving the center intact',
      (tester) async {
    final key = GlobalKey();
    Future<List<int>> capture(bool lens) async {
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
              child: RepaintBoundary(
                  key: key,
                  child: SizedBox(
                      width: 240,
                      height: 140,
                      child: Stack(children: [
                        for (var i = 0; i < 60; i++)
                          Positioned(
                              left: i * 4,
                              top: 0,
                              bottom: 0,
                              width: 4,
                              child: ColoredBox(
                                  color:
                                      i.isEven ? Colors.white : Colors.black)),
                        if (lens)
                          const Positioned.fill(
                              child: MediaQuery(
                                  data: MediaQueryData(),
                                child: GlassContentViewport(
                                      enabled: true,
                                      child: GlassRefraction(radius: 24)))),
                      ]))))));
      await tester.pumpAndSettle();
      return (await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final result = List<int>.from(bytes.buffer.asUint8List());
        image.dispose();
        return result;
      }))!;
    }

    final plain = await capture(false), refracted = await capture(true);
    var changedEdgePixels = 0;
    for (var y = 30; y < 110; y++) {
      for (var x = 0; x < 4; x++) {
        final offset = (y * 240 + x) * 4;
        if ((plain[offset] - refracted[offset]).abs() > 15) changedEdgePixels++;
      }
      for (var x = 20; x < 220; x++) {
        final offset = (y * 240 + x) * 4;
        expect(refracted[offset], plain[offset]);
      }
    }
    expect(changedEdgePixels, greaterThan(80));
    final clip = const GlassEdgeClipper(24).getClip(const Size(240, 140));
    expect(clip.contains(const Offset(120, 70)), isFalse);
    expect(clip.contains(const Offset(1, 70)), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reflection painter updates when primary theme changes',
      (tester) async {
    Future<CustomPainter> rim(Color primary) async {
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(colorSchemeSeed: primary),
          home: const Scaffold(
              body: StudySurface(
                  glass: true,
                  tint: Colors.pink,
                  borderColor: Colors.transparent,
                  child: Text('主题边框')))));
      await tester.pumpAndSettle();
      return tester
          .widgetList<CustomPaint>(find.descendant(
              of: find.byType(StudySurface),
              matching: find.byType(CustomPaint)))
          .firstWhere((w) => w.foregroundPainter != null)
          .foregroundPainter!;
    }

    final green = await rim(Colors.green), purple = await rim(Colors.purple);
    expect(purple.shouldRepaint(green), isTrue);
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
