import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/shared.dart';

const _template = '''{
  "name": "我的口腔题库",
  "questions": [
    {
      "subject": "口腔修复学",
      "chapter": "第一章 牙体缺损修复",
      "type": "A1",
      "stem": "把这里换成题干",
      "options": {
        "A": "选项 A",
        "B": "选项 B",
        "C": "选项 C",
        "D": "选项 D"
      },
      "answer": "A",
      "explanation": "写上答案解析（可不填）",
      "reference": "自己的资料来源（可不填）",
      "modes": ["考研"]
    }
  ]
}''';

class QuestionBankImportHelp extends StatelessWidget {
  const QuestionBankImportHelp({super.key});

  @override
  Widget build(BuildContext context) => ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 4),
          leading: Icon(Icons.code_rounded, color: teal),
          title: const Text('没有 JSON？从模板开始'),
          subtitle: const Text('只填题干、选项、答案即可，系统会补齐内部字段'),
          children: [
            const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                    '1. 复制模板，粘贴到文本编辑器；\n2. 按题目继续添加对象；\n3. 用 UTF-8 编码保存为 .json 文件后上传。\n\nsubject 只能填写现有口腔学科名称；A1/A2 的 answer 要和选项编号一致，例如 A。')),
            Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: teal.withAlpha(12),
                    borderRadius: BorderRadius.circular(12)),
                child: const SelectableText(_template,
                    style: TextStyle(
                        fontFamily: 'monospace', fontSize: 11, height: 1.45))),
            const SizedBox(height: 10),
            Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                          const ClipboardData(text: _template));
                      if (context.mounted) message(context, 'JSON 模板已复制');
                    },
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('复制 JSON 模板'))),
          ]);
}
