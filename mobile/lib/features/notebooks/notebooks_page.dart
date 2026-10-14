import 'package:flutter/material.dart';
import '../../app/shared.dart';
import '../../models.dart';
import '../practice/practice_request.dart';
import '../library/question_preview.dart';
import '../library/question_search.dart';
import '../statistics/learning_metrics.dart';

class NotebooksPage extends StatefulWidget {
  final StartPractice onStart;
  const NotebooksPage({super.key, required this.onStart});
  @override
  State<NotebooksPage> createState() => _NotebooksPageState();
}

class _NotebooksPageState extends State<NotebooksPage> {
  String kind = '错题', subject = '全部', chapter = '全部', keyword = '';
  String type = '全部', tag = '全部', school = '全部', year = '全部';
  bool filtering = false;
  int shown = 20;
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = store.learning;
    final metrics = LearningMetrics(state, store.questions);
    final groups = <String, List<Question>>{
      '错题': store.questions
          .where((q) => state.states[q.id]?.wrong == true)
          .toList(),
      '收藏': store.questions
          .where((q) => state.states[q.id]?.favorite == true)
          .toList(),
      '疑问题': store.questions
          .where((q) => state.states[q.id]?.grade == 'guessed')
          .toList(),
      '笔记': store.questions
          .where((q) => (state.states[q.id]?.note.trim().isNotEmpty ?? false))
          .toList(),
    };
    final activeMistakes = metrics.activeMistakes(groups['错题']!);
    final recovered = groups['错题']!.where(metrics.isRecoveredMistake).toList()
      ..sort((a, b) => (state.states[b.id]?.lastDay ?? '')
          .compareTo(state.states[a.id]?.lastDay ?? ''));
    final source =
        kind == '错题' ? [...activeMistakes, ...recovered] : groups[kind]!;
    final justWrong = activeMistakes.where(metrics.isWrongToday).toList();
    final repeated = activeMistakes
        .where((q) => !metrics.isWrongToday(q) && metrics.isRepeatedMistake(q))
        .toList();
    final matches = keyword.isEmpty
        ? null
        : QuestionSearchIndex(source).search(keyword).map((q) => q.id).toSet();
    final qs = source
        .where((q) =>
            (subject == '全部' || q.subject == subject) &&
            (chapter == '全部' || q.chapter == chapter) &&
            (type == '全部' || q.type == type) &&
            (tag == '全部' || q.tags.contains(tag)) &&
            (school == '全部' || q.data['school'] == school) &&
            (year == '全部' || q.data['year'].toString() == year) &&
            (matches == null || matches.contains(q.id)))
        .toList();
    var newSlots = store.due.isEmpty ? store.remainingNew : 0;
    final learnable = store.catalog.learnable.map((q) => q.id).toSet();
    final practice = qs
        .where((q) {
          if (state.states[q.id]?.lastDay != null) return true;
          if (!learnable.contains(q.id) || newSlots == 0) return false;
          newSlots--;
          return true;
        })
        .take(store.remainingPractice)
        .toList();
    final count = practice.length;
    return PageBody(children: [
      heading('我的题本', sub: '疑问题为最近一次标记“蒙对／不稳”的题目'),
      Wrap(spacing: 8, children: [
        for (final e in groups.entries)
          ChoiceChip(
              label: Text('${e.key} ${e.value.length}'),
              selected: kind == e.key,
              onSelected: (_) => setState(() {
                    kind = e.key;
                    shown = 20;
                  }))
      ]),
      if (kind == '错题')
        Padding(
            padding: const EdgeInsets.only(top: 14),
            child: box(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('错题优先级',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 7),
              Text(
                  '今日订正 ${justWrong.length} 题 · 反复错 ${repeated.length} 题 · 其他错题 ${activeMistakes.length - justWrong.length - repeated.length} 题 · 已掌握待归档 ${recovered.length} 题'),
              const SizedBox(height: 5),
              const Text(
                  '列表已按“今日刚错 → 反复错 → 其他 → 已掌握待归档”排序。移出错题本只改变你的题本标记，不会删除作答记录或复习排期。',
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
            ]))),
      if (kind == '笔记') _noteTopics(groups['笔记']!),
      Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
              onPressed: () => setState(() => filtering = !filtering),
              icon: const Icon(Icons.filter_list),
              label: Text(filtering ? '收起筛选' : '筛选'))),
      if (filtering) ...[
        TextField(
            controller: search,
            decoration: const InputDecoration(labelText: '搜索题干、选项、解析或考点'),
            onChanged: (v) => setState(() {
                  keyword = v.trim();
                  shown = 20;
                })),
        _select('学科', subject, store.questions.map((q) => q.subject).toSet(),
            (v) {
          subject = v;
          chapter = '全部';
        }),
        _select(
            '章节',
            chapter,
            store.questions
                .where((q) => subject == '全部' || q.subject == subject)
                .map((q) => q.chapter)
                .toSet(),
            (v) => chapter = v),
        _select('题型', type, store.questions.map((q) => q.type).toSet(),
            (v) => type = v),
        _select('标签', tag, store.questions.expand((q) => q.tags).toSet(),
            (v) => tag = v),
        _select(
            '院校',
            school,
            store.questions
                .map((q) => q.data['school'])
                .whereType<String>()
                .toSet(),
            (v) => school = v),
        _select(
            '年份',
            year,
            store.questions
                .map((q) => q.data['year'])
                .where((y) => y != null)
                .map((y) => '$y')
                .toSet(),
            (v) => year = v),
      ],
      const SizedBox(height: 12),
      FilledButton(
          onPressed: count == 0
              ? null
              : () => widget.onStart(
                  PracticeRequest(practice, review: true, label: '$kind巩固')),
          child: Text('练习 $count 题 · 预计 ${(count * 1.5).ceil()} 分钟')),
      if (qs.isEmpty) ...[
        heading(source.isEmpty ? '还没有$kind' : '没有匹配的题目'),
        Text(source.isEmpty
            ? '学习中的标记会保存在这里。'
            : '当前筛选条件排除了全部 ${source.length} 道题。'),
        TextButton(onPressed: _clear, child: const Text('清空筛选'))
      ] else
        for (final q in qs.take(shown))
          Card(
              child: ListTile(
                  title: Text(q.stem,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_subtitle(q, metrics)),
                  trailing: kind == '错题'
                      ? IconButton(
                          tooltip: '移出错题本，保留复习排期',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => safely(context,
                              () => store.add(q.id, 'removeWrong', null)))
                      : null,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => QuestionPreviewPage(
                              questions: qs,
                              initialQuestionId: q.id,
                              title: '$kind解析'))))),
      if (qs.length > shown)
        TextButton(
            onPressed: () => setState(() => shown += 20),
            child: const Text('再显示 20 题'))
    ]);
  }

  Widget _select(String label, String value, Set<String> values,
          void Function(String) change) =>
      Padding(
          padding: const EdgeInsets.only(top: 10),
          child: DropdownButtonFormField<String>(
              key: ValueKey('$label:$value'),
              initialValue: value,
              isExpanded: true,
              decoration: InputDecoration(labelText: label),
              items: ['全部', ...values]
                  .map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(s, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) => setState(() {
                    change(v!);
                    shown = 20;
                  })));
  void _clear() => setState(() {
        subject = chapter = type = tag = school = year = '全部';
        keyword = '';
        search.clear();
        shown = 20;
      });

  String _mistakeLabel(Question question, LearningMetrics metrics) {
    if (metrics.isRecoveredMistake(question)) return '已掌握，可归档';
    if (metrics.isWrongToday(question)) return '今日刚错，优先订正';
    final times = metrics.wrongAttempts(question);
    return times >= 2 ? '已错 $times 次，重点巩固' : '待巩固';
  }

  String _subtitle(Question question, LearningMetrics metrics) {
    if (kind == '错题') {
      return '${question.subject} · ${question.chapter} · ${_mistakeLabel(question, metrics)}';
    }
    if (kind == '笔记') {
      final note = store.learning.states[question.id]?.note.trim() ?? '';
      return '${question.subject} · ${question.chapter}\n笔记：$note';
    }
    return '${question.subject} · ${question.chapter}';
  }

  Widget _noteTopics(List<Question> notes) {
    final counts = <String, int>{};
    for (final question in notes) {
      for (final topic in question.tags) {
        counts[topic] = (counts[topic] ?? 0) + 1;
      }
    }
    final topics = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Padding(
        padding: const EdgeInsets.only(top: 14),
        child:
            box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('知识点笔记', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 7),
          Text('共 ${notes.length} 道题留下笔记；下方按题目自带考点聚合，便于考前回看。'),
          if (topics.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
                spacing: 6,
                runSpacing: 6,
                children: topics
                    .take(8)
                    .map((entry) =>
                        Chip(label: Text('${entry.key} ${entry.value}')))
                    .toList())
          ] else ...[
            const SizedBox(height: 7),
            const Text('这些题暂未配置考点标签，仍可逐题回看笔记。',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey))
          ]
        ])));
  }
}
