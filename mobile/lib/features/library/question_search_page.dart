import 'package:flutter/material.dart';
import '../../app/shared.dart';
import '../../models.dart';
import 'question_preview.dart';
import 'question_search.dart';

class QuestionSearchPage extends StatefulWidget {
  final List<Question> questions;
  final String? subject, chapter;
  const QuestionSearchPage(
      {super.key, required this.questions, this.subject, this.chapter});
  @override
  State<QuestionSearchPage> createState() => _QuestionSearchPageState();
}

class _QuestionSearchPageState extends State<QuestionSearchPage> {
  final field = TextEditingController();
  late final index = QuestionSearchIndex(widget.questions);
  late String? subject = widget.subject, chapter = widget.chapter;
  int shown = 20;
  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = field.text.trim();
    final subjects = widget.questions.map((q) => q.subject).toSet();
    final chapters = widget.questions
        .where((q) => q.subject == subject)
        .map((q) => q.chapter)
        .toSet();
    final results = index.search(query, subject: subject, chapter: chapter);
    return Scaffold(
        appBar: AppBar(title: const Text('搜索题目')),
        body: PageBody(children: [
          const SizedBox(height: 12),
          TextField(
              controller: field,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                  hintText: '输入疾病、关键词或题目编号',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空搜索',
                          onPressed: () => setState(() {
                                field.clear();
                                shown = 20;
                              }),
                          icon: const Icon(Icons.close))),
              onChanged: (_) => setState(() => shown = 20),
              onSubmitted: (_) => FocusScope.of(context).unfocus()),
          const SizedBox(height: 12),
          _filter('学科', subject, subjects, (value) {
            subject = value;
            chapter = null;
          }),
          if (subject != null) ...[
            const SizedBox(height: 10),
            _filter('章节', chapter, chapters, (value) => chapter = value)
          ],
          if (query.isEmpty) ...[
            heading('搜索已开放题库'),
            Text('当前${store.mode}方向共 ${widget.questions.length} 题。'
                '搜索题干、选项、解析和考点；多个关键词用空格分隔。'),
            const SizedBox(height: 12),
            const Text('例如：牙周炎、种植、咬合、RPA')
          ] else ...[
            heading('找到 ${results.length} 道题',
                sub: subject == null
                    ? '全部已开放学科'
                    : '$subject${chapter == null ? '' : ' · $chapter'}'),
            if (results.isEmpty) ...[
              const Text('没有同时包含这些关键词的题目。可以减少关键词或扩大搜索范围。'),
              if (subject != null)
                TextButton(
                    onPressed: () => setState(() {
                          subject = chapter = null;
                          shown = 20;
                        }),
                    child: const Text('清空范围筛选'))
            ],
            for (final q in results.take(shown))
              Card(
                  child: ListTile(
                      title: Text(q.stem,
                          maxLines: 3, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${q.subject} · ${q.chapter} · ${q.type}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => QuestionPreviewPage(
                                    questions: results,
                                    initialQuestionId: q.id,
                                    title: '搜索结果解析')));
                      })),
            if (results.length > shown)
              TextButton(
                  onPressed: () => setState(() => shown += 20),
                  child: const Text('再显示 20 题'))
          ]
        ]));
  }

  Widget _filter(String label, String? value, Set<String> values,
          void Function(String?) change) =>
      DropdownButtonFormField<String>(
          key: ValueKey('$label:$value'),
          initialValue: value ?? '',
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            const DropdownMenuItem(value: '', child: Text('全部')),
            for (final item in values)
              DropdownMenuItem(
                  value: item,
                  child: Text(item, overflow: TextOverflow.ellipsis))
          ],
          onChanged: (v) => setState(() {
                change(v == '' ? null : v);
                shown = 20;
              }));
}
