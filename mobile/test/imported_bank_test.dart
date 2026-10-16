import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentstudy/app/shared.dart' as app;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    app.store.prefs = await SharedPreferences.getInstance();
    app.store.userId = 'import-test-user';
    app.store.questions = [];
    app.store.events = [];
    app.store.pending = [];
    app.store.drafts = {};
    app.store.sessions = [];
    app.store.dailyPlan = null;
    app.store.importedQuestionIds = {};
    app.store.lastImportedBankName = null;
    app.store.dailyNewLimit = 10;
    app.store.dailyReviewTarget = null;
    app.store.settingsUpdatedAt = '1970-01-01T00:00:00.000000Z';
  });

  test('simple learner template expands into a valid private bank', () async {
    const source = '''{
      "name": "修复错题整理",
      "questions": [{
        "subject": "口腔修复学",
        "chapter": "固定义齿",
        "stem": "用于测试导入的题目？",
        "options": ["选项甲", "选项乙", "选项丙", "选项丁"],
        "answer": "A",
        "modes": ["考研", "执医"]
      }]
    }''';

    final prepared = app.store.prepareQuestionBankImport(source);
    final bank = jsonDecode(prepared.content) as Map<String, dynamic>;
    final question = (bank['questions'] as List).single as Map<String, dynamic>;

    expect(prepared.name, '修复错题整理');
    expect(question['type'], 'A1');
    expect(
        question['options'], {'A': '选项甲', 'B': '选项乙', 'C': '选项丙', 'D': '选项丁'});
    expect(question['sourceType'], 'user_material');
    expect(question['reviewStatus'], 'draft');
    expect(question['modes'], ['考研', '执医']);

    await app.store.importPreparedQuestionBank(prepared);
    expect(app.store.importedQuestions, hasLength(1));
    expect(app.store.importedQuestions.single.stem, '用于测试导入的题目？');
    expect(app.store.lastImportedBankName, '修复错题整理');
    expect(
        app.store.prefs
            .getStringList('importedQuestionIds:import-test-user')!
            .single,
        question['id']);
    final localImport = jsonDecode(
            app.store.prefs.getString('importedQuestionBank:import-test-user')!)
        as Map;
    expect((localImport['questions'] as List), hasLength(1));
    expect(app.store.prefs.getString('bank'), isNull,
        reason: 'the full bundled bank must never consume browser storage');

    await app.store.add(question['id'] as String, 'review', {
      'answer': 'A',
      'grade': 'mastered',
      'mode': 'practice',
    });
    expect(app.store.events, hasLength(1));
    expect(app.store.pending, isEmpty,
        reason: 'personal imports are not present in the server question bank');
  });
}
