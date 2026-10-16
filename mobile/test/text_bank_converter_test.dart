import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dentstudy/features/profile/text_bank_converter.dart';

void main() {
  test('docx paragraph text is extracted without accepting non-docx files', () {
    const xml = '''<w:document xmlns:w="urn:test"><w:body>
      <w:p><w:r><w:t>题干：Word 题目？</w:t></w:r></w:p>
      <w:p><w:r><w:t>A. 甲</w:t></w:r></w:p>
      <w:p><w:r><w:t>答案：A</w:t></w:r></w:p>
    </w:body></w:document>''';
    final archive = Archive()
      ..addFile(ArchiveFile(
          'word/document.xml', utf8.encode(xml).length, utf8.encode(xml)));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));

    expect(extractDocxText(bytes), contains('题干：Word 题目？'));
    expect(extractDocxText(bytes), contains('答案：A'));
    expect(() => extractDocxText(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<Exception>()));
  });

  test('structured Word-style text becomes a compact JSON bank', () {
    const source = '''
科目：口腔修复学
章节：固定义齿
题干：固定桥的固位体主要依靠什么？
A. 固位力
B. 吸附力
C. 磁力
D. 浮力
答案：A
解析：固位体通过预备体与修复体的摩擦等提供固位。
---
2. 另一道导入题？
A、甲
B、乙
答案：B
''';

    final converted = convertStructuredTextToJson(
        text: source,
        name: 'Word 整理',
        subject: '牙周病学',
        chapter: '默认章节',
        mode: '考研');
    final bank = jsonDecode(converted) as Map<String, dynamic>;
    final questions = (bank['questions'] as List).cast<Map>();

    expect(bank['name'], 'Word 整理');
    expect(questions, hasLength(2));
    expect(questions.first['subject'], '口腔修复学');
    expect(questions.first['chapter'], '固定义齿');
    expect(questions.first['answer'], 'A');
    expect(questions.last['answer'], 'B');
    expect(questions.last['modes'], ['考研']);
  });

  test('structured text explains a missing answer instead of inventing one',
      () {
    expect(
        () => convertStructuredTextToJson(
            text: '题干：没有答案的题\nA. 甲\nB. 乙',
            name: '测试',
            subject: '口腔修复学',
            chapter: '章节',
            mode: '考研'),
        throwsA(isA<Exception>()));
  });
}
