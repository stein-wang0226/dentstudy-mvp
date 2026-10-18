import 'dart:async';
import 'package:flutter/material.dart';
import 'shared.dart';
import 'entrance.dart';
import 'theme_surfaces.dart';
import 'glass_refraction.dart';
import 'motion.dart';
import '../features/practice/mode_picker.dart';
import '../features/today/today_page.dart';
import '../features/today/today_plan.dart';
import '../features/library/library_page.dart';
import '../features/notebooks/notebooks_page.dart';
import '../features/statistics/statistics_page.dart';
import '../features/profile/profile_page.dart';
import '../features/assistant/xiaochi_assistant.dart';
import '../features/profile/policy_page.dart';
import '../features/practice/practice_request.dart';
import '../features/practice/custom_practice.dart';
import '../features/practice/session_journal.dart';
import '../features/practice/session_summary.dart';
import '../features/practice/deep_session.dart';
import '../features/practice/batch_session.dart';
import '../features/practice/speed_session.dart';
import '../models.dart';

class DentStudy extends StatelessWidget {
  const DentStudy({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final hasCustomBackground = store.hasCustomBackground;
        final transparentChrome = store.glassEnabled || hasCustomBackground;
        final scheme =
            ColorScheme.fromSeed(seedColor: teal, surface: Colors.white)
                .copyWith(primary: teal, onPrimary: Colors.white);
        return MaterialApp(
            title: '齿间 · 口腔学习',
            debugShowCheckedModeBanner: false,
            themeAnimationDuration: const Duration(milliseconds: 250),
            builder: (context, child) => StudyBackdrop(
                glass: store.glassEnabled,
                background: paper,
                tint: backgroundTint,
                image: hasCustomBackground
                    ? MemoryImage(store.customBackgroundImageBytes!)
                    : null,
                imageScale: store.customBackgroundScale,
                imageOpacity: store.customBackgroundOpacity,
                child: child ?? const SizedBox.shrink()),
            theme: ThemeData(
                pageTransitionsTheme: const PageTransitionsTheme(builders: {
                  TargetPlatform.android: StudyPageTransitions(),
                  TargetPlatform.macOS: StudyPageTransitions(),
                  TargetPlatform.windows: StudyPageTransitions(),
                  TargetPlatform.linux: StudyPageTransitions(),
                  // Keep one compatible transition implementation across the
                  // project's supported Flutter 3.35+ range. The previous
                  // Cupertino builder name is unavailable in 3.35 CI.
                  TargetPlatform.iOS: StudyPageTransitions(),
                }),
                useMaterial3: true,
                fontFamily: 'DentStudySans',
                fontFamilyFallback: const [
                  'DentStudySymbols',
                  'DentStudyMath',
                  'PingFang SC',
                  'Microsoft YaHei',
                  'sans-serif'
                ],
                colorScheme: scheme,
                scaffoldBackgroundColor:
                    transparentChrome ? Colors.transparent : paper,
                appBarTheme: AppBarTheme(
                    backgroundColor:
                        transparentChrome ? Colors.transparent : paper,
                    surfaceTintColor: Colors.transparent,
                    foregroundColor: ink,
                    elevation: 0,
                    scrolledUnderElevation: 0),
                navigationBarTheme: NavigationBarThemeData(
                    backgroundColor: transparentChrome
                        ? Colors.transparent
                        : Color.lerp(Colors.white, backgroundTint, .07),
                    surfaceTintColor: Colors.transparent,
                    elevation: 0,
                    indicatorColor: teal.withAlpha(30)),
                cardTheme: CardThemeData(
                    elevation: 0,
                    color: store.glassEnabled
                        ? Colors.white.withAlpha(175)
                        : Colors.white,
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: store.glassEnabled
                            ? BorderSide(color: Colors.white.withAlpha(220))
                            : BorderSide.none)),
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

class Home extends StatefulWidget {
  final int initialTab;
  const Home({super.key, this.initialTab = 0});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  late int tab;
  bool opening = false, preparing = false, choosingMode = false;
  late final TodayPlan plan = TodayPlan(store);
  Timer? dayTimer;
  void _storeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    tab = widget.initialTab;
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
    if (opening || preparing || choosingMode) return;
    await _ensurePlan();
    if (!mounted) return;
    final drafts =
        store.drafts.values.where((d) => d['kind'] == 'today').toList();
    if (drafts.isNotEmpty) {
      await _resume(drafts.first);
      return;
    }
    if (plan.remainingNew.isEmpty) await _ensurePlan(next: true);
    final qs = plan.remainingNew;
    if (qs.isEmpty) {
      if (mounted) message(context, '本轮计划已完成，暂时没有新的学习任务。');
      return;
    }
    if (!mounted || choosingMode) return;
    choosingMode = true;
    String? mode;
    try {
      mode = await chooseStudyMode(context,
          review: false,
          count: qs.length,
          helpText: '想调整每日新题数：打开「我的」→「每日学习目标」，修改“每日新题上限”即可。');
    } finally {
      choosingMode = false;
    }
    if (mode == null || !mounted) return;
    await _start(PracticeRequest(qs,
        mode: mode, review: false, kind: 'today', label: '今日计划 · 新题'));
  }

  Future<void> _resume(Map<String, dynamic> draft) async {
    final originalIds = List<String>.from(draft['questionIds'] as List? ?? []);
    final qs = store.resolveQuestions(originalIds);
    if (qs.isEmpty) {
      await store.discardDraft(draft['id'] as String);
      if (mounted) message(context, '上次练习中的题目已不在当前题库，旧续练记录已自动清理。');
      return;
    }
    var usableDraft = draft;
    if (qs.length != originalIds.length) {
      final available = qs.map((q) => q.id).toSet();
      final oldIndex = (draft['index'] as num? ?? 0)
          .toInt()
          .clamp(0, originalIds.length)
          .toInt();
      Map<String, dynamic> retainedMap(String key) {
        final raw = draft[key];
        if (raw is! Map) return <String, dynamic>{};
        final copy = Map<String, dynamic>.from(raw);
        copy.removeWhere((id, _) => !available.contains(id));
        return copy;
      }

      usableDraft = {
        ...draft,
        'questionIds': qs.map((q) => q.id).toList(),
        'saved': List<String>.from(draft['saved'] as List? ?? [])
            .where(available.contains)
            .toList(),
        'answers': retainedMap('answers'),
        'grades': retainedMap('grades'),
        'index': originalIds
            .take(oldIndex)
            .where(available.contains)
            .length
            .clamp(0, qs.length - 1)
            .toInt(),
      };
      if (mounted) {
        message(context,
            '已跳过 ${originalIds.length - qs.length} 道不再提供的旧题，继续剩余 ${qs.length} 题。');
      }
    }
    await _start(PracticeRequest(qs,
        mode: usableDraft['practiceMode'] as String? ?? 'deep',
        review: usableDraft['review'] == true,
        exam: usableDraft['exam'] == true,
        kind: usableDraft['kind'] as String? ?? 'custom',
        label: usableDraft['label'] as String? ?? '上次练习',
        draft: usableDraft));
  }

  List<Question> _yesterdayQuestions({bool wrongOnly = false}) {
    final yesterday = dayOf(DateTime.now().subtract(const Duration(days: 1)));
    final ids = <String>{};
    for (final event in store.events) {
      final at = event['at'];
      if (event['kind'] != 'review' || at is! String) continue;
      try {
        if (dayOf(DateTime.parse(at)) == yesterday &&
            event['questionId'] is String) {
          ids.add(event['questionId'] as String);
        }
      } catch (_) {}
    }
    final questions = store.resolveQuestions(ids);
    return wrongOnly
        ? questions
            .where((q) => store.learning.states[q.id]?.wrong == true)
            .toList()
        : questions;
  }

  Future<void> _reviewYesterday() async {
    if (opening || choosingMode) return;
    final drafts = store.drafts.values
        .where((draft) => draft['kind'] == 'yesterdayReview')
        .toList();
    if (drafts.isNotEmpty) {
      await _resume(drafts.first);
      return;
    }
    final all = _yesterdayQuestions();
    final wrong = _yesterdayQuestions(wrongOnly: true);
    if (all.isEmpty) {
      if (mounted) message(context, '昨天没有可复习的作答记录。');
      return;
    }
    final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('复习昨日题目',
                          style: TextStyle(
                              fontSize: 21, fontWeight: FontWeight.bold))),
                  const SizedBox(height: 8),
                  ListTile(
                      leading: const Icon(Icons.history_edu_outlined),
                      title: Text('昨日全部题目 · ${all.length} 题'),
                      subtitle: const Text('重新巩固昨天完成的题目'),
                      onTap: () => Navigator.pop(sheetContext, 'all')),
                  ListTile(
                      enabled: wrong.isNotEmpty,
                      leading: const Icon(Icons.error_outline),
                      title: Text('昨日错题 · ${wrong.length} 题'),
                      subtitle: Text(wrong.isEmpty ? '昨天没有错题' : '优先订正昨天做错的题目'),
                      onTap: wrong.isEmpty
                          ? null
                          : () => Navigator.pop(sheetContext, 'wrong')),
                ]))));
    if (choice == null) return;
    final questions = choice == 'wrong' ? wrong : all;
    choosingMode = true;
    String? mode;
    try {
      mode = await chooseStudyMode(context,
          review: true,
          count: questions.length,
          helpText: '这是额外复习，不会占用今日新题名额。');
    } finally {
      choosingMode = false;
    }
    if (mode == null || !mounted) return;
    await _start(PracticeRequest(questions,
        mode: mode,
        review: true,
        kind: 'yesterdayReview',
        label: choice == 'wrong' ? '昨日错题复习' : '昨日全部题目复习'));
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
        final allowed = {
          ...store.catalog.learnable.map((q) => q.id),
          ...store.importedQuestionIds
        };
        qs = qs
            .where((q) =>
                allowed.contains(q.id) || state.states[q.id]?.lastDay != null)
            .toList();
      }
      final remaining = store.remainingPractice;
      if (remaining == 0 && qs.any((q) => !saved.contains(q.id))) {
        message(context, '今日练习额度已用完，续练记录会保留。');
        return;
      }
      if (request.exam &&
          qs.where((q) => !saved.contains(q.id)).length > remaining) {
        message(context, '今日剩余额度不足以完成这套卷。');
        return;
      }
      if (request.draft != null &&
          request.mode == 'batch' &&
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
            .take(remaining)
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
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        Scaffold(
          extendBody: store.glassEnabled,
          extendBodyBehindAppBar: store.glassEnabled,
          appBar: AppBar(
              flexibleSpace: store.glassEnabled
                  ? const FrostedChrome(enabled: true, child: SizedBox.expand())
                  : null,
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
                TextButton.icon(
                    onPressed: () => _showContactAuthor(context),
                    icon: const Icon(Icons.mail_outline, size: 19),
                    label: const Text('联系作者')),
                const SizedBox(width: 8)
              ]),
          body: GlassContentViewport(
              enabled: store.glassEnabled,
              child: ListenableBuilder(
                  listenable: store,
                  builder: (c, _) => switch (tab) {
                        0 => TodayPage(
                            plan: plan,
                            onPlan: _today,
                            onReviewYesterday: _reviewYesterday,
                            onCustom: _custom,
                            onResume: _resume,
                            onModeChanged: (mode) async {
                              await store.setMode(mode);
                              await _ensurePlan();
                            },
                            onStart: _start),
                        1 => LibraryPage(onStart: _start),
                        2 => NotebooksPage(onStart: _start),
                        3 => StatisticsPage(onStart: _start),
                        _ => ProfilePage(onStart: _start),
                      })),
          bottomNavigationBar: _navigation(),
        ),
        const XiaochiAssistant(),
      ]);

  Widget _navigation() {
    final navigation = NavigationBar(
        height: store.glassEnabled ? 72 : null,
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
          NavigationDestination(icon: Icon(Icons.person_outline), label: '我的')
        ]);
    if (!store.glassEnabled) return navigation;
    return SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Align(
            heightFactor: 1,
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: FrostedChrome(
                    enabled: true, radius: 30, child: navigation))));
  }
}

void _showContactAuthor(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * .88),
            child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                children: [
                  const Text('联系作者',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  const Text('有问题、建议或合作想法都可以联系我；一般会在 24 小时内回复。',
                      style: TextStyle(color: Colors.blueGrey)),
                  const SizedBox(height: 18),
                  const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.email_outlined),
                      title: Text('邮箱'),
                      subtitle: SelectableText('dentstudy1126@aka.yeah.net')),
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const PolicyPage()));
                      },
                      icon: const Icon(Icons.copyright_outlined),
                      label: const Text('版权投诉与数据删除')),
                  const SizedBox(height: 10),
                  const Text('微信',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('扫描二维码添加好友；请在好友申请中注明来意，例如“DentStudy 用户反馈”。',
                      style: TextStyle(fontSize: 13, color: Colors.blueGrey)),
                  const SizedBox(height: 14),
                  Center(
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.asset('assets/contact_wechat.jpg',
                              width: 280,
                              fit: BoxFit.contain,
                              semanticLabel: '作者微信二维码')))
                ]))));
