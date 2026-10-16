import 'package:flutter/material.dart';

import '../../app/shared.dart';
import '../practice/mode_picker.dart';
import '../practice/practice_request.dart';

class ImportedBankPractice extends StatelessWidget {
  final StartPractice onStart;
  const ImportedBankPractice({super.key, required this.onStart});

  Future<void> _start(BuildContext context) async {
    final questions = store.importedQuestions;
    if (questions.isEmpty) {
      message(context, '导入题库已不在当前设备，请重新上传文件。');
      return;
    }
    final mode =
        await chooseStudyMode(context, review: false, count: questions.length);
    if (mode == null || !context.mounted) return;
    await onStart(PracticeRequest(questions,
        mode: mode, kind: 'imported-bank', label: '导入题库 · 本地练习'));
  }

  @override
  Widget build(BuildContext context) {
    final questions = store.importedQuestions;
    if (questions.isEmpty) return const SizedBox.shrink();
    final name = store.lastImportedBankName;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      heading('练习导入题库'),
      box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.auto_stories_outlined, color: teal),
          const SizedBox(width: 10),
          Expanded(
              child: Text(name == null ? '我的导入题库' : name,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
          Text('${questions.length} 题', style: TextStyle(color: teal))
        ]),
        const SizedBox(height: 8),
        const Text('选择模式后开始；深度、批量、速刷均可使用。',
            style: TextStyle(fontSize: 13, color: Colors.blueGrey)),
        const SizedBox(height: 14),
        SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
                onPressed: () => _start(context),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('练习导入题库')))
      ]))
    ]);
  }
}
