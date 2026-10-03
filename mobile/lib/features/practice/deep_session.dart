import 'session_journal.dart';
import 'session_summary.dart';
import 'question_tools.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../models.dart';
import '../../app/shared.dart';

class StudySession extends StatefulWidget {
  final List<Question> questions;
  final bool exam, review;
  final String checkpointKind;
  final SessionJournal journal;
  StudySession(
      {super.key,
      required this.questions,
      required this.journal,
      this.exam = false,
      this.review = false,
      this.checkpointKind = 'study'});
  @override
  State<StudySession> createState() => _StudySessionState();
}

class _StudySessionState extends State<StudySession>
    with WidgetsBindingObserver {
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
  bool revealed = false, busy = false, finished = false;
  final Map<String, String> answers = {};
  final Set<String> saved = {};
  late DateTime deadline;
  Timer? timer;
  int seconds = 0;
  Question get q => widget.questions[index];
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
      index++;
      revealed = false;
    }
    if (index >= widget.questions.length) {
      finished = true;
      index = widget.questions.length - 1;
    }

    restoring = false;

    WidgetsBinding.instance.addObserver(this);
    deadline = DateTime.now().add(Duration(
        minutes: widget.questions.first.data['durationMinutes'] as int? ?? 15));
    deadline =
        DateTime.tryParse(widget.journal.data['deadline'] as String? ?? '') ??
            deadline;
    widget.journal.capture(
        {'deadline': deadline.toUtc().toIso8601String(), 'finished': finished});
    if (widget.exam) {
      tick();
      timer = Timer.periodic(Duration(seconds: 1), (_) => tick());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.exam) tick();
  }

  void tick() {
    if (!mounted || finished) return;
    setState(
        () => seconds = max(0, deadline.difference(DateTime.now()).inSeconds));
    if (seconds == 0 && !busy) submitExam();
  }

  Future<void> save(Question question, String grade,
      {String mode = 'practice'}) async {
    if (saved.contains(question.id)) return;
    await store.add(question.id, 'review',
        {'answer': answers[question.id], 'grade': grade, 'mode': mode});
    saved.add(question.id);
  }

  Future<void> grade(String grade) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await save(q, grade, mode: widget.review ? 'review' : 'practice');
      if (!mounted) return;
      if (index + 1 == widget.questions.length) {
        setState(() => finished = true);
        await widget.journal.capture(snapshot());
        await widget.journal.finish();
      } else
        setState(() {
          index++;
          revealed = false;
        });
    } catch (e) {
      if (mounted) message(context, '保存失败，请重试：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submitExam() async {
    if (busy || finished) return;
    setState(() => busy = true);
    try {
      for (final question in widget.questions) {
        if (question.answer != null && answers.containsKey(question.id))
          await save(question,
              answers[question.id] == question.answer ? 'guessed' : 'wrong',
              mode: 'exam');
      }
      timer?.cancel();
      await widget.journal.capture(snapshot());
      await widget.journal.finish();
      if (mounted) setState(() => finished = true);
    } catch (e) {
      if (mounted) message(context, '提交失败，作答仍保留在本页：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> leave() async {
    if (busy) return false;
    if (finished) return true;
    final confirmed = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
                    title: Text('结束本次练习？'),
                    content: Text(widget.exam
                        ? '保存当前作答与原截止时间，恢复后继续计时。'
                        : '已标记掌握度的题目已保存，当前答案和进度会保存，稍后可继续。'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: Text('继续')),
                      FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: Text('结束'))
                    ])) ??
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
            if (context.mounted) Navigator.pop(context);
          });
        }
      },
      child: Scaffold(
          appBar: AppBar(
              title: Text(finished
                  ? '本次练习分析'
                  : widget.exam
                      ? '限时模考'
                      : widget.review
                          ? '今日巩固'
                          : '专注练习'),
              actions: [
                if (widget.exam && !finished)
                  Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: seconds < 60 ? Colors.red : ink)))
              ]),
          body: SafeArea(
              child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 800),
                      child: ListView(
                          padding: EdgeInsets.all(20),
                          children: finished
                              ? [
                                  SessionSummary(journal: widget.journal),
                                  if (widget.exam) ...report()
                                ]
                              : questionView()))))));
  List<Widget> questionView() {
    final selected = answers[q.id];
    return [
      Row(children: [
        Text('${index + 1} / ${widget.questions.length}',
            style: TextStyle(color: teal, fontWeight: FontWeight.bold)),
        Spacer(),
        Text(q.subject, style: TextStyle(fontSize: 12, color: Colors.blueGrey))
      ]),
      SizedBox(height: 12),
      LinearProgressIndicator(
          value: (index + 1) / widget.questions.length,
          minHeight: 4,
          borderRadius: BorderRadius.circular(4)),
      SizedBox(height: 24),
      QuestionTools(question: q, store: store),
      if (q.sharedStem.isNotEmpty) ...[
        SizedBox(height: 16),
        box(Text(q.sharedStem, style: TextStyle(fontSize: 15, height: 1.8)),
            color: teal.withAlpha(15))
      ],
      SizedBox(height: 20),
      Text(q.stem,
          style: TextStyle(
              fontSize: 21,
              height: 1.7,
              fontWeight: FontWeight.w600,
              color: ink)),
      SizedBox(height: 24),
      if (q.answer != null)
        ...q.options.entries.map((option) {
          final chosen = selected == option.key;
          final correct = revealed && option.key == q.answer;
          final wrong = revealed && chosen && !correct;
          return Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: OutlinedButton(
                  onPressed: revealed || busy
                      ? null
                      : () => setState(() => answers[q.id] = option.key),
                  style: OutlinedButton.styleFrom(
                      disabledForegroundColor: ink,
                      alignment: Alignment.centerLeft,
                      padding: EdgeInsets.all(18),
                      backgroundColor: correct
                          ? teal.withAlpha(25)
                          : wrong
                              ? Color(0xFFFFE9E2)
                              : chosen
                                  ? teal.withAlpha(18)
                                  : Colors.white,
                      side: BorderSide(
                          color: correct
                              ? teal
                              : wrong
                                  ? Colors.deepOrange
                                  : chosen
                                      ? teal
                                      : Color(0xFFDDE5DF)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15))),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(option.key,
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(width: 16),
                        Expanded(
                            child: Text(option.value,
                                style: TextStyle(fontSize: 16, height: 1.5)))
                      ])));
        })
      else
        TextFormField(
            key: ValueKey(q.id),
            initialValue: selected,
            minLines: 5,
            maxLines: 10,
            enabled: !revealed,
            decoration: InputDecoration(hintText: '写下你的分析要点，再对照参考答案自评'),
            onChanged: (v) => setState(() => answers[q.id] = v)),
      if (!widget.exam && !revealed) ...[
        SizedBox(height: 16),
        FilledButton(
            onPressed: selected == null || selected.trim().isEmpty
                ? null
                : () => setState(() => revealed = true),
            child: Text('确认作答 · 查看解析'))
      ],
      if (revealed) ...[
        heading(q.answer == null
            ? '对照要点，自评掌握度'
            : selected == q.answer
                ? '回答正确，再确认掌握度'
                : '这道题值得再巩固'),
        ...explanation(q),
        SizedBox(height: 20),
        Wrap(spacing: 8, runSpacing: 8, children: [
          gradeButton('做错', 'wrong', Colors.deepOrange),
          gradeButton('蒙对 / 不稳', 'guessed', Color(0xFFA77625),
              enabled: q.answer == null || selected == q.answer),
          gradeButton('完全掌握', 'mastered', teal,
              enabled: q.answer == null || selected == q.answer)
        ]),
        SizedBox(height: 10),
        Text('答错将排入次日复习；只有标记掌握度后才保存本题。',
            style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
        TextButton.icon(
            onPressed: editNote,
            icon: Icon(Icons.edit_note),
            label: Text('写题目笔记'))
      ],
      if (widget.exam) ...[
        SizedBox(height: 24),
        Row(children: [
          OutlinedButton(
              onPressed:
                  index == 0 || busy ? null : () => setState(() => index--),
              child: Text('上一题')),
          Spacer(),
          FilledButton(
              onPressed: busy
                  ? null
                  : () => index + 1 < widget.questions.length
                      ? setState(() => index++)
                      : confirmSubmit(),
              child:
                  Text(index + 1 == widget.questions.length ? '交卷并分析' : '下一题'))
        ]),
        SizedBox(height: 14),
        Text(
            '已作答 ${answers.values.where((a) => a.trim().isNotEmpty).length} / ${widget.questions.length} · 到时自动交卷',
            style: TextStyle(fontSize: 12, color: Colors.blueGrey))
      ]
    ];
  }

  Widget gradeButton(String text, String value, Color color,
          {bool enabled = true}) =>
      FilledButton(
          onPressed: busy || !enabled ? null : () => grade(value),
          style: FilledButton.styleFrom(backgroundColor: color),
          child: Text(text));
  List<Widget> explanation(Question question) => [
        box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('参考答案：${question.answer ?? question.data['rubric']}',
              style: TextStyle(fontWeight: FontWeight.bold, color: teal)),
          SizedBox(height: 12),
          SourceDetails(question: question),
          Text(question.explanation, style: TextStyle(height: 1.8)),
          SizedBox(height: 8),
          Wrap(
              spacing: 6,
              runSpacing: 6,
              children: question.tags.map(pill).toList())
        ]))
      ];
  Future<void> editNote() async {
    final field =
        TextEditingController(text: store.learning.states[q.id]?.note ?? '');
    final value = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text('个人笔记'),
                content: TextField(
                    controller: field,
                    minLines: 5,
                    maxLines: 10,
                    maxLength: 10000,
                    decoration: InputDecoration(hintText: '记录你的理解与易混点')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c), child: Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, field.text),
                      child: Text('保存'))
                ]));
    if (value != null && mounted)
      await safely(context, () => store.add(q.id, 'note', value));
  }

  Future<void> confirmSubmit() async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text('确认交卷'),
                content:
                    Text('未答客观题记 0 分。主观题对照要点自评，不计入自动得分。答对题目先按“蒙对 / 不稳”安排复习。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: Text('继续检查')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: Text('交卷'))
                ]));
    if (ok == true) await submitExam();
  }

  List<Widget> report() {
    final objective = widget.questions.where((q) => q.answer != null).toList();
    final correct = objective.where((q) => answers[q.id] == q.answer).length;
    final total =
        objective.fold<int>(0, (sum, q) => sum + (q.data['points'] as int));
    final score = objective
        .where((q) => answers[q.id] == q.answer)
        .fold<int>(0, (sum, q) => sum + (q.data['points'] as int));
    return [
      box(Column(children: [
        Icon(Icons.task_alt, color: teal, size: 48),
        SizedBox(height: 16),
        Text(widget.exam ? '客观题 $score / $total 分' : '本次练习已完成',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
        SizedBox(height: 10),
        Text('客观题正确 $correct / ${objective.length} · 复习计划已更新'),
        if (widget.exam)
          Text('主观题不包含在自动得分中；请在下方完成自评。',
              style: TextStyle(fontSize: 12, color: Colors.blueGrey))
      ])),
      heading('逐题回顾'),
      ...widget.questions.map((question) => Card(
          elevation: 0,
          child: ExpansionTile(
              title: Text(question.stem, style: TextStyle(fontSize: 15)),
              subtitle: Text('你的作答：${answers[question.id] ?? '未作答'}',
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              children: [
                Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...explanation(question),
                          if (widget.exam &&
                              question.answer == null &&
                              (answers[question.id]?.trim().isNotEmpty ??
                                  false) &&
                              !saved.contains(question.id)) ...[
                            SizedBox(height: 12),
                            Text('对照要点后自评（仅保存一次）'),
                            Wrap(
                                spacing: 8,
                                children: ['wrong', 'guessed', 'mastered']
                                    .map((g) => TextButton(
                                        onPressed: busy
                                            ? null
                                            : () => safely(context, () async {
                                                  setState(() => busy = true);
                                                  try {
                                                    await save(question, g,
                                                        mode: 'exam');
                                                  } finally {
                                                    if (mounted)
                                                      setState(
                                                          () => busy = false);
                                                  }
                                                }),
                                        child: Text({
                                          'wrong': '做错',
                                          'guessed': '不稳',
                                          'mastered': '掌握'
                                        }[g]!)))
                                    .toList())
                          ],
                          if (saved.contains(question.id))
                            Text(
                                '下次复习：${store.learning.states[question.id]?.due ?? '—'}',
                                style: TextStyle(color: teal, fontSize: 12))
                        ]))
              ]))),
      SizedBox(height: 20),
      FilledButton(
          onPressed: () => Navigator.pop(context), child: Text('返回学习首页'))
    ];
  }
}
