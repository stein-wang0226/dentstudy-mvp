import 'package:flutter/material.dart';
import '../../models.dart';
import '../../store.dart';
import '../../app/shared.dart' show box, message, pill, safely, store, teal;
import '../library/catalog.dart';
import '../library/question_preview.dart';
import '../statistics/learning_metrics.dart';

class SourceDetails extends StatelessWidget {
  final Question question;
  const SourceDetails({super.key, required this.question});
  @override
  Widget build(BuildContext context) => ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(
              '${QuestionCatalog.sourceLabel(question)} · ${QuestionCatalog.reviewLabel(question)}',
              style: const TextStyle(fontSize: 12)),
          children: [
            Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText('题目编号：${question.id}',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.blueGrey)),
                          const SizedBox(height: 6),
                          Text(question.reference,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.blueGrey))
                        ])))
          ]);
}

class QuestionTools extends StatelessWidget {
  final Question question;
  final StudyStore store;
  const QuestionTools({super.key, required this.question, required this.store});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: store,
      builder: (c, _) =>
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${question.subject} · ${question.chapter}',
                style: const TextStyle(fontSize: 13, color: Colors.blueGrey)),
            Row(children: [
              Chip(label: Text(question.type)),
              const Spacer(),
              IconButton(
                  tooltip: '收藏题目',
                  icon: Icon(
                      store.learning.states[question.id]?.favorite == true
                          ? Icons.bookmark
                          : Icons.bookmark_border),
                  onPressed: () => safely(
                      c,
                      () => store.add(
                          question.id,
                          'favorite',
                          !(store.learning.states[question.id]?.favorite ??
                              false)))),
              IconButton(
                  tooltip: '题目笔记',
                  icon: const Icon(Icons.edit_note),
                  onPressed: () => _note(c)),
              IconButton(
                  tooltip: '题目讨论',
                  icon: const Icon(Icons.forum_outlined),
                  onPressed: () => _comments(c))
            ]),
          ]));
  Future<void> _note(BuildContext context) async {
    final field = TextEditingController(
        text: store.learning.states[question.id]?.note ?? '');
    final result = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('题目笔记'),
                content: TextField(
                    controller: field,
                    minLines: 3,
                    maxLines: 8,
                    maxLength: 10000),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, field.text),
                      child: const Text('保存'))
                ]));
    if (result != null && context.mounted)
      await safely(context, () => store.add(question.id, 'note', result));
    // Dispose after the dialog's exit animation has detached its text field.
    Future.delayed(const Duration(milliseconds: 400), field.dispose);
  }

  Future<void> _comments(BuildContext context) async {
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
            child: SizedBox(
                height: MediaQuery.sizeOf(sheetContext).height * .8,
                child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [QuestionComments(question: question)]))));
  }
}

class QuestionComments extends StatefulWidget {
  final Question question;
  const QuestionComments({super.key, required this.question});

  @override
  State<QuestionComments> createState() => _QuestionCommentsState();
}

class _QuestionCommentsState extends State<QuestionComments> {
  final field = TextEditingController();
  List<Map<String, dynamic>> comments = [];
  bool loading = true, sending = false, composing = false;
  String? loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted)
      setState(() {
        loading = true;
        loadError = null;
      });
    try {
      final result = await store.questionComments(widget.question.id);
      if (mounted) setState(() => comments = result);
    } catch (_) {
      if (mounted) setState(() => loadError = '讨论暂时无法加载');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _send() async {
    if (store.token.isEmpty) {
      message(context, '登录后即可参与讨论');
      return;
    }
    final body = field.text.trim();
    if (body.isEmpty) {
      message(context, '写点内容再发布吧');
      return;
    }
    setState(() => sending = true);
    try {
      await store.postQuestionComment(widget.question.id, body);
      field.clear();
      if (mounted) setState(() => composing = false);
      await _load();
    } catch (error) {
      if (mounted) message(context, error.toString());
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  IconData _avatarIcon(String value) => switch (value) {
        'tooth' => Icons.health_and_safety_outlined,
        'science' => Icons.science_outlined,
        'leaf' => Icons.eco_outlined,
        'star' => Icons.star_outline,
        'smile' => Icons.sentiment_satisfied_alt_outlined,
        _ => Icons.auto_stories_outlined,
      };

  String _time(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    final local = date.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child:
          box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.forum_outlined, size: 20),
          const SizedBox(width: 8),
          Text('题目讨论${comments.isEmpty ? '' : ' · ${comments.length}'}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(
              tooltip: '刷新讨论',
              onPressed: loading ? null : _load,
              icon: const Icon(Icons.refresh, size: 20))
        ]),
        const SizedBox(height: 6),
        if (loading)
          const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()))
        else if (loadError != null)
          Text(loadError!, style: const TextStyle(color: Colors.blueGrey))
        else if (comments.isEmpty)
          const Text('暂时还没有讨论，留下你的理解吧。',
              style: TextStyle(color: Colors.blueGrey))
        else
          ...comments.map((comment) => Padding(
              padding: const EdgeInsets.only(top: 14),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(
                    radius: 18,
                    backgroundColor: teal.withAlpha(20),
                    child: Icon(_avatarIcon(comment['avatar'] as String? ?? ''),
                        color: teal, size: 19)),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                          '${comment['nickname'] ?? '齿间同学'}${(comment['university'] as String? ?? '').isEmpty ? '' : ' · ${comment['university']}'}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(_time(comment['createdAt'] as String? ?? ''),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.blueGrey)),
                      const SizedBox(height: 5),
                      Text(comment['body'] as String,
                          style: const TextStyle(height: 1.55)),
                    ]))
              ]))),
        const SizedBox(height: 16),
        if (!composing)
          Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                  onPressed: store.token.isEmpty
                      ? _send
                      : () => setState(() => composing = true),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('写评论')))
        else ...[
          TextField(
              controller: field,
              minLines: 2,
              maxLines: 5,
              maxLength: 500,
              decoration: const InputDecoration(hintText: '分享你的理解或易错点'),
              enabled: !sending),
          const SizedBox(height: 8),
          Align(
              alignment: Alignment.centerRight,
              child: Wrap(spacing: 8, children: [
                TextButton(
                    onPressed: sending
                        ? null
                        : () => setState(() => composing = false),
                    child: const Text('取消')),
                FilledButton.icon(
                    onPressed: sending ? null : _send,
                    icon: const Icon(Icons.send_outlined),
                    label: Text(sending ? '发布中…' : '发布评论'))
              ]))
        ]
      ])));
}

/// Shown with an explanation.  It uses the existing bank as a small,
/// transparent follow-up rather than claiming that a new recommendation model
/// knows medical facts that are not present in the question data.
class QuestionLearningSupport extends StatelessWidget {
  final Question question;
  final StudyStore store;
  const QuestionLearningSupport(
      {super.key, required this.question, required this.store});

  List<Question> get _related {
    final tags = question.tags.toSet();
    final peers = store.catalog.material(question.subject).where((candidate) {
      if (candidate.id == question.id) return false;
      return candidate.chapter == question.chapter ||
          candidate.tags.any(tags.contains);
    }).toList();
    peers.sort((a, b) {
      final aTag = a.tags.any(tags.contains) ? 0 : 1;
      final bTag = b.tags.any(tags.contains) ? 0 : 1;
      return aTag.compareTo(bTag);
    });
    return peers.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = LearningMetrics(store.learning, store.questions);
    final related = _related;
    final mistakes = metrics.wrongAttempts(question);
    return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('学习巩固',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          if (question.tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('本题考点',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
            const SizedBox(height: 5),
            Wrap(
                spacing: 6,
                runSpacing: 6,
                children: question.tags.map(pill).toList()),
          ],
          const SizedBox(height: 10),
          Text(
              mistakes >= 2
                  ? '这道题已错 $mistakes 次，建议比较相似题的选项排除依据，再安排一次复习。'
                  : '易混点通常在相近选项的排除依据；看完解析后可用同考点题再确认一次。',
              style: const TextStyle(
                  fontSize: 13, height: 1.55, color: Colors.blueGrey)),
          if (related.isNotEmpty)
            TextButton.icon(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => QuestionPreviewPage(
                            questions: related,
                            title: '同考点解析 · ${question.chapter}'))),
                icon: const Icon(Icons.auto_stories_outlined),
                label: Text('查看 ${related.length} 道同考点题解析')),
        ]));
  }
}
