import 'package:dentstudy/features/profile/question_bank_import_progress.dart';
import 'package:dentstudy/features/profile/text_bank_converter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('import progress exposes truthful stages and file requirements',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Column(children: [
      QuestionBankImportProgress(
          stage: QuestionBankImportStage.syncing, detail: '正在同步到作者私密审核箱…'),
      TextBankSourceRequirements(initiallyExpanded: true),
    ]))));

    expect(find.text('读取文件'), findsOneWidget);
    expect(find.text('核对题目'), findsOneWidget);
    expect(find.text('保存练习'), findsOneWidget);
    expect(find.text('私密同步'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('仅支持 Office 2007'), findsOneWidget);
    expect(find.textContaining('不支持旧版 .doc、PDF、图片/扫描件'), findsOneWidget);
  });

  test('progress only advances after the corresponding stage completes', () {
    expect(QuestionBankImportStage.reading.completedSteps, 0);
    expect(QuestionBankImportStage.validating.completedSteps, 1);
    expect(QuestionBankImportStage.saving.completedSteps, 2);
    expect(QuestionBankImportStage.syncing.completedSteps, 3);
    expect(QuestionBankImportStage.complete.completedSteps, 4);
    expect(QuestionBankImportStage.partial.completedSteps, 3);
  });
}
