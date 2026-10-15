import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentstudy/app/shared.dart' as app;
import 'package:dentstudy/models.dart';
import 'package:dentstudy/features/library/catalog.dart';
import 'package:dentstudy/features/library/exam_year_catalog.dart';
import 'package:dentstudy/features/library/library_page.dart';
import 'package:dentstudy/features/practice/question_tools.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<Question> questions;
  Future<void> prepare(WidgetTester tester, {bool bundled = false}) async {
    questions = bundled
        ? (await tester.runAsync(() async {
            final data = jsonDecode(
                await rootBundle.loadString('assets/all_questions.json'));
            return (data['questions'] as List)
                .map((q) => Question(Map<String, dynamic>.from(q)))
                .toList();
          }))!
        : [
            for (var i = 0; i < 60; i++)
              Question({
                'id': 'source-fixture-$i',
                'stem': '来源展示测试题 $i',
                'subject': i < 50 ? '口腔修复学' : '牙周病学',
                'chapter': '测试章节',
                'type': 'A1',
                'options': {'A': '甲', 'B': '乙', 'C': '丙', 'D': '丁', 'E': '戊'},
                'answer': 'E',
                'explanation': '仅用于软件测试',
                'modes': ['执医'],
                'isDemo': false,
                'sourceType': 'open_dataset',
                'reviewStatus': 'draft',
                'reference': 'CMB / FreedomIntelligence · 测试来源展示',
                'sourceUrl': 'https://github.com/FreedomIntelligence/CMB',
                'license': 'Apache-2.0',
                'explanationSource': 'AI 辅助补充解析，待审核',
                'tags': <String>[],
                'topics': <String>[],
              }),
          ];
    SharedPreferences.setMockInitialValues({});
    app.store.prefs = await SharedPreferences.getInstance();
    app.store.questions = questions;
    app.store.events = [];
    app.store.pending = [];
    app.store.mode = '执医';
  }

  testWidgets('actual counts, fifth options and year isolation remain truthful',
      (tester) async {
    await prepare(tester, bundled: true);
    expect(questions.length, 3650);
    final catalog = QuestionCatalog(questions, '执医');
    expect(catalog.material('牙体牙髓病学').length, 50);
    expect(catalog.material('口腔修复学').length, 50);
    expect(catalog.material('口腔颌面外科学').length, 1210);
    expect(catalog.learnable.length, 1310);
    expect(catalog.available('牙周病学'), isFalse);
    expect(catalog.material('牙周病学').length, 10);
    expect(QuestionCatalog(questions, '考研').learnable.length, 3504);
    expect(ExamYearCatalog(questions, '执医').years, isEmpty);
    final q = questions.firstWhere((q) => q.id.startsWith('cmb-train-'));
    expect(q.options.length, 5);
    expect(QuestionCatalog.sourceLabel(q), '开放数据练习题');
    expect(QuestionCatalog.reviewLabel(q), '待审核');
    expect(ExamYearCatalog.yearLabel(q), isNull);
  }, skip: kIsWeb); // The browser widget runner does not serve bundled assets.

  testWidgets('source details distinguish dataset and added explanations',
      (tester) async {
    await prepare(tester);
    final q = questions.first;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(child: SourceDetails(question: q)))));
    await tester.tap(find.text('开放数据练习题 · 待审核'));
    await tester.pumpAndSettle();
    expect(find.textContaining('CMB / FreedomIntelligence'), findsOneWidget);
    expect(find.textContaining('Apache-2.0'), findsOneWidget);
    expect(find.textContaining('AI 辅助补充解析'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('building subject can preview but never starts ordinary practice',
      (tester) async {
    await prepare(tester);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var starts = 0;
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: LibraryPage(onStart: (_) async {
      starts++;
    }))));
    await tester.tap(find.byKey(const ValueKey('library-track-执医')));
    await tester.pumpAndSettle();
    final preview = find.byKey(const ValueKey('building-preview-牙周病学'));
    await tester.scrollUntilVisible(preview, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(find.textContaining('已收录题目'), findsOneWidget);
    expect(starts, 0);
    expect(app.store.events, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
