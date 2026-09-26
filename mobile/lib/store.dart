import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class StudyStore extends ChangeNotifier {
  late SharedPreferences prefs;
  final secure = const FlutterSecureStorage();
  List<Question> questions = [];
  List<Map<String, dynamic>> events = [];
  List<String> pending = [];
  String mode = '考研', email = '', userId = 'guest', baseUrl = '', token = '';
  bool syncing = false;
  String syncMessage = '离线学习 · 记录保存在本机';
  LearningState get learning => LearningState(events, questions);
  List<Question> get bank => questions.where((q) => q.modes.contains(mode)).toList();
  // Review-first is account-wide, including questions from other exam tracks.
  List<Question> get due => learning.due(questions, DateTime.now());
  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    mode = prefs.getString('mode') ?? '考研';
    baseUrl = prefs.getString('baseUrl') ?? const String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8787');
    email = prefs.getString('email') ?? '';
    userId = prefs.getString('userId') ?? 'guest';
    token = await secure.read(key: 'token') ?? '';
    final raw = prefs.getString('bank') ?? await rootBundle.loadString('assets/questions.json');
    questions = (jsonDecode(raw)['questions'] as List).map((q) => Question(Map<String,dynamic>.from(q))).toList();
    _loadAccount();
  }
  void _loadAccount() {
    final data=jsonDecode(prefs.getString('account:$userId') ?? '{"events":[],"pending":[]}');
    events = (data['events'] as List).map((e) => Map<String,dynamic>.from(e)).toList();
    pending = List<String>.from(data['pending']);
  }
  Future<void> _save() async {
    // One atomic preferences value keeps the event log and upload queue together.
    await prefs.setString('account:$userId', jsonEncode({'events':events,'pending':pending}));
    notifyListeners();
  }
  Future<void> setMode(String value) async { mode = value; await prefs.setString('mode', mode); notifyListeners(); }
  Future<void> add(String questionId, String kind, dynamic value) async {
    final random = Random.secure();
    final id = List.generate(20, (_) => random.nextInt(256).toRadixString(16).padLeft(2,'0')).join();
    events.add({'id': id, 'at': DateTime.now().toUtc().toIso8601String(), 'questionId': questionId, 'kind': kind, 'value': value});
    pending.add(id);
    await _save();
  }
  Future<Map<String,dynamic>> request(String path, [Map<String,dynamic>? data]) async {
    final uri = Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');
    if (!['http','https'].contains(uri.scheme) || uri.host.isEmpty) throw Exception('请输入有效的 API 地址');
    if (kReleaseMode && uri.scheme != 'https') throw Exception('发行版本必须使用 HTTPS 服务');
    final headers = {'Content-Type':'application/json', if(token.isNotEmpty) 'Authorization':'Bearer $token'};
    final response = await (data == null ? http.get(uri, headers:headers) : http.post(uri, headers:headers, body:jsonEncode(data))).timeout(const Duration(seconds: 15));
    final body = Map<String,dynamic>.from(jsonDecode(response.body));
    if (response.statusCode >= 400) throw Exception(body['error'] ?? '服务暂不可用');
    return body;
  }
  Future<void> login(String address, String account, String password, bool register) async {
    if (syncing) throw Exception('请等待当前同步完成');
    baseUrl = address.trim();
    final result = await request('/v1/auth/${register ? 'register' : 'login'}', {'email':account, 'password':password});
    token = result['token']; email = result['email']; userId = result['userId'];
    await secure.write(key:'token', value:token);
    await prefs.setString('baseUrl', baseUrl); await prefs.setString('email', email); await prefs.setString('userId', userId);
    _loadAccount(); // Guest history stays in its own namespace, never silently copied to another account.
    try { await sync(); } catch (_) { /* Account is valid; pending data remains available for retry. */ }
  }
  Future<void> importGuest() async {
    if (userId == 'guest' || syncing) return;
    final guest = (jsonDecode(prefs.getString('account:guest') ?? '{"events":[]}')['events'] as List).map((e)=>Map<String,dynamic>.from(e));
    final ids = events.map((e)=>e['id']).toSet();
    for(final event in guest) { if(ids.add(event['id'])) { events.add(event); pending.add(event['id']); } }
    await _save(); await sync();
  }
  Future<void> logout() async {
    if(syncing) throw Exception('请等待当前同步完成');
    // Revoke remotely first; on failure retain the session so the user can retry.
    await request('/v1/auth/logout', {});
    await secure.delete(key:'token'); token=''; userId='guest'; email='';
    await prefs.remove('email'); await prefs.remove('userId');
    _loadAccount(); syncMessage='离线学习 · 记录保存在本机'; notifyListeners();
  }
  Future<void> sync() async {
    if (token.isEmpty || syncing) return;
    syncing=true; notifyListeners();
    try {
      do {
        final ids = pending.take(500).toSet();
        final result = await request('/v1/sync', {'events':events.where((e)=>ids.contains(e['id'])).toList()});
        final remote = (result['events'] as List).map((e)=>Map<String,dynamic>.from(e));
        final merged = {for(final e in events) e['id'] as String:e};
        for(final e in remote) { merged[e['id'] as String]=e; }
        events=merged.values.toList(); pending.removeWhere(ids.contains);
        await _save();
      } while(pending.isNotEmpty);
      syncMessage='已同步 · ${dayOf(DateTime.now())}';
    } catch(e) { syncMessage='同步未完成，记录已保留：$e'; rethrow; }
    finally { syncing=false; notifyListeners(); }
  }
  Future<void> download() async {
    final result = await request('/v1/questions');
    final updated = (result['questions'] as List).map((q)=>Question(Map<String,dynamic>.from(q))).toList();
    // Never discard questions referenced by unsynced or historical events.
    final byId = {for(final q in questions) q.id:q, for(final q in updated) q.id:q};
    questions=byId.values.toList();
    await prefs.setString('bank', jsonEncode({'questions':questions.map((q)=>q.data).toList()}));
    notifyListeners();
  }
}
