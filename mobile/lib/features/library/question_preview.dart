import 'package:flutter/material.dart';
import '../../models.dart';
import '../../app/shared.dart';
import '../practice/question_tools.dart';

class QuestionPreviewPage extends StatefulWidget {
  final List<Question> questions;
  QuestionPreviewPage({super.key, required this.questions});

  @override
  State<QuestionPreviewPage> createState() => _QuestionPreviewPageState();
}

class _QuestionPreviewPageState extends State<QuestionPreviewPage> {
  int index = 0;

  Question get question => widget.questions[index];

  @override
  Widget build(BuildContext context) {
    final q = question;
    return Scaffold(
        appBar: AppBar(title: Text('题目解析')),
        body: SafeArea(
            child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 800),
                    child: ListView(padding: EdgeInsets.all(20), children: [
                      Row(children: [
                        Text('${index + 1} / ${widget.questions.length}',
                            style: TextStyle(
                                color: teal, fontWeight: FontWeight.bold)),
                        SizedBox(width: 16),
                        Expanded(
                            child: Text('${q.subject} · ${q.chapter}',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 12, color: Colors.blueGrey)))
                      ]),
                      SizedBox(height: 18),
                      QuestionTools(question: q, store: store),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        pill(q.type),
                        ...q.tags.map(pill),
                      ]),
                      SizedBox(height: 22),
                      if (q.data['sharedStem'] != null)
                        Text(q.data['sharedStem'] as String,
                            style: TextStyle(height: 1.7)),
                      Text(q.stem,
                          style: TextStyle(
                              fontSize: 21,
                              height: 1.7,
                              fontWeight: FontWeight.w600,
                              color: ink)),
                      SizedBox(height: 22),
                      ...q.options.entries.map((option) => Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: Container(
                              padding: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                  color: option.key == q.answer
                                      ? teal.withAlpha(25)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: option.key == q.answer
                                          ? teal
                                          : Color(0xFFDDE5DF))),
                              child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(option.key,
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: teal)),
                                    SizedBox(width: 14),
                                    Expanded(
                                        child: Text(option.value,
                                            style: TextStyle(
                                                fontSize: 16, height: 1.5)))
                                  ])))),
                      SizedBox(height: 10),
                      box(Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('参考答案：${q.answer ?? q.data['rubric']}',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, color: teal)),
                            SizedBox(height: 12),
                            SourceDetails(question: q),
                            Text(q.explanation, style: TextStyle(height: 1.8)),
                          ])),
                      SizedBox(height: 20),
                      Row(children: [
                        OutlinedButton(
                            onPressed: index == 0
                                ? null
                                : () => setState(() => index--),
                            child: Text('上一题')),
                        Spacer(),
                        FilledButton(
                            onPressed: index + 1 == widget.questions.length
                                ? null
                                : () => setState(() => index++),
                            child: Text('下一题'))
                      ])
                    ])))));
  }
}
