import 'package:flutter/material.dart';
import 'models.dart';
import 'store.dart';

const _ink = Color(0xFF173C3C);
const _teal = Color(0xFF087F78);

class SpeedStudySession extends StatefulWidget {
  final List<Question> questions;
  final StudyStore store;
  final bool review;
  const SpeedStudySession({
    super.key,
    required this.questions,
    required this.store,
    required this.review,
  });

  @override
  State<SpeedStudySession> createState() => _SpeedStudySessionState();
}

class _SpeedStudySessionState extends State<SpeedStudySession> {
  int index = 0;
  int? viewingIndex;
  bool revealed = false;
  bool busy = false;
  bool finished = false;
  final Map<String, String> answers = {};
  final Set<String> saved = {};

  Question get current => widget.questions[index];
  Question get displayed => widget.questions[viewingIndex ?? index];
  bool get isViewingHistory => viewingIndex != null;

  int? get previousCorrectIndex {
    final before = isViewingHistory ? viewingIndex! : index;
    for (var i = before - 1; i >= 0; i--) {
      final question = widget.questions[i];
      if (answers[question.id] == question.answer) return i;
    }
    return null;
  }

  Future<void> answer(String value) async {
    if (busy || revealed || isViewingHistory) return;
    final question = current;
    final correct = value == question.answer;
    setState(() {
      busy = true;
      answers[question.id] = value;
    });
    try {
      if (!saved.contains(question.id)) {
        await widget.store.add(question.id, 'review', {
          'answer': value,
          'grade': correct ? 'mastered' : 'wrong',
          'mode': widget.review ? 'speed-review' : 'speed',
        });
        saved.add(question.id);
      }
      if (!mounted) return;
      setState(() {
        if (correct) {
          if (index + 1 == widget.questions.length) {
            finished = true;
          } else {
            index++;
            revealed = false;
          }
        } else {
          revealed = true;
        }
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败，请重试：$error')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void nextAfterExplanation() {
    if (busy) return;
    setState(() {
      if (index + 1 == widget.questions.length) {
        finished = true;
      } else {
        index++;
        revealed = false;
      }
    });
  }

  Future<bool> leave() async {
    if (finished) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('结束速刷？'),
            content: const Text('已经作答的题目和复习排期会保留。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('继续刷题')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('结束')),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: finished,
        onPopInvokedWithResult: (didPop, result) async {
          if (!didPop && await leave() && context.mounted) {
            Navigator.pop(context);
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(finished
                ? '速刷完成'
                : isViewingHistory
                    ? '已答对题目'
                    : '速刷模式'),
            actions: [
              if (!finished && isViewingHistory)
                TextButton.icon(
                  onPressed: () => setState(() => viewingIndex = null),
                  icon: const Icon(Icons.redo, size: 18),
                  label: const Text('回到当前题'),
                )
              else if (!finished && previousCorrectIndex != null)
                TextButton.icon(
                  onPressed: () =>
                      setState(() => viewingIndex = previousCorrectIndex),
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('上一道答对题'),
                ),
            ],
          ),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: finished ? _finishedView() : _questionView(),
                ),
              ),
            ),
          ),
        ),
      );

  List<Widget> _questionView() {
    final question = displayed;
    final selected = answers[question.id];
    final answerShown = isViewingHistory || revealed;
    return [
      Row(children: [
        Text(
            '${isViewingHistory ? viewingIndex! + 1 : index + 1} / ${widget.questions.length}',
            style: const TextStyle(color: _teal, fontWeight: FontWeight.bold)),
        const Spacer(),
        Text(isViewingHistory ? '已答对 · 仅查看' : '答对自动下一题',
            style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
      ]),
      const SizedBox(height: 10),
      LinearProgressIndicator(
          value: (index + 1) / widget.questions.length,
          minHeight: 5,
          borderRadius: BorderRadius.circular(5),
          color: _teal),
      const SizedBox(height: 22),
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
              fontSize: 21,
              height: 1.65,
              fontWeight: FontWeight.w600,
              color: _ink)),
      const SizedBox(height: 22),
      ...question.options.entries.map((option) {
        final chosen = selected == option.key;
        final correct = answerShown && option.key == question.answer;
        final wrong = answerShown && chosen && !correct;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: OutlinedButton(
            onPressed: answerShown || busy ? null : () => answer(option.key),
            style: OutlinedButton.styleFrom(
              disabledForegroundColor: _ink,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.all(18),
              backgroundColor: correct
                  ? const Color(0xFFE0F0E7)
                  : wrong
                      ? const Color(0xFFFFE9E2)
                      : chosen
                          ? const Color(0xFFE7F1EE)
                          : Colors.white,
              side: BorderSide(
                  color: correct
                      ? _teal
                      : wrong
                          ? Colors.deepOrange
                          : const Color(0xFFDDE5DF)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(option.key,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 16),
              Expanded(
                  child: Text(option.value,
                      style: const TextStyle(fontSize: 16, height: 1.5))),
            ]),
          ),
        );
      }),
      if (revealed && !isViewingHistory) ...[
        const SizedBox(height: 8),
        _analysis(question),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: nextAfterExplanation,
          icon: const Icon(Icons.arrow_forward),
          label: Text(index + 1 == widget.questions.length ? '完成速刷' : '继续下一题'),
        ),
      ],
      if (isViewingHistory) ...[
        const SizedBox(height: 12),
        _analysis(question),
        const SizedBox(height: 18),
        Row(children: [
          OutlinedButton(
            onPressed: previousCorrectIndex == null
                ? null
                : () => setState(() => viewingIndex = previousCorrectIndex),
            child: const Text('再看上一道'),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () => setState(() => viewingIndex = null),
            child: const Text('回到当前题'),
          ),
        ]),
      ],
      if (!revealed && !isViewingHistory) ...[
        const SizedBox(height: 8),
        const Text('答对默认按“完全掌握”安排复习；答错会优先安排次日巩固。',
            style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
      ],
    ];
  }

  Widget _analysis(Question question) => _card(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('参考答案：${question.answer}',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, color: _teal)),
          const SizedBox(height: 12),
          Text(question.explanation, style: const TextStyle(height: 1.75)),
          const Divider(height: 28),
          Text('易错提示：${question.warning}',
              style: const TextStyle(fontSize: 13, color: Color(0xFFA16736))),
          const SizedBox(height: 10),
          Text('出处：${question.reference}',
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
        ],
      ));

  List<Widget> _finishedView() => [
        _card(const Column(children: [
          Icon(Icons.bolt, color: _teal, size: 54),
          SizedBox(height: 14),
          Text('本次速刷已完成',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('答对题已按掌握度排期，答错题已加入优先复习。'),
        ])),
        const SizedBox(height: 20),
        FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('返回学习首页')),
      ];

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
