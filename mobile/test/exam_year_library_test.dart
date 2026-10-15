import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentstudy/models.dart';
import 'package:dentstudy/app/shared.dart' as app;
import 'package:dentstudy/features/library/catalog.dart';
import 'package:dentstudy/features/library/exam_year_catalog.dart';
import 'package:dentstudy/features/library/library_page.dart';
import 'package:dentstudy/features/practice/practice_request.dart';

Question fixture(int id,
        {String mode = '执医',
        int year = 2024,
        bool yearVerified = true,
        String source = 'past_paper'}) =>
    Question({
      'id': 'fixture-$id',
      'stem': '测试题 $id',
      'subject': '口腔修复学',
      'chapter': '测试章节',
      'type': 'A1',
      'modes': [mode],
      'year': year,
      'isDemo': false,
      'sourceType': source,
      'sourceUrl': 'https://example.invalid/test-source',
      'citation': {'verified': true},
      'reviewStatus': 'draft',
      'examProvenance': {'yearVerified': yearVerified, 'sourceVerified': true},
      'paperId': 'test-$year',
      'paperName': '$year 年口腔执医（测试资料）',
      'order': id + 1,
      'options': {'A': '甲', 'B': '乙', 'C': '丙', 'D': '丁', 'E': '戊'},
      'answer': 'E',
      'explanation': '仅用于软件测试的解析',
      'reference': '仅用于软件测试',
      'warning': '测试数据',
      'tags': <String>[]
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'archive isolates tracks, deduplicates IDs and verifies examination year',
      () {
    final a = fixture(1);
    final archive = ExamYearCatalog([
      a,
      a,
      fixture(2, year: 2023),
      fixture(3, mode: '考研', year: 2022),
      fixture(4, yearVerified: false),
      fixture(5, year: 2099),
      fixture(6, source: 'user_material'),
    ], '执医');
    expect(archive.years, [2024, 2023]);
    expect(archive.forYear(2024).map((q) => q.id), ['fixture-1']);
    expect(archive.pendingCount, 2);
    expect(QuestionCatalog.sourceLabel(fixture(4, yearVerified: false)),
        '真题来源待核验');
    expect(QuestionCatalog.sourceLabel(fixture(8, source: 'recalled_paper')),
        '考生回忆题');
    expect(
        ExamYearCatalog.yearLabel(fixture(9, source: 'user_material')), isNull);
    expect(a.options.keys, ['A', 'B', 'C', 'D', 'E']);
    expect(a.answer, 'E');
  });

  testWidgets(
      'three track entries lead to year, paper, answer and scoped practice',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    app.store.prefs = await SharedPreferences.getInstance();
    app.store.mode = '考研';
    app.store.glassEnabled = false;
    app.store.questions = [
      for (var i = 0; i < 50; i++) fixture(i),
      for (var i = 50; i < 100; i++) fixture(i, mode: '考研', year: 2023),
    ];
    app.store.events = [];
    app.store.pending = [];
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    PracticeRequest? request;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: LibraryPage(onStart: (value) async => request = value))));
    expect(find.byKey(const ValueKey('library-track-考研')), findsOneWidget);
    expect(find.byKey(const ValueKey('library-track-本科期末')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('library-track-执医')));
    await tester.pumpAndSettle();
    expect(app.store.mode, '执医');
    expect(app.store.prefs.getString('mode'), '执医');
    await tester.tap(find.text('历年试题'));
    await tester.pumpAndSettle();
    expect(find.text('2023 年'), findsNothing);
    await tester.tap(find.text('2024 年'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2024 年口腔执医（测试资料）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试题 0'));
    await tester.pumpAndSettle();
    expect(find.text('2024 年 · 真题'), findsOneWidget);
    expect(find.textContaining('戊'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始练习'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('批量练习'));
    await tester.pumpAndSettle();
    expect(request?.mode, 'batch');
    expect(request?.questions.length, 50);
    expect(
        request?.questions
            .every((q) => q.modes.contains('执医') && q.data['year'] == 2024),
        isTrue);
    expect(app.store.events, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
