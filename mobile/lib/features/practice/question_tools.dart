import 'package:flutter/material.dart';
import '../../models.dart';
import '../../store.dart';
import '../../app/shared.dart' show safely;
import '../library/catalog.dart';

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
                    child: Text(question.reference,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.blueGrey))))
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
                  onPressed: () => _note(c))
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
}
