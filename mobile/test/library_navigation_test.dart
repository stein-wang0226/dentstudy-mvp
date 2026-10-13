import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentstudy/app/shared.dart' as app;
import 'package:dentstudy/models.dart';
import 'package:dentstudy/features/library/question_preview.dart';
import 'package:dentstudy/features/library/question_search.dart';
import 'package:dentstudy/features/library/question_search_page.dart';
import 'package:dentstudy/features/library/reading_sequence.dart';

Question question(String id, String chapter, String stem,
        {String explanation = '解析', String subject = '口腔修复学'}) =>
    Question({
      'id': id,
      'subject': subject,
      'chapter': chapter,
      'stem': stem,
      'type': 'A1',
      'options': {'A': 'RPA', 'B': '选项二', 'C': '选项三', 'D': '选项四'},
      'answer': 'A',
      'explanation': explanation,
      'tags': <String>[],
      'reference': '资料',
      'sourceType': 'user_material',
      'reviewStatus': 'draft',
      'modes': ['考研'],
      'isDemo': false,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final qs = [
    question('a', '第一章', '𬌗力测试'),
    question('b', '第一章', '第二道题'),
    question('c', '第二章', '末章题目'),
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    app.store.prefs = await SharedPreferences.getInstance();
    app.store.userId = 'guest';
    app.store.mode = '考研';
    app.store.events = [];
    app.store.pending = [];
    app.store.questions = qs;
  });

  test('chapter sequence groups interleaved content without losing IDs', () {
    final sequence = ReadingSequence([qs[0], qs[2], qs[1]], byChapter: true);
    expect(sequence.questions.map((q) => q.id), ['a', 'b', 'c']);
    expect(sequence.startIndex(questionId: 'b'), 1);
    expect(sequence.endsChapter(0), isFalse);
    expect(sequence.endsChapter(1), isTrue);
    expect(sequence.chapterPosition(1), 2);
    expect(sequence.chapterCount(1), 2);
    expect(sequence.startIndex(chapter: '第二章'), 2);
  });

  test('search includes options/analysis, AND terms, scope and occlusion alias',
      () {
    final other =
        question('d', '第三章', '牙周炎', subject: '牙周病学', explanation: '𬌗力检查');
    final index = QuestionSearchIndex([...qs, other]);
    expect(index.search('咬合力').map((q) => q.id), ['a', 'd']);
    expect(index.search('𬌗力').map((q) => q.id), ['a', 'd']);
    expect(index.search('  牙周炎   rpa ').map((q) => q.id), ['d']);
    expect(index.search('咬合力', subject: '牙周病学').single.id, 'd');
    expect(index.search('rpa', chapter: '第二章').single.id, 'c');
    expect(index.search('牙周炎 不存在'), isEmpty);
    expect(index.search('   '), isEmpty);
    expect(other.stem, '牙周炎');
  });

  testWidgets(
      'mobile reader starts on tapped question, crosses chapters and remembers without answers',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: QuestionPreviewPage(
            questions: qs, initialQuestionId: 'b', chapterNavigation: true)));
    await tester.pumpAndSettle();
    expect(find.text('本章第 2 / 2 题'), findsOneWidget);
    expect(find.text('下一章'), findsOneWidget);
    await tester.tap(find.byTooltip('题目目录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('𬌗力测试'));
    await tester.pumpAndSettle();
    expect(find.text('本章第 1 / 2 题'), findsOneWidget);
    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一章'));
    await tester.pumpAndSettle();
    expect(find.text('本章第 1 / 1 题'), findsOneWidget);
    expect(find.text('返回章节目录'), findsOneWidget);
    expect(app.store.prefs.getString('reading:guest:考研:口腔修复学:第一章'), 'b');
    expect(app.store.prefs.getString('reading:guest:考研:口腔修复学:第二章'), 'c');
    expect(app.store.events, isEmpty);
    expect(app.store.pending, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(
        home: QuestionPreviewPage(
            questions: qs, initialChapter: '第一章', chapterNavigation: true)));
    await tester.pumpAndSettle();
    expect(find.text('本章第 2 / 2 题'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    app.store.userId = 'another-account';
    await tester.pumpWidget(MaterialApp(
        home: QuestionPreviewPage(
            questions: qs, initialChapter: '第一章', chapterNavigation: true)));
    await tester.pumpAndSettle();
    expect(find.text('本章第 1 / 2 题'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'search result opens at selected result and retains query on return',
      (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: QuestionSearchPage(questions: qs)));
    await tester.enterText(find.byType(TextField), 'rpa');
    await tester.pumpAndSettle();
    expect(find.text('找到 3 道题'), findsOneWidget);
    await tester.ensureVisible(find.text('第二道题'));
    await tester.tap(find.text('第二道题'));
    await tester.pumpAndSettle();
    expect(find.text('第 2 / 3 题'), findsOneWidget);
    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();
    expect(find.text('返回列表'), findsOneWidget);
    await tester.tap(find.text('返回列表'));
    await tester.pumpAndSettle();
    expect(find.text('找到 3 道题'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'rpa');
    expect(app.store.events, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
