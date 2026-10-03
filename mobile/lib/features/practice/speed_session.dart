import 'session_journal.dart';
import 'session_summary.dart';
import 'question_tools.dart';
import 'package:flutter/material.dart';
import '../../models.dart';
import '../../store.dart';
import '../../app/shared.dart' show teal, ink;

Color get _ink => ink;
Color get _teal => teal;

class SpeedStudySession extends StatefulWidget {
  final List<Question> questions;
  final StudyStore store;
  final bool review;
  final String checkpointKind;
  final SessionJournal journal;
  SpeedStudySession({
    super.key,
    required this.questions,
    required this.journal,
    required this.store,
    required this.review,
    this.checkpointKind = 'study',
  });

  @override
  State<SpeedStudySession> createState() => _SpeedStudySessionState();
}

class _SpeedStudySessionState extends State<SpeedStudySession> {
  bool leaving = false;
  bool restoring = true;
  Map<String, dynamic> snapshot() => {
        'index': index,
        'finished': finished,
        'answers': Map<String, String>.from(answers),
        'revealed': revealed,
        'saved': saved.toList(),
      };
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    if (!restoring && !leaving) {
      widget.journal.capture(snapshot());
    }
  }

  int index = 0;
  int? viewingIndex;
  bool revealed = false;
  bool busy = false;
  bool finished = false;
  final Map<String, String> answers = {};
  final Set<String> saved = {};

  @override
  void initState() {
    super.initState();
    final data = widget.journal.data;
    index = (data['index'] as int? ?? 0).clamp(0, widget.questions.length - 1);
    answers.addAll(Map<String, String>.from(data['answers'] ?? {}));
    saved.addAll(widget.journal.saved);
    revealed = data['revealed'] == true;
    while (index < widget.questions.length &&
        saved.contains(widget.questions[index].id)) {
      if (answers[widget.questions[index].id] !=
          widget.questions[index].answer) {
        revealed = true;
        break;
      }
      index++;
      revealed = false;
    }
    if (index >= widget.questions.length) {
      finished = true;
      index = widget.questions.length - 1;
    }

    restoring = false;
    if (finished) widget.journal.capture({'finished': true});
  }

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
      final completed = correct && index + 1 == widget.questions.length;
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
      if (completed) {
        await widget.journal.capture(snapshot());
        await widget.journal.finish();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败，请重试：$error')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> nextAfterExplanation() async {
    if (busy) return;
    final completed = index + 1 == widget.questions.length;
    setState(() {
      if (index + 1 == widget.questions.length) {
        finished = true;
      } else {
        index++;
        revealed = false;
      }
    });
    if (completed) {
      await widget.journal.capture(snapshot());
      await widget.journal.finish();
    }
  }

  Future<bool> leave() async {
    if (busy) return false;
    if (finished) return true;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('结束速刷？'),
            content: Text('已经作答的题目和复习排期会保留。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('继续刷题')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text('结束')),
            ],
          ),
        ) ??
        false;
    if (confirmed) {
      await widget.journal.capture(snapshot());
      if (widget.journal.error != null) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(widget.journal.error!)));
        return false;
      }
    }
    return confirmed;
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: (finished || leaving) && !busy,
        onPopInvokedWithResult: (didPop, result) async {
          if (!didPop && await leave() && context.mounted) {
            setState(() => leaving = true);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) Navigator.pop(context);
            });
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
                  icon: Icon(Icons.redo, size: 18),
                  label: Text('回到当前题'),
                )
              else if (!finished && previousCorrectIndex != null)
                TextButton.icon(
                  onPressed: () =>
                      setState(() => viewingIndex = previousCorrectIndex),
                  icon: Icon(Icons.undo, size: 18),
                  label: Text('上一道答对题'),
                ),
            ],
          ),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 800),
                child: ListView(
                  padding: EdgeInsets.all(20),
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
      QuestionTools(question: question, store: widget.store),
      Row(children: [
        Text(
            '${isViewingHistory ? viewingIndex! + 1 : index + 1} / ${widget.questions.length}',
            style: TextStyle(color: _teal, fontWeight: FontWeight.bold)),
        Spacer(),
        Text(isViewingHistory ? '已答对 · 仅查看' : '答对自动下一题',
            style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
      ]),
      SizedBox(height: 10),
      LinearProgressIndicator(
          value: (index + 1) / widget.questions.length,
          minHeight: 5,
          borderRadius: BorderRadius.circular(5),
          color: _teal),
      SizedBox(height: 22),
      Wrap(
          spacing: 8,
          children: [_pill(question.type), _pill(question.subject)]),
      if (question.sharedStem.isNotEmpty) ...[
        SizedBox(height: 16),
        _card(Text(question.sharedStem,
            style: TextStyle(fontSize: 15, height: 1.7))),
      ],
      SizedBox(height: 20),
      Text(question.stem,
          style: TextStyle(
              fontSize: 21,
              height: 1.65,
              fontWeight: FontWeight.w600,
              color: _ink)),
      SizedBox(height: 22),
      ...question.options.entries.map((option) {
        final chosen = selected == option.key;
        final correct = answerShown && option.key == question.answer;
        final wrong = answerShown && chosen && !correct;
        return Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: OutlinedButton(
            onPressed: answerShown || busy ? null : () => answer(option.key),
            style: OutlinedButton.styleFrom(
              disabledForegroundColor: _ink,
              alignment: Alignment.centerLeft,
              padding: EdgeInsets.all(18),
              backgroundColor: correct
                  ? _teal.withAlpha(25)
                  : wrong
                      ? Color(0xFFFFE9E2)
                      : chosen
                          ? _teal.withAlpha(18)
                          : Colors.white,
              side: BorderSide(
                  color: correct
                      ? _teal
                      : wrong
                          ? Colors.deepOrange
                          : Color(0xFFDDE5DF)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(option.key, style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(width: 16),
              Expanded(
                  child: Text(option.value,
                      style: TextStyle(fontSize: 16, height: 1.5))),
            ]),
          ),
        );
      }),
      if (revealed && !isViewingHistory) ...[
        SizedBox(height: 8),
        _analysis(question),
        SizedBox(height: 18),
        FilledButton.icon(
          onPressed: nextAfterExplanation,
          icon: Icon(Icons.arrow_forward),
          label: Text(index + 1 == widget.questions.length ? '完成速刷' : '继续下一题'),
        ),
      ],
      if (isViewingHistory) ...[
        SizedBox(height: 12),
        _analysis(question),
        SizedBox(height: 18),
        Row(children: [
          OutlinedButton(
            onPressed: previousCorrectIndex == null
                ? null
                : () => setState(() => viewingIndex = previousCorrectIndex),
            child: Text('再看上一道'),
          ),
          Spacer(),
          FilledButton(
            onPressed: () => setState(() => viewingIndex = null),
            child: Text('回到当前题'),
          ),
        ]),
      ],
      if (!revealed && !isViewingHistory) ...[
        SizedBox(height: 8),
        Text('答对默认按“完全掌握”安排复习；答错会优先安排次日巩固。',
            style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
      ],
    ];
  }

  Widget _analysis(Question question) => _card(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('参考答案：${question.answer}',
              style: TextStyle(fontWeight: FontWeight.bold, color: _teal)),
          SizedBox(height: 12),
          SourceDetails(question: question),
          Text(question.explanation, style: TextStyle(height: 1.75)),
        ],
      ));

  List<Widget> _finishedView() => [SessionSummary(journal: widget.journal)];

  Widget _card(Widget child) => Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _ink.withAlpha(12))),
      child: Material(type: MaterialType.transparency, child: child));

  Widget _pill(String text) => Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: _teal.withAlpha(16), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(fontSize: 12, color: _teal)));
}
