import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'features/library/catalog.dart';
import 'app/theme_palette.dart';

/// The validated, complete JSON sent to the private submission inbox.
///
/// The UI also accepts a smaller learner-friendly shape and expands it into
/// this form before it is stored locally or sent to the server.
class PreparedQuestionBank {
  final String name;
  final String content;
  final List<Question> questions;
  const PreparedQuestionBank(
      {required this.name, required this.content, required this.questions});
}

class StudyStore extends ChangeNotifier {
  static const maxQuestionBankBytes = 12 * 1024 * 1024;
  late SharedPreferences prefs;
  final secure = const FlutterSecureStorage();
  List<Question> questions = [];
  List<Map<String, dynamic>> events = [];
  List<String> pending = [];
  Map<String, dynamic>? continuation;
  Map<String, Map<String, dynamic>> drafts = {};
  List<Map<String, dynamic>> sessions = [];
  Map<String, dynamic>? dailyPlan;
  Set<String> importedQuestionIds = <String>{};
  String? lastImportedBankName;
  Map<String, Question> _bundledQuestions = <String, Question>{};
  String? activeSessionId;
  Future<void> _writeQueue = Future.value();
  QuestionCatalog get catalog => QuestionCatalog(questions, mode);
  String mode = '考研', email = '', userId = 'guest', baseUrl = '', token = '';
  String themeColorKey = 'teal';
  String customPrimaryKey = 'teal', customBackgroundKey = 'teal';
  bool glassEnabled = false;
  int dailyNewLimit = 10;
  int? dailyReviewTarget;
  String settingsUpdatedAt = '1970-01-01T00:00:00.000000Z';
  bool syncing = false;
  String syncMessage = '离线学习 · 记录保存在本机';
  LearningState? _learningCache;
  List<Map<String, dynamic>>? _cachedEvents;
  List<Question>? _cachedQuestions;
  int _cachedCount = -1;
  LearningState get learning {
    if (!identical(_cachedEvents, events) ||
        !identical(_cachedQuestions, questions) ||
        _cachedCount != events.length) {
      _learningCache = LearningState(events, questions);
      _cachedEvents = events;
      _cachedQuestions = questions;
      _cachedCount = events.length;
    }
    return _learningCache!;
  }

  List<Question> get bank =>
      questions.where((q) => q.modes.contains(mode)).toList();
  List<Question> get importedQuestions => questions
      .where((question) => importedQuestionIds.contains(question.id))
      .toList();
  bool hasImportedQuestionBank(PreparedQuestionBank prepared) =>
      prepared.questions.isNotEmpty &&
      prepared.questions
          .every((question) => importedQuestionIds.contains(question.id));
  bool isLocalOnlyQuestionId(Object? questionId) =>
      questionId is String && importedQuestionIds.contains(questionId);
  String get _importedQuestionIdsKey => 'importedQuestionIds:$userId';
  String get _lastImportedBankNameKey => 'lastImportedBankName:$userId';
  String get _importedQuestionBankKey => 'importedQuestionBank:$userId';
  static const _questionOverridesKey = 'questionOverrides';
  // Review-first is account-wide, including questions from other exam tracks.
  List<Question> get due => learning.due(questions, DateTime.now());
  String get today => dayOf(DateTime.now());
  Set<String> get learnedBeforeToday {
    final result = <String>{};
    for (final event in events) {
      if (event['kind'] == 'review' &&
          dayOf(DateTime.parse(event['at'])) != today) {
        result.add(event['questionId'] as String);
      }
    }
    return result;
  }

  Set<String> get answeredToday => events
      .where((event) =>
          event['kind'] == 'review' &&
          dayOf(DateTime.parse(event['at'])) == today)
      .map((event) => event['questionId'] as String)
      .toSet();
  int get todayNewCount =>
      answeredToday.where((id) => !learnedBeforeToday.contains(id)).length;
  int get todayReviewCount =>
      answeredToday.where(learnedBeforeToday.contains).length;
  int get dailyPracticeLimit => 200;
  int get todayPracticeCount => events
      .where((event) =>
          event['kind'] == 'review' &&
          dayOf(DateTime.parse(event['at'])) == today)
      .length;
  int get remainingPractice {
    final limit = dailyPracticeLimit;
    return (limit - todayPracticeCount).clamp(0, limit);
  }

  int get remainingNew =>
      (dailyNewLimit - todayNewCount).clamp(0, dailyNewLimit);
  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    mode = prefs.getString('mode') ?? '考研';
    baseUrl = prefs.getString('baseUrl') ??
        const String.fromEnvironment('API_URL',
            defaultValue: 'http://10.0.2.2:8787');
    email = prefs.getString('email') ?? '';
    userId = prefs.getString('userId') ?? 'guest';
    token = await secure.read(key: 'token') ?? '';
    // Membership and in-app purchases have been retired. Remove only their
    // obsolete local keys; learning records and account data stay untouched.
    await prefs.remove('vipEntitled');
    await secure.delete(key: 'vipPurchaseId');
    themeColorKey = prefs.getString('themeColorKey') ?? 'teal';
    if (themeColorKey != 'custom' && !themeColors.containsKey(themeColorKey))
      themeColorKey = 'teal';
    customPrimaryKey = prefs.getString('customPrimaryKey') ?? 'teal';
    customBackgroundKey = prefs.getString('customBackgroundKey') ?? 'teal';
    if (!themeColors.containsKey(customPrimaryKey)) customPrimaryKey = 'teal';
    if (!themeColors.containsKey(customBackgroundKey))
      customBackgroundKey = 'teal';
    glassEnabled = prefs.getBool('glassEnabled') ?? false;
    const bankAsset = String.fromEnvironment('QUESTION_BANK_ASSET',
        defaultValue: 'assets/all_questions.json');
    final raw = await rootBundle.loadString(bankAsset);
    questions = (jsonDecode(raw)['questions'] as List)
        .map((q) => Question(Map<String, dynamic>.from(q)))
        .toList();
    _bundledQuestions = {
      for (final question in questions) question.id: question
    };
    _loadAccount();
    await _restoreQuestionCache();
  }

  List<Question> _readQuestionCache(String? content) {
    if (content == null || content.isEmpty) return const [];
    try {
      return (jsonDecode(content)['questions'] as List)
          .map((value) => Question(Map<String, dynamic>.from(value)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  bool _isBundledQuestion(Question question) {
    final bundled = _bundledQuestions[question.id];
    return bundled != null &&
        jsonEncode(bundled.data) == jsonEncode(question.data);
  }

  /// Older builds stored all 3,650 bundled questions in browser preferences.
  /// Safari can exhaust its small per-site quota before even a tiny personal
  /// bank is added. Keep only imported questions and server-only overrides;
  /// the bundled asset is always restored from the app package on startup.
  Future<void> _restoreQuestionCache() async {
    final legacy = prefs.getString('bank');
    final savedImported =
        _readQuestionCache(prefs.getString(_importedQuestionBankKey));
    final savedOverrides =
        _readQuestionCache(prefs.getString(_questionOverridesKey));
    final legacyQuestions = _readQuestionCache(legacy);
    final legacyImported = legacyQuestions
        .where((question) => importedQuestionIds.contains(question.id))
        .toList();
    final legacyOverrides = legacyQuestions
        .where((question) =>
            !importedQuestionIds.contains(question.id) &&
            !_isBundledQuestion(question))
        .toList();

    // Clear the legacy full-bank cache first. It is reproducible from the
    // bundled asset and freeing that space makes migration possible in Safari.
    if (legacy != null) await prefs.remove('bank');

    var imported = savedImported.isNotEmpty ? savedImported : legacyImported;
    var overrides =
        savedOverrides.isNotEmpty ? savedOverrides : legacyOverrides;
    if (savedImported.isEmpty && imported.isNotEmpty) {
      try {
        await prefs.setString(
            _importedQuestionBankKey,
            jsonEncode({
              'questions': imported.map((question) => question.data).toList()
            }));
      } catch (_) {
        // The questions remain available for this run. A later import gives a
        // clear space warning rather than corrupting any study records.
      }
    }
    if (savedOverrides.isEmpty && overrides.isNotEmpty) {
      try {
        await prefs.setString(
            _questionOverridesKey,
            jsonEncode({
              'questions': overrides.map((question) => question.data).toList()
            }));
      } catch (_) {
        overrides = const [];
      }
    }
    questions = {
      for (final question in questions) question.id: question,
      for (final question in overrides) question.id: question,
      for (final question in imported) question.id: question,
    }.values.toList();
  }

  void _loadAccount() {
    final data = jsonDecode(
        prefs.getString('account:$userId') ?? '{"events":[],"pending":[]}');
    events = (data['events'] as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    pending = List<String>.from(data['pending']);
    final savedContinuation = data['continuation'];
    continuation = savedContinuation is Map
        ? Map<String, dynamic>.from(savedContinuation)
        : null;
    drafts = (data['drafts'] as Map? ?? {})
        .map((k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v)));
    sessions = (data['sessions'] as List? ?? [])
        .map((v) => Map<String, dynamic>.from(v))
        .toList();
    dailyPlan = data['dailyPlan'] is Map
        ? Map<String, dynamic>.from(data['dailyPlan'])
        : null;
    // Older builds saved only the remaining IDs. Preserve those IDs without
    // inventing the answers or elapsed time they never recorded.
    if (continuation != null && !drafts.containsKey('legacy')) {
      drafts['legacy'] = {
        ...continuation!,
        'id': 'legacy',
        'legacy': true,
        'answers': <String, String>{},
        'saved': <String>[],
        'index': 0
      };
      continuation = null;
    }
    final settings = Map<String, dynamic>.from(data['settings'] ?? {});
    dailyNewLimit = settings['dailyNewLimit'] as int? ?? 10;
    dailyReviewTarget = settings['dailyReviewTarget'] as int?;
    settingsUpdatedAt =
        settings['updatedAt'] as String? ?? '1970-01-01T00:00:00.000000Z';
    importedQuestionIds =
        (prefs.getStringList(_importedQuestionIdsKey) ?? <String>[]).toSet();
    lastImportedBankName = prefs.getString(_lastImportedBankNameKey);
  }

  Future<void> _save() async {
    // One atomic preferences value keeps the event log and upload queue together.
    final key = 'account:$userId';
    final payload = jsonEncode({
      'events': events,
      'pending': pending,
      if (continuation != null) 'continuation': continuation,
      'settings': settingsPayload,
      'drafts': drafts,
      'sessions': sessions,
      'dailyPlan': dailyPlan,
    });
    final write = _writeQueue.then((_) async {
      if (!await prefs.setString(key, payload)) throw Exception('本机存储失败');
    });
    _writeQueue = write.catchError((_) {});
    await write;
    notifyListeners();
  }

  List<Question> resolveQuestions(Iterable<dynamic> ids) {
    final byId = {for (final q in questions) q.id: q};
    return ids.map((id) => byId[id]).whereType<Question>().toList();
  }

  Future<void> saveDraft(Map<String, dynamic> value) async {
    drafts[value['id'] as String] = value;
    await _save();
  }

  Future<void> finishSession(String id, Map<String, dynamic> summary) async {
    drafts.remove(id);
    sessions.removeWhere((s) => s['id'] == id);
    sessions.add(summary);
    await _save();
  }

  Future<void> savePlan(Map<String, dynamic> plan) async {
    dailyPlan = plan;
    await _save();
  }

  Map<String, dynamic> get settingsPayload => {
        'dailyNewLimit': dailyNewLimit,
        'dailyReviewTarget': dailyReviewTarget,
        'updatedAt': settingsUpdatedAt,
      };

  List<Question> get continuationQuestions {
    final ids = continuation?['questionIds'];
    if (ids is! List) return [];
    final byId = {for (final question in questions) question.id: question};
    return ids
        .whereType<String>()
        .map((id) => byId[id])
        .whereType<Question>()
        .toList();
  }

  Future<void> saveContinuation({
    required List<Question> questions,
    required String practiceMode,
    required String kind,
  }) async {
    if (questions.isEmpty) return;
    continuation = {
      'questionIds': questions.map((question) => question.id).toList(),
      'practiceMode': practiceMode,
      'kind': kind,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await _save();
  }

  Future<void> clearContinuation() async {
    if (continuation == null) return;
    continuation = null;
    await _save();
  }

  Future<void> setGoals(int newLimit, int? reviewTarget) async {
    if (newLimit < 0 ||
        newLimit > 1000000 ||
        (reviewTarget != null && (reviewTarget < 0 || reviewTarget > 200))) {
      throw Exception('学习目标超出允许范围');
    }
    dailyNewLimit = newLimit;
    dailyReviewTarget = reviewTarget;
    settingsUpdatedAt = DateTime.now().toUtc().toIso8601String();
    await _save();
    if (token.isNotEmpty) {
      try {
        await sync();
      } catch (_) {/* Saved locally and retried on next sync. */}
    }
  }

  Future<void> setMode(String value) async {
    mode = value;
    await prefs.setString('mode', mode);
    notifyListeners();
  }

  Future<void> setThemeColor(String value) async {
    if (value != 'custom' && !themeColors.containsKey(value))
      throw Exception('请选择已有主题色');
    themeColorKey = value;
    await prefs.setString('themeColorKey', value);
    notifyListeners();
  }

  Future<void> setCustomTheme(
      {required String primary, required String background}) async {
    if (!themeColors.containsKey(primary) ||
        !themeColors.containsKey(background)) {
      throw Exception('请从已有颜色中选择');
    }
    customPrimaryKey = primary;
    customBackgroundKey = background;
    await prefs.setString('customPrimaryKey', primary);
    await prefs.setString('customBackgroundKey', background);
    await setThemeColor('custom');
  }

  Future<void> setGlassEnabled(bool value) async {
    glassEnabled = value;
    await prefs.setBool('glassEnabled', value);
    notifyListeners();
  }

  Future<void> add(String questionId, String kind, dynamic value) async {
    await addMany([
      {'questionId': questionId, 'kind': kind, 'value': value}
    ]);
  }

  Future<void> addMany(List<Map<String, dynamic>> additions) async {
    if (activeSessionId != null) {
      final freshIds = additions
          .where((a) =>
              a['kind'] == 'review' &&
              a['value']?['mode'] != 'exam' &&
              learning.states[a['questionId']]?.lastDay == null)
          .map((a) => a['questionId'])
          .toSet();
      if (freshIds.isNotEmpty && due.isNotEmpty)
        throw Exception('有到期复习题，请返回今日先完成复习；当前作答已保留。');
      if (freshIds.length > remainingNew) throw Exception('今日新题目标已完成，当前作答已保留。');
    }
    final reviewCount =
        additions.where((addition) => addition['kind'] == 'review').length;
    final remaining = remainingPractice;
    if (reviewCount > remaining) {
      throw Exception('今日刷题量已达到 200 道，请明天再继续练习。');
    }
    final random = Random.secure();
    for (final addition in additions) {
      final id = List.generate(
              20, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
          .join();
      events.add({
        'id': id,
        'at': DateTime.now().toUtc().toIso8601String(),
        ...addition,
      });
      // Personal imports intentionally stay on this device. Their IDs are not
      // in the server's reviewed bank, so sending them to /sync would reject
      // an otherwise valid session with “题目不存在”.
      if (!isLocalOnlyQuestionId(addition['questionId'])) pending.add(id);
      final localSession = drafts[activeSessionId] ??
          sessions.where((s) => s['id'] == activeSessionId).firstOrNull;
      if (addition['kind'] == 'review' && localSession != null) {
        final draft = localSession;
        draft['saved'] = <String>{
          ...List<String>.from(draft['saved'] ?? []),
          addition['questionId'] as String
        }.toList();
        draft['eventIds'] = [...List<String>.from(draft['eventIds'] ?? []), id];
        draft['answers'] = {
          ...Map<String, dynamic>.from(draft['answers'] ?? {}),
          addition['questionId']: addition['value']['answer']
        };
      }
    }
    await _save();
  }

  Future<Map<String, dynamic>> request(String path,
      [Map<String, dynamic>? data,
      Duration timeout = const Duration(seconds: 15)]) async {
    final configuredBase = baseUrl.trim();
    final relativeBase = configuredBase.startsWith('/');
    final uri = relativeBase
        ? Uri.base
            .resolve('${configuredBase.replaceAll(RegExp(r'/+$'), '')}$path')
        : Uri.parse('${configuredBase.replaceAll(RegExp(r'/+$'), '')}$path');
    if (!['http', 'https'].contains(uri.scheme) || uri.host.isEmpty)
      throw Exception('请输入有效的 API 地址');
    if (kReleaseMode && uri.scheme != 'https' && !relativeBase)
      throw Exception('发行版本必须使用 HTTPS 服务');
    final headers = {
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token'
    };
    final response = await (data == null
            ? http.get(uri, headers: headers)
            : http.post(uri, headers: headers, body: jsonEncode(data)))
        .timeout(timeout);
    final body = Map<String, dynamic>.from(jsonDecode(response.body));
    if (response.statusCode >= 400) throw Exception(body['error'] ?? '服务暂不可用');
    return body;
  }

  Future<void> login(String account, String password, bool register) async {
    if (syncing) throw Exception('请等待当前同步完成');
    final result = await request('/v1/auth/${register ? 'register' : 'login'}',
        {'email': account, 'password': password});
    token = result['token'];
    email = result['email'];
    userId = result['userId'];
    await secure.write(key: 'token', value: token);
    await prefs.setString('baseUrl', baseUrl);
    await prefs.setString('email', email);
    await prefs.setString('userId', userId);
    _loadAccount(); // Guest history stays in its own namespace, never silently copied to another account.
    try {
      await sync();
    } catch (_) {
      /* Account is valid; pending data remains available for retry. */
    }
  }

  Future<void> importGuest() async {
    if (userId == 'guest' || syncing) return;
    final guest = (jsonDecode(
                prefs.getString('account:guest') ?? '{"events":[]}')['events']
            as List)
        .map((e) => Map<String, dynamic>.from(e));
    final ids = events.map((e) => e['id']).toSet();
    for (final event in guest) {
      if (ids.add(event['id'])) {
        events.add(event);
        pending.add(event['id']);
      }
    }
    await _save();
    await sync();
  }

  Future<void> logout() async {
    if (syncing) throw Exception('请等待当前同步完成');
    // Revoke remotely first; on failure retain the session so the user can retry.
    await request('/v1/auth/logout', {});
    await secure.delete(key: 'token');
    token = '';
    userId = 'guest';
    email = '';
    await prefs.remove('email');
    await prefs.remove('userId');
    _loadAccount();
    syncMessage = '离线学习 · 记录保存在本机';
    notifyListeners();
  }

  Future<void> sync() async {
    if (token.isEmpty || syncing) return;
    syncing = true;
    notifyListeners();
    try {
      // Remove entries made by older builds before personal imports were
      // marked local-only. The events remain in the local learning history.
      final localOnlyEventIds = events
          .where((event) => isLocalOnlyQuestionId(event['questionId']))
          .map((event) => event['id'] as String)
          .toSet();
      if (localOnlyEventIds.isNotEmpty) {
        pending.removeWhere(localOnlyEventIds.contains);
      }
      do {
        final ids = pending.take(500).toSet();
        final result = await request('/v1/sync', {
          'events': events.where((e) => ids.contains(e['id'])).toList(),
          'settings': settingsPayload,
        });
        final remote =
            (result['events'] as List).map((e) => Map<String, dynamic>.from(e));
        final merged = {for (final e in events) e['id'] as String: e};
        for (final e in remote) {
          merged[e['id'] as String] = e;
        }
        events = merged.values.toList();
        pending.removeWhere(ids.contains);
        final remoteSettings = result['settings'];
        if (remoteSettings is Map &&
            (remoteSettings['updatedAt'] as String)
                    .compareTo(settingsUpdatedAt) >=
                0) {
          dailyNewLimit = remoteSettings['dailyNewLimit'] as int;
          dailyReviewTarget = remoteSettings['dailyReviewTarget'] as int?;
          settingsUpdatedAt = remoteSettings['updatedAt'] as String;
        }
        await _save();
      } while (pending.isNotEmpty);
      syncMessage = '已同步 · ${dayOf(DateTime.now())}';
    } catch (e) {
      syncMessage = '同步未完成，记录已保留：$e';
      rethrow;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> download() async {
    final result = await request('/v1/questions');
    final updated = (result['questions'] as List)
        .map((q) => Question(Map<String, dynamic>.from(q)))
        .toList();
    // Never discard questions referenced by unsynced or historical events.
    final byId = {
      for (final q in questions) q.id: q,
      for (final q in updated) q.id: q
    };
    questions = byId.values.toList();
    final overrides =
        updated.where((question) => !_isBundledQuestion(question)).toList();
    if (!await prefs.setString(_questionOverridesKey,
        jsonEncode({'questions': overrides.map((q) => q.data).toList()}))) {
      throw Exception('本机存储空间不足，未能保存离线题库更新');
    }
    notifyListeners();
  }

  PreparedQuestionBank prepareQuestionBankImport(String content) {
    if (content.trim().isEmpty) throw Exception('题库文件为空');
    final bytes = utf8.encode(content).length;
    if (bytes > maxQuestionBankBytes) throw Exception('题库文件不能超过 12 MB');
    final normalized = _normalizeImportedBank(content);
    final normalizedContent = jsonEncode(normalized);
    if (utf8.encode(normalizedContent).length > maxQuestionBankBytes) {
      throw Exception('题库补全后的文件超过 12 MB，请拆分后再上传');
    }
    return PreparedQuestionBank(
        name: normalized['name'] as String,
        content: normalizedContent,
        questions: _readImportedQuestions(normalizedContent));
  }

  Future<int> importPreparedQuestionBank(PreparedQuestionBank prepared) async {
    final imported = prepared.questions;
    final existing = questions.map((question) => question.id).toSet();
    final conflict = imported
        .map((question) => question.id)
        .where(existing.contains)
        .firstOrNull;
    if (conflict != null) {
      throw Exception('题目 ID “$conflict” 已存在；为保护既有学习记录，请更换题目 ID 后再导入。');
    }
    final before = questions;
    final existingImported = questions
        .where((question) => importedQuestionIds.contains(question.id))
        .toList();
    questions = [...questions, ...imported];
    try {
      // Never duplicate the bundled bank in SharedPreferences. Storing only
      // personal imports keeps Safari's site storage free for study records.
      if (!await prefs.setString(
          _importedQuestionBankKey,
          jsonEncode({
            'questions': [
              ...existingImported.map((question) => question.data),
              ...imported.map((question) => question.data),
            ]
          }))) {
        throw Exception('本机存储空间不足，未能保存导入题库');
      }
    } catch (_) {
      questions = before;
      rethrow;
    }
    dailyPlan = null;
    importedQuestionIds = {
      ...importedQuestionIds,
      ...imported.map((q) => q.id)
    };
    lastImportedBankName = prepared.name;
    if (!await prefs.setStringList(
        _importedQuestionIdsKey, importedQuestionIds.toList()..sort())) {
      throw Exception('本机存储空间不足，未能记录导入题库');
    }
    if (!await prefs.setString(_lastImportedBankNameKey, prepared.name)) {
      throw Exception('本机存储空间不足，未能记录导入题库');
    }
    await _save();
    return imported.length;
  }

  Future<int> importQuestionBank(String content) async =>
      importPreparedQuestionBank(prepareQuestionBankImport(content));

  Future<Map<String, dynamic>> submitQuestionBank({
    required String filename,
    required String content,
  }) async {
    if (token.isEmpty) throw Exception('请先登录后再提交题库');
    return request(
        '/v1/question-bank-submissions',
        {'filename': filename, 'content': content},
        const Duration(seconds: 60));
  }

  Future<Map<String, dynamic>> questionBankSubmissions() async {
    if (token.isEmpty) throw Exception('请先登录');
    return request('/v1/question-bank-submissions');
  }

  Future<Map<String, dynamic>> downloadQuestionBankSubmission(
      String submissionId) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{16,100}$').hasMatch(submissionId)) {
      throw Exception('投稿编号无效');
    }
    return request('/v1/admin/question-bank-submissions/$submissionId', null,
        const Duration(seconds: 60));
  }

  Future<Map<String, dynamic>> profile() async {
    if (token.isEmpty) throw Exception('请先登录');
    return request('/v1/profile');
  }

  Future<Map<String, dynamic>> updateProfile({
    required String nickname,
    required String avatar,
    required String university,
  }) async {
    if (token.isEmpty) throw Exception('请先登录');
    return request('/v1/profile', {
      'nickname': nickname,
      'avatar': avatar,
      'university': university,
    });
  }

  Future<Map<String, dynamic>> questionComments(String questionId) async {
    return request('/v1/questions/${Uri.encodeComponent(questionId)}/comments');
  }

  Future<Map<String, dynamic>> postQuestionComment(
      String questionId, String body,
      {String? parentId}) async {
    if (token.isEmpty) throw Exception('登录后即可参与讨论');
    return request('/v1/questions/${Uri.encodeComponent(questionId)}/comments',
        {'body': body, if (parentId != null) 'parentId': parentId});
  }

  Future<Map<String, dynamic>> voteComment(String commentId, int value) async =>
      request('/v1/comments/${Uri.encodeComponent(commentId)}/vote',
          {'value': value});

  Future<void> deleteComment(String commentId) async {
    await request('/v1/comments/${Uri.encodeComponent(commentId)}/delete', {});
  }

  Future<Map<String, dynamic>> authorComments({int offset = 0}) async =>
      request('/v1/admin/comments?offset=$offset');

  Future<Map<String, dynamic>> authorUsers() async {
    if (token.isEmpty) throw Exception('请先登录');
    return request('/v1/admin/users');
  }
}

List<Question> _readImportedQuestions(String content) {
  dynamic decoded;
  try {
    decoded = jsonDecode(content.replaceFirst('\uFEFF', ''));
  } on FormatException {
    throw Exception('文件不是有效 JSON');
  }
  if (decoded is! Map || decoded['questions'] is! List) {
    throw Exception('题库顶层必须是包含 questions 数组的 JSON 对象');
  }
  final rawQuestions = decoded['questions'] as List;
  if (rawQuestions.isEmpty) throw Exception('题库至少需要 1 道题');
  final ids = <String>{};
  final result = <Question>[];
  for (var index = 0; index < rawQuestions.length; index++) {
    final raw = rawQuestions[index];
    if (raw is! Map) throw Exception('第 ${index + 1} 题必须是对象');
    final question = Map<String, dynamic>.from(raw);
    const required = [
      'id',
      'subject',
      'chapter',
      'type',
      'stem',
      'options',
      'answer',
      'explanation',
      'warning',
      'reference',
      'citation',
      'tags',
      'topics',
      'modes',
      'paperId',
      'paperName',
      'durationMinutes',
      'order',
      'points',
      'isDemo',
      'reviewStatus',
      'sourceType',
      'license'
    ];
    final missing = required.where((field) => !question.containsKey(field));
    if (missing.isNotEmpty) {
      throw Exception('第 ${index + 1} 题缺少 ${missing.first} 字段，请使用题库模板');
    }
    final id = question['id'];
    if (id is! String || id.trim().isEmpty || !ids.add(id)) {
      throw Exception('第 ${index + 1} 题的 id 为空或重复');
    }
    for (final field in [
      'subject',
      'chapter',
      'type',
      'stem',
      'explanation',
      'warning',
      'reference',
      'paperId',
      'paperName',
      'license'
    ]) {
      if (question[field] is! String ||
          (question[field] as String).trim().isEmpty) {
        throw Exception('第 ${index + 1} 题的 $field 必须是非空文字');
      }
    }
    if (question['options'] is! Map ||
        !(question['options'] as Map)
            .entries
            .every((entry) => entry.key is String && entry.value is String)) {
      throw Exception('第 ${index + 1} 题的 options 必须是选项文字映射');
    }
    final options = Map<String, String>.from(question['options'] as Map);
    final subjective = question['type'] == '简答题' || question['type'] == '案例分析';
    if (!subjective &&
        (options.length < 2 || !options.containsKey(question['answer']))) {
      throw Exception('第 ${index + 1} 题至少需要两个选项，且答案必须属于选项');
    }
    if (subjective && question['answer'] != null) {
      throw Exception('第 ${index + 1} 题为主观题时 answer 必须为 null');
    }
    for (final field in ['tags', 'topics', 'modes']) {
      if (question[field] is! List ||
          !(question[field] as List).every((value) => value is String)) {
        throw Exception('第 ${index + 1} 题的 $field 必须是文字数组');
      }
    }
    if ((question['modes'] as List).isEmpty) {
      throw Exception('第 ${index + 1} 题至少要指定一个学习方向');
    }
    result.add(Question(question));
  }
  return result;
}

const _importRequiredFields = [
  'id',
  'subject',
  'chapter',
  'type',
  'stem',
  'options',
  'answer',
  'explanation',
  'warning',
  'reference',
  'citation',
  'tags',
  'topics',
  'modes',
  'paperId',
  'paperName',
  'durationMinutes',
  'order',
  'points',
  'isDemo',
  'reviewStatus',
  'sourceType',
  'license'
];

Map<String, dynamic> _normalizeImportedBank(String content) {
  dynamic decoded;
  try {
    decoded = jsonDecode(content.replaceFirst('\uFEFF', ''));
  } on FormatException {
    throw Exception('文件不是有效 JSON，请从模板复制后再填写');
  }
  final Map<String, dynamic> bank;
  if (decoded is List) {
    bank = {'name': '用户导入题库', 'questions': decoded};
  } else if (decoded is Map) {
    bank = Map<String, dynamic>.from(decoded);
  } else {
    throw Exception('题库顶层应为 questions 数组，或直接是题目数组');
  }
  if (bank['questions'] is! List) {
    throw Exception('题库顶层必须包含 questions 数组');
  }
  final rawQuestions = bank['questions'] as List;
  if (rawQuestions.isEmpty) throw Exception('题库至少需要 1 道题');
  final suppliedName = bank['name'];
  final name = suppliedName is String && suppliedName.trim().isNotEmpty
      ? suppliedName.trim()
      : '用户导入题库';
  final normalized = <Map<String, dynamic>>[];
  for (var index = 0; index < rawQuestions.length; index++) {
    final raw = rawQuestions[index];
    if (raw is! Map) throw Exception('第 ${index + 1} 题必须是 JSON 对象');
    final question = Map<String, dynamic>.from(raw);
    final canonical =
        _importRequiredFields.every((field) => question.containsKey(field));
    normalized.add(canonical
        ? question
        : _normalizeSimpleImportedQuestion(question, index + 1, name));
  }
  return {'version': 1, 'name': name, 'questions': normalized};
}

Map<String, dynamic> _normalizeSimpleImportedQuestion(
    Map<String, dynamic> raw, int position, String bankName) {
  String requiredText(String field, {String? fallback}) {
    final value = raw[field];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (fallback != null) return fallback;
    throw Exception('第 $position 题的 $field 不能为空');
  }

  final subject = requiredText('subject');
  if (!subjects.contains(subject)) {
    throw Exception('第 $position 题的 subject 不在支持科目中，请按模板填写');
  }
  var type = raw['type'] is String ? (raw['type'] as String).trim() : 'A1';
  if (type == '单选题') type = 'A1';
  if (!const ['A1', 'A2'].contains(type)) {
    throw Exception('简化模板暂只支持 A1 或 A2；共用题干请使用完整 JSON 格式');
  }
  final options = _simpleOptions(raw['options'], position);
  final answer = requiredText('answer');
  if (!options.containsKey(answer)) {
    throw Exception('第 $position 题的 answer 必须与选项编号一致，例如 A');
  }
  final chapter = requiredText('chapter', fallback: '未分类章节');
  final stem = requiredText('stem');
  final id = raw['id'] is String && (raw['id'] as String).trim().isNotEmpty
      ? (raw['id'] as String).trim()
      : _generatedImportedId(raw, position);
  final modes = _stringList(raw['modes'], fallback: const ['考研']);
  if (modes.isEmpty ||
      modes.any((mode) => !const ['考研', '本科期末', '执医'].contains(mode))) {
    throw Exception('第 $position 题的 modes 仅可使用 考研、本科期末、执医');
  }
  final tags = _stringList(raw['tags'], fallback: const ['用户导入', '待医学审核']);
  final topics = _stringList(raw['topics'], fallback: [chapter]);
  final reference = requiredText('reference', fallback: '用户自有学习资料');
  final explanation = requiredText('explanation', fallback: '导入资料未提供详细解析。');
  final warning = requiredText('warning', fallback: '请结合教材、课程与专业教师意见核对。');
  final citation = raw['citation'] is Map
      ? Map<String, dynamic>.from(raw['citation'] as Map)
      : <String, dynamic>{'verified': false, 'title': reference};
  final duration = raw['durationMinutes'];
  final order = raw['order'];
  final points = raw['points'];
  return {
    'id': id,
    'subject': subject,
    'chapter': chapter,
    'type': type,
    'stem': stem,
    'options': options,
    'answer': answer,
    'explanation': explanation,
    'warning': warning,
    'reference': reference,
    'citation': citation,
    'tags': tags,
    'topics': topics,
    'modes': modes,
    'paperId':
        raw['paperId'] is String && (raw['paperId'] as String).trim().isNotEmpty
            ? (raw['paperId'] as String).trim()
            : 'user-import-$subject-$chapter',
    'paperName': raw['paperName'] is String &&
            (raw['paperName'] as String).trim().isNotEmpty
        ? (raw['paperName'] as String).trim()
        : '$subject · $bankName（用户导入）',
    'durationMinutes': duration is int && duration > 0 ? duration : 60,
    'order': order is int && order > 0 ? order : position,
    'points': points is int && points > 0 ? points : 1,
    'isDemo': false,
    'reviewStatus': 'draft',
    'sourceType': 'user_material',
    'license':
        raw['license'] is String && (raw['license'] as String).trim().isNotEmpty
            ? (raw['license'] as String).trim()
            : '用户提供资料；仅供本地学习使用，公开前需核实授权与医学审核。',
  };
}

Map<String, String> _simpleOptions(dynamic value, int position) {
  if (value is Map) {
    final options = <String, String>{};
    for (final entry in value.entries) {
      if (entry.key is! String ||
          entry.value is! String ||
          (entry.key as String).trim().isEmpty ||
          (entry.value as String).trim().isEmpty) {
        throw Exception('第 $position 题的 options 必须是非空文字选项');
      }
      options[(entry.key as String).trim()] = (entry.value as String).trim();
    }
    if (options.length >= 2) return options;
  }
  if (value is List &&
      value.length >= 2 &&
      value.every((item) => item is String && item.trim().isNotEmpty)) {
    return {
      for (var index = 0; index < value.length; index++)
        String.fromCharCode(65 + index): (value[index] as String).trim()
    };
  }
  throw Exception('第 $position 题至少需要 2 个 options，例如 {"A":"选项一","B":"选项二"}');
}

List<String> _stringList(dynamic value, {required List<String> fallback}) {
  if (value == null) return List<String>.from(fallback);
  if (value is! List || !value.every((item) => item is String)) {
    throw Exception('tags、topics、modes 需要填写为文字数组');
  }
  return value
      .cast<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList();
}

String _generatedImportedId(Map<String, dynamic> raw, int position) {
  var hash = 0x811c9dc5;
  for (final unit in jsonEncode(raw).codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return 'user-${hash.toRadixString(16)}-$position';
}
