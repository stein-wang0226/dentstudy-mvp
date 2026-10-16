import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';

import '../../models.dart';

const int maxTextSourceBytes = 5 * 1024 * 1024;

class TextBankConversion {
  final String filename;
  final String content;
  const TextBankConversion({required this.filename, required this.content});
}

class TextBankSourceRequirements extends StatelessWidget {
  final bool initiallyExpanded;
  const TextBankSourceRequirements({
    super.key,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) => ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 6),
          initiallyExpanded: initiallyExpanded,
          leading: const Icon(Icons.rule_folder_outlined),
          title: const Text('Word / TXT 文件要求'),
          subtitle: const Text('每题须有题干、选项与明确答案；仅支持客观单选题'),
          children: const [
            Padding(
                padding: EdgeInsets.only(left: 4, right: 4),
                child: Text(
                    '• 仅支持 Office 2007 及以上的 .docx、UTF-8 编码的 .txt，或直接粘贴文字；单个文件不超过 5 MB。\n'
                    '• 不支持旧版 .doc、PDF、图片/扫描件、加密文档；表格、复杂排版可能无法完整识别。\n'
                    '• 每题按行写：题干：…… → A. …… / B. ……（至少两项）→ 答案：A；“解析：”可不填。\n'
                    '• 可用“科目：口腔修复学”“章节：固定义齿”切换分类；科目须为站内已有名称。\n'
                    '• 只转换已有答案的 A1/A2 单选题，不会从讲义、散文或无答案材料中猜题或猜答案。'))
          ]);
}

String extractDocxText(Uint8List bytes) {
  if (bytes.isEmpty) throw Exception('Word 文件为空');
  if (bytes.length > maxTextSourceBytes) {
    throw Exception('Word / 文本文件不能超过 5 MB');
  }
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    final document = archive.findFile('word/document.xml');
    if (document == null) throw Exception('这不是可读取的 .docx 文档');
    if (document.size > maxTextSourceBytes * 3) {
      throw Exception('Word 文档解压后的正文过大，请拆分后再转换');
    }
    final xml = utf8.decode(document.content, allowMalformed: false);
    final text = xml
        .replaceAll(RegExp(r'<w:tab\b[^>]*/>'), '\t')
        .replaceAll(RegExp(r'<w:br\b[^>]*/>'), '\n')
        .replaceAll('</w:tc>', '\t')
        .replaceAll('</w:p>', '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&')
        .trim();
    if (text.isEmpty) throw Exception('Word 文档没有可读取的文字');
    return text;
  } on ArchiveException {
    throw Exception('Word 文件格式无法识别，请使用 .docx 文件');
  } on FormatException {
    throw Exception('Word 文档文字编码无法识别');
  }
}

String convertStructuredTextToJson({
  required String text,
  required String name,
  required String subject,
  required String chapter,
  required String mode,
}) {
  final selectedSubject = subject.trim();
  if (!subjects.contains(selectedSubject)) {
    throw Exception('请选择支持的口腔学科');
  }
  final selectedChapter = chapter.trim().isEmpty ? '未分类章节' : chapter.trim();
  final selectedName = name.trim().isEmpty ? '文字转换题库' : name.trim();
  final questions = <Map<String, dynamic>>[];
  var currentSubject = selectedSubject;
  var currentChapter = selectedChapter;
  String? stem;
  final options = <String, String>{};
  String? answer;
  final explanation = StringBuffer();
  var collectingExplanation = false;
  var startedAt = 0;

  void flush(int line) {
    if (stem == null && options.isEmpty && answer == null) return;
    final prefix = startedAt == 0 ? '第 $line 行附近' : '第 $startedAt 题';
    if (stem == null || stem!.trim().isEmpty) {
      throw Exception('$prefix 缺少题干；请用“题干：”开始一题');
    }
    if (options.length < 2) {
      throw Exception('$prefix 至少需要两项 A. / B. 选项');
    }
    if (answer == null || !options.containsKey(answer)) {
      throw Exception('$prefix 的答案应写成“答案：A”并与选项一致');
    }
    questions.add({
      'subject': currentSubject,
      'chapter': currentChapter,
      'type': 'A1',
      'stem': stem!.trim(),
      'options': Map<String, String>.from(options),
      'answer': answer,
      'explanation': explanation.toString().trim(),
      'reference': '由 Word / 文本转换：$selectedName',
      'modes': [mode],
    });
    stem = null;
    options.clear();
    answer = null;
    explanation.clear();
    collectingExplanation = false;
    startedAt = 0;
  }

  final optionPattern = RegExp(r'^([A-Ha-h])\s*[.．、:：)）]\s*(.+)$');
  final answerPattern = RegExp(r'^(?:答案|参考答案)\s*[:：]\s*([A-Ha-h])\b');
  final stemPattern = RegExp(r'^(?:题干|问题)\s*[:：]\s*(.+)$');
  final explanationPattern = RegExp(r'^(?:解析|答案解析)\s*[:：]\s*(.*)$');
  final subjectPattern = RegExp(r'^科目\s*[:：]\s*(.+)$');
  final chapterPattern = RegExp(r'^章节\s*[:：]\s*(.+)$');
  final numberedStemPattern = RegExp(r'^\d+\s*[.．、]\s*(.+)$');

  final lines = const LineSplitter().convert(text);
  for (var index = 0; index < lines.length; index++) {
    final lineNumber = index + 1;
    final line = lines[index].trim();
    if (line.isEmpty || RegExp(r'^[-—_]{3,}$').hasMatch(line)) continue;

    final subjectMatch = subjectPattern.firstMatch(line);
    if (subjectMatch != null) {
      flush(lineNumber);
      final value = subjectMatch.group(1)!.trim();
      if (!subjects.contains(value)) {
        throw Exception('第 $lineNumber 行的科目不受支持，请从口腔学科中选择');
      }
      currentSubject = value;
      continue;
    }
    final chapterMatch = chapterPattern.firstMatch(line);
    if (chapterMatch != null) {
      flush(lineNumber);
      currentChapter = chapterMatch.group(1)!.trim().isEmpty
          ? selectedChapter
          : chapterMatch.group(1)!.trim();
      continue;
    }
    final stemMatch =
        stemPattern.firstMatch(line) ?? numberedStemPattern.firstMatch(line);
    if (stemMatch != null) {
      flush(lineNumber);
      stem = stemMatch.group(1)!.trim();
      startedAt = lineNumber;
      continue;
    }
    final optionMatch = optionPattern.firstMatch(line);
    if (optionMatch != null) {
      if (stem == null) {
        throw Exception('第 $lineNumber 行的选项前缺少“题干：”');
      }
      collectingExplanation = false;
      options[optionMatch.group(1)!.toUpperCase()] =
          optionMatch.group(2)!.trim();
      continue;
    }
    final answerMatch = answerPattern.firstMatch(line);
    if (answerMatch != null) {
      if (stem == null) throw Exception('第 $lineNumber 行的答案前缺少题干');
      answer = answerMatch.group(1)!.toUpperCase();
      collectingExplanation = false;
      continue;
    }
    final explanationMatch = explanationPattern.firstMatch(line);
    if (explanationMatch != null) {
      if (stem == null) throw Exception('第 $lineNumber 行的解析前缺少题干');
      collectingExplanation = true;
      explanation.write(explanationMatch.group(1)!.trim());
      continue;
    }
    if (collectingExplanation) {
      if (explanation.isNotEmpty) explanation.write('\n');
      explanation.write(line);
      continue;
    }
    if (stem == null) {
      // Word docs often carry a title or a blank heading before the first
      // question. It is not a question until a recognizable question line.
      continue;
    }
    stem = '${stem!}\n$line';
  }
  flush(lines.length);
  if (questions.isEmpty) {
    throw Exception('没有识别到题目。请按“题干 / A. / B. / 答案：A”的格式整理');
  }
  return const JsonEncoder.withIndent('  ')
      .convert({'name': selectedName, 'questions': questions});
}

Future<TextBankConversion?> showTextBankConverter(BuildContext context,
    {String initialText = '', String initialName = '文字转换题库'}) async {
  final name = TextEditingController(text: initialName);
  final chapter = TextEditingController(text: '未分类章节');
  final text = TextEditingController(text: initialText);
  var subject = '口腔修复学';
  var mode = '考研';
  String? error;
  final result = await showDialog<TextBankConversion>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, set) => AlertDialog(
                  title: const Text('从 Word / 纯文字生成 JSON'),
                  content: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: Colors.blueGrey.withAlpha(10),
                                borderRadius: BorderRadius.circular(12)),
                            child: const Text(
                                '仅转换已整理的客观单选题。每题至少要有：题干、A./B. 选项与“答案：A”。解析可选；不会从讲义或散文中猜答案。')),
                        const SizedBox(height: 12),
                        TextField(
                            controller: name,
                            decoration:
                                const InputDecoration(labelText: '题库名称')),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                            initialValue: subject,
                            decoration:
                                const InputDecoration(labelText: '默认科目'),
                            items: subjects
                                .map((item) => DropdownMenuItem(
                                    value: item, child: Text(item)))
                                .toList(),
                            onChanged: (value) =>
                                set(() => subject = value ?? subject)),
                        const SizedBox(height: 10),
                        TextField(
                            controller: chapter,
                            decoration:
                                const InputDecoration(labelText: '默认章节')),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                            initialValue: mode,
                            decoration:
                                const InputDecoration(labelText: '学习方向'),
                            items: const ['考研', '本科期末', '执医']
                                .map((item) => DropdownMenuItem(
                                    value: item, child: Text(item)))
                                .toList(),
                            onChanged: (value) =>
                                set(() => mode = value ?? mode)),
                        const SizedBox(height: 10),
                        TextField(
                          controller: text,
                          minLines: 9,
                          maxLines: 16,
                          decoration: const InputDecoration(
                              alignLabelWithHint: true,
                              labelText: '题目文字',
                              hintText: '题干：……\nA. ……\nB. ……\n答案：A\n解析：……'),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 8),
                          Text(error!,
                              style: const TextStyle(color: Colors.red))
                        ]
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () {
                          try {
                            final content = convertStructuredTextToJson(
                                text: text.text,
                                name: name.text,
                                subject: subject,
                                chapter: chapter.text,
                                mode: mode);
                            final base = name.text.trim().replaceAll(
                                RegExp(r'[^\w\u4e00-\u9fff-]+'), '_');
                            Navigator.pop(
                                dialogContext,
                                TextBankConversion(
                                    filename:
                                        '${base.isEmpty ? '文字转换题库' : base}.json',
                                    content: content));
                          } catch (exception) {
                            set(() => error = exception.toString());
                          }
                        },
                        child: const Text('生成并上传'))
                  ])));
  name.dispose();
  chapter.dispose();
  text.dispose();
  return result;
}
