import 'dart:async';
import 'package:flutter/material.dart';
import 'shared.dart';
import '../features/today/today_page.dart';
import '../features/today/today_plan.dart';
import '../features/library/library_page.dart';
import '../features/notebooks/notebooks_page.dart';
import '../features/statistics/statistics_page.dart';
import '../features/profile/profile_page.dart';
import '../features/practice/practice_request.dart';
import '../features/practice/custom_practice.dart';
import '../features/practice/session_journal.dart';
import '../features/practice/session_summary.dart';
import '../features/practice/deep_session.dart';
import '../features/practice/batch_session.dart';
import '../features/practice/speed_session.dart';

class DentStudy extends StatelessWidget {
  const DentStudy({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final scheme =
            ColorScheme.fromSeed(seedColor: teal, surface: Colors.white);
        return MaterialApp(
            title: '齿间 · 口腔学习',
            debugShowCheckedModeBanner: false,
            themeAnimationDuration: const Duration(milliseconds: 250),
            theme: ThemeData(
                useMaterial3: true,
                fontFamily: 'PingFang SC',
                colorScheme: scheme,
                scaffoldBackgroundColor: paper,
                appBarTheme: AppBarTheme(
                    backgroundColor: paper,
                    surfaceTintColor: Colors.transparent,
                    foregroundColor: ink,
                    elevation: 0),
                navigationBarTheme: NavigationBarThemeData(
                    backgroundColor: Color.lerp(Colors.white, teal, .07),
                    indicatorColor: teal.withAlpha(30)),
                cardTheme: CardThemeData(
                    elevation: 0,
                    color: Colors.white,
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18))),
                textTheme: TextTheme(
                    bodyLarge: TextStyle(fontSize: 16, height: 1.6, color: ink),
                    bodyMedium:
                        TextStyle(fontSize: 14, height: 1.5, color: ink)),
                inputDecorationTheme: InputDecorationTheme(
                    filled: true,
                    fillColor: paper,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none)),
                filledButtonTheme: FilledButtonThemeData(
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))))),
            home: const Entrance(child: Home()));
      });
}

/// Plays once per application launch. Reduced-motion users see content directly.
class Entrance extends StatefulWidget {
  final Widget child;
  const Entrance({super.key, required this.child});
  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 550));
  bool started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context)) {
      controller.value = 1;
      started = true;
    } else if (!started) {
      started = true;
      controller.forward();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
      opacity: CurvedAnimation(parent: controller, curve: Curves.easeOut),
      child: SlideTransition(
          position: Tween(begin: const Offset(0, .015), end: Offset.zero)
              .animate(CurvedAnimation(
                  parent: controller, curve: Curves.easeOutCubic)),
          child: widget.child));
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  int tab = 0;
  bool opening = false, preparing = false;
  late final TodayPlan plan = TodayPlan(store);
  Timer? dayTimer;
  void _storeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    store.addListener(_storeChanged);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _ensurePlan();
      if (store.token.isNotEmpty && mounted) await safely(context, store.sync);
      await _ensurePlan();
    });
    dayTimer = Timer.periodic(const Duration(minutes: 1), (_) => _ensurePlan());
  }

  @override
  void dispose() {
    store.removeListener(_storeChanged);
    dayTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _ensurePlan();
      if (store.token.isNotEmpty) safely(context, store.sync);
    }
  }

  Future<void> _ensurePlan({bool next = false}) async {
    if (preparing) return;
    preparing = true;
    try {
      await plan.ensure(next: next);
    } finally {
      preparing = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _today() async {
    if (opening) return;
    await _ensurePlan();
    if (!mounted) return;
    final drafts =
        store.drafts.values.where((d) => d['kind'] == 'today').toList();
    if (drafts.isNotEmpty &&
        (store.due.isEmpty || drafts.first['review'] == true)) {
      await _resume(drafts.first);
      return;
    }
    if (plan.remainingReviews.isEmpty && plan.remainingNew.isEmpty ||
        plan.remainingReviews.isEmpty && store.due.isNotEmpty)
      await _ensurePlan(next: true);
    final review = plan.remainingReviews.isNotEmpty;
    final qs = review ? plan.remainingReviews : plan.remainingNew;
    if (qs.isEmpty) {
      if (mounted) message(context, '本轮计划已完成，暂时没有新的学习任务。');
      return;
    }
    await _start(PracticeRequest(qs,
        review: review,
        kind: 'today',
        label: review ? '今日计划 · 到期复习' : '今日计划 · 新题'));
  }

  Future<void> _resume(Map<String, dynamic> draft) async {
    final qs = store.resolveQuestions(draft['questionIds'] as List? ?? []);
    if (qs.isEmpty || qs.length != (draft['questionIds'] as List).length) {
      message(context, '部分题目暂不可用，已保留续练记录，请先更新题库。');
      return;
    }
    await _start(PracticeRequest(qs,
        mode: draft['practiceMode'] as String? ?? 'deep',
        review: draft['review'] == true,
        exam: draft['exam'] == true,
        kind: draft['kind'] as String? ?? 'custom',
        label: draft['label'] as String? ?? '上次练习',
        draft: draft));
  }

  Future<void> _custom() async {
    final randomDrafts =
        store.drafts.values.where((d) => d['kind'] == 'random').toList();
    if (randomDrafts.isNotEmpty) {
      final choice = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
                  title: const Text('是否继续上次刷题？'),
                  content:
                      Text(randomDrafts.first['label'] as String? ?? '随机练习'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('新建练习')),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('继续上次'))
                  ]));
      if (choice == null) return;
      if (choice) {
        await _resume(randomDrafts.first);
        return;
      }
    }
    if (!mounted) return;
    final request = await choosePractice(context);
    if (request != null) await _start(request);
  }

  Future<void> _start(PracticeRequest request) async {
    if (opening || !mounted) return;
    opening = true;
    SessionJournal? journal;
    PracticeAction? action;
    try {
      final saved = Set<String>.from(request.draft?['saved'] ?? []);
      var qs = [...request.questions];
      final state = store.learning;
      if (request.draft == null) {
        final allowed = store.catalog.learnable.map((q) => q.id).toSet();
        qs = qs
            .where((q) =>
                allowed.contains(q.id) || state.states[q.id]?.lastDay != null)
            .toList();
      }
      if (store.due.isNotEmpty &&
          qs.any((q) =>
              !saved.contains(q.id) && state.states[q.id]?.lastDay == null)) {
        message(context, '先完成今日计划中的到期复习，再继续新题。');
        return;
      }
      final remaining = store.remainingPractice;
      if (remaining == 0 && qs.any((q) => !saved.contains(q.id))) {
        message(context, '今日练习额度已用完，续练记录会保留。');
        return;
      }
      if (request.exam &&
          remaining != null &&
          qs.where((q) => !saved.contains(q.id)).length > remaining) {
        message(context, '今日剩余额度不足以完成这套卷。');
        return;
      }
      if (request.draft != null &&
          request.mode == 'batch' &&
          remaining != null &&
          qs.where((q) => !saved.contains(q.id)).length > remaining) {
        message(context, '今日剩余额度不足以提交整批练习，已保留原作答。');
        return;
      }
      if (request.draft == null && !request.exam) {
        var slots = store.remainingNew;
        qs = qs
            .where((q) {
              if (state.states[q.id]?.lastDay != null) return true;
              if (slots == 0) return false;
              slots--;
              return true;
            })
            .take(remaining ?? qs.length)
            .toList();
      }
      if (request.mode == 'speed')
        qs = qs.where((q) => q.answer != null).toList();
      if (qs.isEmpty) {
        message(context, '当前没有可练题目，请检查题库范围和今日学习目标。');
        return;
      }
      final actual = PracticeRequest(qs,
          mode: request.mode,
          review: request.review,
          exam: request.exam,
          kind: request.kind,
          label: request.label,
          draft: request.draft);
      journal = SessionJournal(store, actual);
      await journal.open();
      if (!mounted) return;
      action = await Navigator.push<PracticeAction>(
          context,
          MaterialPageRoute(
              builder: (_) => request.mode == 'batch'
                  ? BatchStudySession(
                      questions: qs,
                      store: store,
                      review: request.review,
                      journal: journal!)
                  : request.mode == 'speed'
                      ? SpeedStudySession(
                          questions: qs,
                          store: store,
                          review: request.review,
                          journal: journal!)
                      : StudySession(
                          questions: qs,
                          exam: request.exam,
                          review: request.review,
                          journal: journal!)));
    } catch (e) {
      if (mounted) message(context, '练习未能完成：$e');
    } finally {
      try {
        await journal?.close();
      } catch (e) {
        if (mounted) message(context, '练习记录保存失败，请勿清除浏览器数据：$e');
      } finally {
        opening = false;
      }
    }
    if (!mounted) return;
    if (store.token.isNotEmpty) await safely(context, store.sync);
    if (store.prefs.getBool('reminders') ?? false)
      await safely(context, () => reminders.refresh(store));
    if (!mounted) return;
    if (action == PracticeAction.home) setState(() => tab = 0);
    if (action == PracticeAction.next) {
      setState(() => tab = 0);
      await _today();
    }
    if (action == PracticeAction.mistakes && journal != null) {
      final record =
          store.sessions.where((s) => s['id'] == journal!.id).firstOrNull ??
              journal.data;
      final ids = Set<String>.from(record['eventIds'] ?? []);
      final wrong = store.learning.attempts
          .where((a) =>
              ids.contains(a['id']) &&
              (a['correct'] == false || a['grade'] == 'wrong'))
          .map((a) => a['questionId'])
          .toSet();
      await _start(PracticeRequest(store.resolveQuestions(wrong),
          review: true, label: '本次错题巩固'));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Row(children: [
              Icon(Icons.auto_stories_rounded, color: teal),
              const SizedBox(width: 9),
              const Text('齿间', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 9),
              const Flexible(
                  child: Text('DENTSTUDY',
                      style: TextStyle(fontSize: 10, letterSpacing: 2)))
            ]),
            actions: [
              DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                      value: store.mode,
                      items: ['考研', '本科期末', '执医']
                          .map(
                              (m) => DropdownMenuItem(value: m, child: Text(m)))
                          .toList(),
                      onChanged: (m) async {
                        if (m != null) {
                          await store.setMode(m);
                          await _ensurePlan();
                        }
                      })),
              const SizedBox(width: 16)
            ]),
        body: ListenableBuilder(
            listenable: store,
            builder: (c, _) => switch (tab) {
                  0 => TodayPage(
                      plan: plan,
                      onPlan: _today,
                      onCustom: _custom,
                      onResume: _resume,
                      onStart: _start),
                  1 => LibraryPage(onStart: _start),
                  2 => NotebooksPage(onStart: _start),
                  3 => StatisticsPage(onStart: _start),
                  _ => ProfilePage(),
                }),
        bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (i) async {
              setState(() => tab = i);
              if (i == 0) await _ensurePlan();
            },
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.wb_sunny_outlined), label: '今日'),
              NavigationDestination(
                  icon: Icon(Icons.grid_view_outlined), label: '题库'),
              NavigationDestination(
                  icon: Icon(Icons.bookmarks_outlined), label: '题本'),
              NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined), label: '学情'),
              NavigationDestination(
                  icon: Icon(Icons.person_outline), label: '我的')
            ]),
      );
}
