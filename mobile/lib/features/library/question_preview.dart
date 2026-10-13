import 'package:flutter/material.dart';
import '../../models.dart';
import '../../app/shared.dart';
import '../practice/question_tools.dart';
import 'reading_sequence.dart';

class QuestionPreviewPage extends StatefulWidget {
  final List<Question> questions;
  final String? initialQuestionId, initialChapter;
  final bool chapterNavigation;
  final String title;
  const QuestionPreviewPage({
    super.key,
    required this.questions,
    this.initialQuestionId,
    this.initialChapter,
    this.chapterNavigation = false,
    this.title = '题目解析',
  });
  @override
  State<QuestionPreviewPage> createState() => _QuestionPreviewPageState();
}

class _QuestionPreviewPageState extends State<QuestionPreviewPage> {
  late final sequence =
      ReadingSequence(widget.questions, byChapter: widget.chapterNavigation);
  final scroll = ScrollController();
  int index = 0;
  Question get question => sequence.questions[index];
  String _readingKey(Question q) =>
      'reading:${store.userId}:${store.mode}:${q.subject}:${q.chapter}';

  @override
  void initState() {
    super.initState();
    if (sequence.questions.isEmpty) return;
    index = sequence.startIndex(
        questionId: widget.initialQuestionId, chapter: widget.initialChapter);
    if (widget.chapterNavigation && widget.initialQuestionId == null) {
      final saved = store.prefs.getString(_readingKey(question));
      final current = question;
      final found = sequence.questions
          .indexWhere((q) => q.id == saved && sequence.sameChapter(q, current));
      if (found >= 0) index = found;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _remember();
    });
  }

  void _remember() {
    if (widget.chapterNavigation) {
      final q = question;
      safely(context, () async {
        await store.prefs.setString(_readingKey(q), q.id);
      });
    }
  }

  void _move(int target) {
    setState(() => index = target);
    if (scroll.hasClients) scroll.jumpTo(0);
    _remember();
  }

  Future<void> _chooseQuestion() async {
    final indices = [
      for (var i = 0; i < sequence.questions.length; i++)
        if (!widget.chapterNavigation ||
            sequence.sameChapter(sequence.questions[i], question))
          i
    ];
    final chosen = await showModalBottomSheet<int>(
        context: context,
        isScrollControlled: true,
        builder: (c) => SafeArea(
            child: SizedBox(
                height: MediaQuery.sizeOf(c).height * .7,
                child: Column(children: [
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                          widget.chapterNavigation
                              ? '${question.chapter} · ${indices.length} 题'
                              : '当前列表 · ${indices.length} 题',
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(
                      child: ListView.builder(
                          itemCount: indices.length,
                          itemBuilder: (_, position) {
                            final target = indices[position];
                            return ListTile(
                                selected: target == index,
                                leading: Text('${position + 1}'),
                                title: Text(sequence.questions[target].stem,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                trailing: target == index
                                    ? const Icon(Icons.visibility_outlined)
                                    : null,
                                onTap: () => Navigator.pop(c, target));
                          }))
                ]))));
    if (chosen != null && mounted) _move(chosen);
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (sequence.questions.isEmpty) {
      return Scaffold(
          appBar: AppBar(title: Text(widget.title)),
          body: const Center(child: Text('当前范围没有可查看的题目')));
    }
    final q = question;
    final last = index + 1 == sequence.questions.length;
    final nextChapter = widget.chapterNavigation && sequence.endsChapter(index);
    final progress = widget.chapterNavigation
        ? '本章第 ${sequence.chapterPosition(index)} / ${sequence.chapterCount(index)} 题'
        : '第 ${index + 1} / ${sequence.questions.length} 题';
    return Scaffold(
        appBar: AppBar(title: Text(widget.title), actions: [
          IconButton(
              tooltip: '题目目录',
              onPressed: _chooseQuestion,
              icon: const Icon(Icons.format_list_numbered)),
        ]),
        bottomNavigationBar: SafeArea(
            top: false,
            child: Align(
                heightFactor: 1,
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                        child: Row(children: [
                          OutlinedButton.icon(
                              onPressed:
                                  index == 0 ? null : () => _move(index - 1),
                              icon: const Icon(Icons.chevron_left),
                              label: const Text('上一题')),
                          const SizedBox(width: 16),
                          Expanded(
                              child: FilledButton.icon(
                                  onPressed: last
                                      ? () => Navigator.pop(context)
                                      : () => _move(index + 1),
                                  icon: Icon(
                                      last ? Icons.list : Icons.chevron_right),
                                  label: Text(last
                                      ? widget.chapterNavigation
                                          ? '返回章节目录'
                                          : '返回列表'
                                      : nextChapter
                                          ? '下一章'
                                          : '下一题')))
                        ]))))),
        body: SafeArea(
            child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: SelectionArea(
                        key: ValueKey(q.id),
                        child: ListView(
                            controller: scroll,
                            padding: const EdgeInsets.all(20),
                            children: [
                              Text(progress,
                                  style: TextStyle(
                                      color: teal,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 12),
                              QuestionTools(
                                  key: ValueKey(q.id),
                                  question: q,
                                  store: store),
                              if (q.tags.isNotEmpty) ...[
                                Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: q.tags.map(pill).toList()),
                                const SizedBox(height: 14)
                              ],
                              const SizedBox(height: 8),
                              if (q.sharedStem.isNotEmpty)
                                Text(q.sharedStem,
                                    style: const TextStyle(height: 1.7)),
                              Text(q.stem,
                                  style: TextStyle(
                                      fontSize: 21,
                                      height: 1.7,
                                      fontWeight: FontWeight.w600,
                                      color: ink)),
                              const SizedBox(height: 22),
                              ...q.options.entries.map((option) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                          color: option.key == q.answer
                                              ? teal.withAlpha(25)
                                              : Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          border: Border.all(
                                              color: option.key == q.answer
                                                  ? teal
                                                  : const Color(0xFFDDE5DF))),
                                      child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(option.key,
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: teal)),
                                            const SizedBox(width: 14),
                                            Expanded(
                                                child: Text(option.value,
                                                    style: const TextStyle(
                                                        fontSize: 16,
                                                        height: 1.5)))
                                          ])))),
                              const SizedBox(height: 10),
                              box(Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('参考答案：${q.answer ?? q.data['rubric']}',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: teal)),
                                    const SizedBox(height: 12),
                                    Text(q.explanation,
                                        style: const TextStyle(height: 1.8)),
                                    SourceDetails(
                                        key: ValueKey('source:${q.id}'),
                                        question: q),
                                  ])),
                              if (nextChapter) ...[
                                const SizedBox(height: 20),
                                box(Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(last ? '已到本学科最后一题' : '本章已到最后一题',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      if (!last) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                            '下一章：${sequence.questions[index + 1].chapter}')
                                      ],
                                      const SizedBox(height: 8),
                                      const Text('浏览解析不会计入作答完成数。',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.blueGrey))
                                    ]))
                              ],
                              const SizedBox(height: 16)
                            ]))))));
  }
}
