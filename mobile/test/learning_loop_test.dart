import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentstudy/store.dart';
import 'package:dentstudy/models.dart';
import 'package:dentstudy/features/library/catalog.dart';
import 'package:dentstudy/features/today/today_plan.dart';
import 'package:dentstudy/features/practice/practice_request.dart';
import 'package:dentstudy/features/practice/session_journal.dart';
import 'package:dentstudy/features/practice/batch_session.dart';
import 'package:dentstudy/features/practice/speed_session.dart';
import 'package:dentstudy/features/practice/session_summary.dart';
import 'package:dentstudy/app/app.dart';
import 'package:dentstudy/features/profile/profile_page.dart';
import 'package:dentstudy/app/shared.dart' as app;

Question q(int n, {bool demo = false, String subject = '主学科'}) => Question({
      'id': 'q$n',
      'stem': '测试题 $n',
      'answer': 'A',
      'options': {'A': '正确', 'B': '错误', 'C': '其他', 'D': '另外'},
      'subject': subject,
      'chapter': '第一章',
      'type': 'A1',
      'modes': ['考研'],
      'isDemo': demo,
      'reviewStatus': 'draft',
      'sourceType': 'user_material',
      'citation': {'verified': false},
      'explanation': '测试解析',
      'reference': '测试资料',
      'tags': <String>[],
    });
Future<StudyStore> freshStore() async {
  SharedPreferences.setMockInitialValues({});
  final store = StudyStore();
  store.prefs = await SharedPreferences.getInstance();
  store.questions = List.generate(60, q);
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'theme selection refreshes foreground and pale background together',
      (tester) async {
    final local = await freshStore();
    app.store.prefs = local.prefs;
    app.store.questions = local.questions;
    app.store.themeColorKey = 'teal';
    await tester.pumpWidget(const DentStudy());
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('湖蓝'));
    await tester.tap(find.byTooltip('湖蓝'));
    await tester.pumpAndSettle();
    expect(app.store.themeColorKey, 'blue');
    final icon = tester.widget<Icon>(find.byIcon(Icons.auto_stories_rounded));
    expect(icon.color, app.themeColors['blue']);
    final context = tester.element(find.byType(ProfilePage).first);
    expect(Theme.of(context).scaffoldBackgroundColor,
        Color.lerp(Colors.white, app.themeColors['blue'], .045));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('completed summary shows actual result and all follow-up actions',
      (tester) async {
    final store = await freshStore();
    final journal =
        SessionJournal(store, PracticeRequest([q(0)], label: '测试章节'));
    await journal.open();
    await store.add(
        'q0', 'review', {'answer': 'B', 'grade': 'wrong', 'mode': 'practice'});
    await journal.capture({'elapsedSeconds': 80, 'finished': true});
    await journal.finish();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: SessionSummary(journal: journal)))));
    expect(find.text('完成 1 题'), findsOneWidget);
    expect(find.textContaining('正确率 0% · 错题 1 题'), findsOneWidget);
    expect(find.text('复习错题 1'), findsOneWidget);
    expect(find.text('继续学习'), findsOneWidget);
    expect(find.text('返回今日'), findsOneWidget);
    expect(find.textContaining('下次复习'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await journal.close();
    expect(store.drafts, isEmpty);
    expect(store.sessions, hasLength(1));
  });
  test('catalogue gates by non-demo count and examination track', () {
    final qs = [
      for (var i = 0; i < 49; i++) q(i),
      q(99, demo: true),
      q(100, subject: '占位学科', demo: true)
    ];
    expect(QuestionCatalog(qs, '考研').learnable, isEmpty);
    qs.add(q(50));
    expect(QuestionCatalog(qs, '考研').learnable.length, 50);
    expect(QuestionCatalog(qs, '执医').learnable, isEmpty);
    expect(QuestionCatalog.reviewLabel(q(0)), '待审核');
  });
  test('downloaded cache survives default composite bank initialization',
      () async {
    SharedPreferences.setMockInitialValues({
      'bank': jsonEncode({
        'questions': [q(9999).data]
      })
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
    final store = StudyStore();
    await store.init();
    expect(store.questions.any((q) => q.id == 'q9999'), isTrue);
    expect(store.questions.length, 3521);
  });
  test('daily plan is bounded, stable and review-first', () async {
    final store = await freshStore();
    store.dailyNewLimit = 1999;
    final plan = TodayPlan(store);
    await plan.ensure();
    expect(plan.fresh.length, 10);
    await store.add('q0', 'review',
        {'answer': 'A', 'grade': 'mastered', 'mode': 'practice'});
    await plan.ensure();
    expect(plan.total, 10);
    expect(plan.completed, 1);
    final past = DateTime.now()
        .subtract(const Duration(days: 10))
        .toUtc()
        .toIso8601String();
    store.events = [
      for (var i = 0; i < 25; i++)
        {
          'id': 'e$i',
          'at': past,
          'questionId': 'q$i',
          'kind': 'review',
          'value': {'answer': 'B', 'grade': 'wrong', 'mode': 'practice'}
        }
    ];
    await plan.ensure(next: true);
    expect(plan.reviews.length, 20);
    expect(plan.fresh, isEmpty);
  });
  test(
      'answer event and saved IDs persist together; finishing keeps other drafts',
      () async {
    final store = await freshStore();
    await store.saveDraft({
      'id': 'other',
      'questionIds': ['q10']
    });
    final journal = SessionJournal(store, PracticeRequest([q(0), q(1)]));
    await journal.open();
    await journal.capture({
      'answers': {'q0': 'B'},
      'index': 0
    });
    await store.add(
        'q0', 'review', {'answer': 'B', 'grade': 'wrong', 'mode': 'practice'});
    final persisted = jsonDecode(store.prefs.getString('account:guest')!);
    expect(persisted['drafts'][journal.id]['saved'], ['q0']);
    await journal.capture({'saved': <String>[]});
    expect(journal.saved, contains('q0'));
    await journal.finish();
    await journal.close();
    expect(store.drafts.containsKey('other'), isTrue);
    expect(store.sessions.single['eventIds'].length, 1);
  });
  testWidgets(
      'batch checkpoint restores answers and review phase without submission',
      (tester) async {
    final store = await freshStore();
    final initial =
        SessionJournal(store, PracticeRequest([q(0), q(1)], mode: 'batch'));
    await initial.open();
    await initial.capture({
      'index': 1,
      'answers': {'q0': 'A', 'q1': 'B'},
      'grades': {'q1': 'wrong'},
      'reviewing': true
    });
    await initial.close();
    final resumed = SessionJournal(
        store,
        PracticeRequest([q(0), q(1)],
            mode: 'batch', draft: store.drafts[initial.id]));
    await resumed.open();
    await tester.pumpWidget(MaterialApp(
        home: BatchStudySession(
            questions: [q(0), q(1)], store: store, journal: resumed)));
    expect(find.text('统一查看解析'), findsOneWidget);
    expect(find.text('你的作答：B'), findsOneWidget);
    expect(store.events, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await resumed.close();
  });
  testWidgets('speed restores saved wrong answer without duplicating its event',
      (tester) async {
    final store = await freshStore();
    final initial =
        SessionJournal(store, PracticeRequest([q(0), q(1)], mode: 'speed'));
    await initial.open();
    await initial.capture({
      'answers': {'q0': 'B'}
    });
    await store.add(
        'q0', 'review', {'answer': 'B', 'grade': 'wrong', 'mode': 'speed'});
    await initial.capture({});
    await initial.close();
    final resumed = SessionJournal(
        store,
        PracticeRequest([q(0), q(1)],
            mode: 'speed', draft: store.drafts[initial.id]));
    await resumed.open();
    await tester.pumpWidget(MaterialApp(
        home: SpeedStudySession(
            questions: [q(0), q(1)],
            store: store,
            review: false,
            journal: resumed)));
    await tester.scrollUntilVisible(find.text('继续下一题'), 250);
    await tester.tap(find.text('继续下一题'));
    await tester.pump();
    expect(store.events.length, 1);
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await resumed.close();
  });
}
