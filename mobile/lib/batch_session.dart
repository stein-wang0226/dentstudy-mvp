import 'package:flutter/material.dart';
import 'models.dart';
import 'store.dart';

const _ink = Color(0xFF173C3C);
const _teal = Color(0xFF087F78);
const _paper = Color(0xFFF5F7F3);

class BatchStudySession extends StatefulWidget {
  final List<Question> questions;
  final StudyStore store;
  final bool review;
  const BatchStudySession({
    super.key,
    required this.questions,
    required this.store,
    this.review = false,
  });

  @override
  State<BatchStudySession> createState() => _BatchStudySessionState();
}

class _BatchStudySessionState extends State<BatchStudySession> {
  int index = 0;
  bool reviewing = false, busy = false, finished = false;
  final Map<String, String> answers = {};
  final Map<String, String> grades = {};

  Question get question => widget.questions[index];

  Future<bool> _confirmLeave() async {
    if (finished) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('结束批量刷题？'),
            content: const Text('整批提交前的作答不会保存或更新复习排期。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('继续'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('结束'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _nextQuestion() {
    if ((answers[question.id] ?? '').trim().isEmpty) return;
    if (index + 1 < widget.questions.length) {
      setState(() => index++);
      return;
    }
    for (final item in widget.questions) {
      if (item.answer != null && answers[item.id] != item.answer) {
        grades[item.id] = 'wrong';
      }
    }
    setState(() {
      reviewing = true;
      index = 0;
    });
  }

  Future<void> _submit() async {
    if (busy || grades.length != widget.questions.length) return;
    setState(() => busy = true);
    try {
      final additions = widget.questions
          .map((item) => <String, dynamic>{
                'questionId': item.id,
                'kind': 'review',
                'value': {
                  'answer': answers[item.id],
                  'grade': grades[item.id],
                  'mode': widget.review ? 'review' : 'practice',
                },
              })
          .toList();
      // These are the same review events as deep mode. StudyStore's existing
      // reducer schedules them offline; the server reducer recalculates them
      // on sync. No scheduling algorithm is duplicated here.
      await widget.store.addMany(additions);
      if (!mounted) return;
      setState(() {
        busy = false;
        finished = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('整批保存失败，请重试：$error')));
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: finished,
        onPopInvokedWithResult: (didPop, result) async {
          if (!didPop && await _confirmLeave() && context.mounted) {
            setState(() => finished = true);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) Navigator.pop(context);
            });
          }
        },
        child: Scaffold(
          backgroundColor: _paper,
          appBar: AppBar(
            backgroundColor: _paper,
            title: Text(finished
                ? '批量刷题完成'
                : reviewing
                    ? '统一查看解析'
                    : '批量刷题'),
          ),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: finished
                      ? _finishedView()
                      : reviewing
                          ? _reviewView()
                          : _answerView(),
                ),
              ),
            ),
          ),
        ),
      );

  List<Widget> _answerView() {
    final selected = answers[question.id];
    return [
      _progress(),
      const SizedBox(height: 24),
      Wrap(
          spacing: 8,
          children: [_pill(question.type), _pill(question.subject)]),
      if (question.sharedStem.isNotEmpty) ...[
        const SizedBox(height: 16),
        _card(Text(question.sharedStem,
            style: const TextStyle(fontSize: 15, height: 1.7))),
      ],
      const SizedBox(height: 20),
      Text(question.stem,
          style: const TextStyle(
              fontSize: 21, height: 1.7, fontWeight: FontWeight.w600)),
      const SizedBox(height: 22),
      if (question.answer != null)
        ...question.options.entries.map((option) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton(
                onPressed: () =>
                    setState(() => answers[question.id] = option.key),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.all(18),
                  backgroundColor: selected == option.key
                      ? const Color(0xFFE7F1EE)
                      : Colors.white,
                  side: BorderSide(
                      color: selected == option.key
                          ? _teal
                          : const Color(0xFFDDE5DF)),
                ),
                child: Text('${option.key}　${option.value}',
                    style: const TextStyle(color: _ink, fontSize: 16)),
              ),
            ))
      else
        TextFormField(
          key: ValueKey(question.id),
          initialValue: selected,
          minLines: 5,
          maxLines: 10,
          decoration: const InputDecoration(hintText: '写下你的分析要点'),
          onChanged: (value) => setState(() => answers[question.id] = value),
        ),
      const SizedBox(height: 18),
      Row(children: [
        OutlinedButton(
          onPressed: index == 0 ? null : () => setState(() => index--),
          child: const Text('上一题'),
        ),
        const Spacer(),
        FilledButton(
          onPressed: (selected ?? '').trim().isEmpty ? null : _nextQuestion,
          child: Text(index + 1 == widget.questions.length ? '完成作答' : '下一题'),
        ),
      ]),
      const SizedBox(height: 12),
      Text(
          '已作答 ${answers.values.where((a) => a.trim().isNotEmpty).length} / ${widget.questions.length} · 完成本批后统一看解析',
          style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
    ];
  }

  List<Widget> _reviewView() {
    final answer = answers[question.id]!;
    final wrong = question.answer != null && answer != question.answer;
    final grade = grades[question.id];
    return [
      _progress(),
      const SizedBox(height: 22),
      Text(question.stem,
          style: const TextStyle(
              fontSize: 20, height: 1.6, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      Text('你的作答：$answer',
          style: TextStyle(
              color: wrong ? Colors.deepOrange : _teal,
              fontWeight: FontWeight.w600)),
      const SizedBox(height: 16),
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('参考答案：${question.answer ?? question.data['rubric']}',
            style: const TextStyle(color: _teal, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Text(question.explanation,
            style: const TextStyle(height: 1.75, color: _ink)),
        const Divider(height: 28),
        Text('易错提示：${question.warning}',
            style: const TextStyle(fontSize: 13, color: Color(0xFFA16736))),
      ])),
      const SizedBox(height: 18),
      if (wrong)
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.error_outline, color: Colors.deepOrange),
          title: Text('客观题答错，已自动标记“做错”'),
          subtitle: Text('整批提交后进入复习队列，无需再次确认。'),
        )
      else ...[
        const Text('请确认掌握程度', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _gradeChoice('做错', 'wrong', Colors.deepOrange, grade),
          _gradeChoice('蒙对 / 不稳', 'guessed', const Color(0xFFA77625), grade),
          _gradeChoice('完全掌握', 'mastered', _teal, grade),
        ]),
      ],
      const SizedBox(height: 22),
      Row(children: [
        OutlinedButton(
          onPressed: index == 0 ? null : () => setState(() => index--),
          child: const Text('上一题'),
        ),
        const Spacer(),
        FilledButton(
          onPressed: grade == null
              ? null
              : index + 1 < widget.questions.length
                  ? () => setState(() => index++)
                  : _submit,
          child: Text(index + 1 == widget.questions.length
              ? busy
                  ? '保存中…'
                  : '整批提交'
              : '下一题解析'),
        ),
      ]),
    ];
  }

  Widget _gradeChoice(
          String text, String value, Color color, String? selected) =>
      FilledButton(
        onPressed: () => setState(() => grades[question.id] = value),
        style: FilledButton.styleFrom(
            backgroundColor: selected == value ? color : color.withAlpha(150)),
        child: Text(selected == value ? '✓ $text' : text),
      );

  List<Widget> _finishedView() => [
        _card(const Column(children: [
          Icon(Icons.task_alt, color: _teal, size: 54),
          SizedBox(height: 14),
          Text('本批题目已保存',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('离线排期已更新；登录后会自动同步并由服务端复算。'),
        ])),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('返回学习首页'),
        ),
      ];

  Widget _progress() => Column(children: [
        Row(children: [
          Text('${index + 1} / ${widget.questions.length}',
              style:
                  const TextStyle(color: _teal, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text(reviewing ? '解析与评级' : '连续作答',
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
        ]),
        const SizedBox(height: 10),
        LinearProgressIndicator(
            value: (index + 1) / widget.questions.length,
            minHeight: 5,
            color: _teal),
      ]);

  Widget _card(Widget child) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _ink.withAlpha(12))),
      child: child);

  Widget _pill(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: _teal.withAlpha(16), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: const TextStyle(fontSize: 12, color: _teal)));
}
