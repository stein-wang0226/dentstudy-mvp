import 'package:flutter/material.dart';
import '../../models.dart';
import '../../app/shared.dart';
import '../statistics/learning_metrics.dart';
import '../practice/practice_request.dart';
import 'question_preview.dart';
import 'catalog.dart';

class LibraryPage extends StatefulWidget {
  final StartPractice onStart;
  const LibraryPage({super.key, required this.onStart});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String? subject, chapter;
  int shown = 20;
  String previousMode = '';
  @override
  Widget build(BuildContext context) {
    if (previousMode != store.mode) {
      subject = null;
      chapter = null;
      previousMode = store.mode;
    }
    final catalog = store.catalog;
    final metrics = LearningMetrics(store.learning, store.questions);
    if (subject == null) {
      final available = catalog.subjects.where(catalog.available).toList();
      final building =
          catalog.subjects.where((s) => !catalog.available(s)).toList();
      return PageBody(children: [
        heading('题库', sub: catalog.countLabel),
        for (final name in available) ...[
          Card(
              child: ListTile(
                  contentPadding: const EdgeInsets.all(18),
                  title: Text(name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      '${catalog.material(name).length} 题 · ${catalog.material(name).map((q) => q.chapter).toSet().length} 章\n'
                      '已学 ${metrics.learned(catalog.material(name))} · 正确率 ${LearningMetrics.percent(metrics.accuracy(catalog.material(name)))} · 待复习 ${metrics.due(catalog.material(name))}\n${QuestionCatalog.statusSummary(catalog.material(name))}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => setState(() => subject = name))),
          const SizedBox(height: 8)
        ],
        if (building.isNotEmpty)
          heading('题库建设中', sub: '当前方向资料题不足 50 道，暂未开放常规练习'),
        for (final name in building)
          ListTile(
              enabled: false,
              leading: const Icon(Icons.hourglass_empty),
              title: Text(name),
              subtitle: Text('${catalog.material(name).length} 道资料题 · 题库建设中')),
        const SizedBox(height: 16),
        OutlinedButton.icon(
            onPressed: _papers,
            icon: const Icon(Icons.timer_outlined),
            label: const Text('套卷练习'))
      ]);
    }
    final qs = catalog.material(subject!);
    final chapters = qs.map((q) => q.chapter).toSet();
    return PageBody(children: [
      Row(children: [
        TextButton.icon(
            onPressed: () => setState(() {
                  if (chapter != null) {
                    chapter = null;
                  } else {
                    subject = null;
                  }
                  shown = 20;
                }),
            icon: const Icon(Icons.arrow_back),
            label: Text(chapter == null ? '全部学科' : '章节目录')),
        const Spacer(),
        TextButton.icon(
            onPressed: () => _chooseMode(chapter == null
                ? qs
                : qs.where((q) => q.chapter == chapter).toList()),
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始练习'))
      ]),
      heading(chapter ?? subject!,
          sub: chapter == null
              ? '${qs.length} 题 · ${QuestionCatalog.statusSummary(qs)}'
              : subject),
      if (chapter == null)
        for (final name in chapters)
          _chapter(name, qs.where((q) => q.chapter == name).toList(), metrics)
      else ...[
        _actions(qs.where((q) => q.chapter == chapter).toList()),
        const SizedBox(height: 14),
        for (final q in qs.where((q) => q.chapter == chapter).take(shown))
          Card(
              child: ListTile(
                  title: Text(q.stem,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(q.type),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _preview([q]))),
        if (qs.where((q) => q.chapter == chapter).length > shown)
          TextButton(
              onPressed: () => setState(() => shown += 20),
              child: const Text('再显示 20 题')),
      ]
    ]);
  }

  Future<void> _chooseMode(List<Question> qs) async {
    final mode = await showModalBottomSheet<String>(
        context: context,
        builder: (c) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(padding: EdgeInsets.all(20), child: Text('选择练习模式')),
              for (final entry
                  in {'deep': '逐题深度', 'batch': '批量练习', 'speed': '速刷'}.entries)
                ListTile(
                    title: Text(entry.value),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(c, entry.key))
            ])));
    if (mode != null && mounted)
      widget.onStart(PracticeRequest(qs,
          mode: mode,
          label: chapter == null ? subject! : '$subject · $chapter'));
  }

  Widget _chapter(String name, List<Question> qs, LearningMetrics metrics) =>
      Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(name),
                        subtitle: Text(
                            '已学 ${metrics.learned(qs)} / ${qs.length} · 错题 ${metrics.wrong(qs)}\n最近学习：${metrics.lastDay(qs)}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => setState(() {
                              chapter = name;
                              shown = 20;
                            })),
                    Semantics(
                        container: true,
                        child: LinearProgressIndicator(
                            value: qs.isEmpty
                                ? 0
                                : metrics.learned(qs) / qs.length)),
                    const SizedBox(height: 12),
                    _actions(qs)
                  ])));
  Widget _actions(List<Question> qs) {
    final due = store.learning.due(qs, DateTime.now());
    return Wrap(spacing: 8, children: [
      TextButton(
          onPressed: () => widget.onStart(
              PracticeRequest(qs, label: '${subject!} · ${qs.first.chapter}')),
          child: const Text('顺序练习')),
      TextButton(
          onPressed: due.isEmpty
              ? null
              : () => widget.onStart(PracticeRequest(due,
                  review: true, label: '${subject!} · 章节复习')),
          child: Text('章节复习 ${due.length}')),
      TextButton(onPressed: () => _preview(qs), child: const Text('查看解析'))
    ]);
  }

  void _preview(List<Question> qs) => Navigator.push(context,
      MaterialPageRoute(builder: (_) => QuestionPreviewPage(questions: qs)));
  Future<void> _papers() async {
    final groups = <String, List<Question>>{};
    for (final q in store.catalog.learnable) {
      groups.putIfAbsent(q.data['paperId'], () => []).add(q);
    }
    final qs = await showModalBottomSheet<List<Question>>(
        context: context,
        isScrollControlled: true,
        builder: (c) => SafeArea(
            child: SizedBox(
                height: MediaQuery.sizeOf(c).height * .65,
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  heading('套卷练习', sub: '资料练习卷，不等于历年真题'),
                  for (final questions in groups.values)
                    ListTile(
                        title: Text(questions.first.data['paperName']),
                        subtitle: Text('${questions.length} 题'),
                        onTap: () => Navigator.pop(c, questions))
                ]))));
    if (qs != null) {
      qs.sort(
          (a, b) => (a.data['order'] as int).compareTo(b.data['order'] as int));
      await widget.onStart(PracticeRequest(qs, exam: true, label: '套卷练习'));
    }
  }
}
