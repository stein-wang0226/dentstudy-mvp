import 'package:flutter/material.dart';
import '../../app/shared.dart';
import '../../models.dart';
import '../practice/practice_request.dart';
import '../library/question_preview.dart';

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
    };
    final source = groups[kind]!;
    final qs = source
        .where((q) =>
            (subject == '全部' || q.subject == subject) &&
            (chapter == '全部' || q.chapter == chapter) &&
            (type == '全部' || q.type == type) &&
            (tag == '全部' || q.tags.contains(tag)) &&
            (school == '全部' || q.data['school'] == school) &&
            (year == '全部' || q.data['year'].toString() == year) &&
            (keyword.isEmpty ||
                '${q.stem} ${q.chapter} ${q.data['topics']}'.contains(keyword)))
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
        .take(store.remainingPractice ?? qs.length)
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
      Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
              onPressed: () => setState(() => filtering = !filtering),
              icon: const Icon(Icons.filter_list),
              label: Text(filtering ? '收起筛选' : '筛选'))),
      if (filtering) ...[
        TextField(
            controller: search,
            decoration: const InputDecoration(labelText: '搜索题干或考点'),
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
                  subtitle: Text('${q.subject} · ${q.chapter}'),
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
                          builder: (_) =>
                              QuestionPreviewPage(questions: [q]))))),
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
}
