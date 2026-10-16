import 'package:flutter/material.dart';
import '../../app/shared.dart';
import 'download_file.dart';
import 'user_avatar.dart';

enum AuthorRecordKind { users, submissions }

class AuthorRecordsPage extends StatefulWidget {
  final AuthorRecordKind kind;
  const AuthorRecordsPage({super.key, required this.kind});

  @override
  State<AuthorRecordsPage> createState() => _AuthorRecordsPageState();
}

class _AuthorRecordsPageState extends State<AuthorRecordsPage> {
  List<Map<String, dynamic>> records = [];
  int? total;
  bool loading = false;
  final Set<String> downloadingSubmissions = <String>{};
  String? error;
  bool get isUsers => widget.kind == AuthorRecordKind.users;
  String get title => isUsers ? '用户目录' : '题库投稿箱';
  String get unit => isUsers ? '人' : '份';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = isUsers
          ? await store.authorUsers()
          : await store.questionBankSubmissions();
      if (!isUsers && result['isAdmin'] != true) {
        throw Exception('仅作者账号可查看投稿箱');
      }
      final items = (result[isUsers ? 'users' : 'submissions'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      if (mounted)
        setState(() {
          records = items;
          total = result['totalCount'] as int? ?? items.length;
        });
    } catch (_) {
      if (mounted) setState(() => error = '暂时无法加载，请稍后重试');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String time(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return value;
    String two(int number) => number.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
  }

  String bytes(int value) => value < 1024 * 1024
      ? '${(value / 1024).toStringAsFixed(0)} KB'
      : '${(value / 1024 / 1024).toStringAsFixed(1)} MB';

  Future<void> downloadSubmission(Map<String, dynamic> item) async {
    final id = item['id'] as String? ?? '';
    if (id.isEmpty || downloadingSubmissions.contains(id)) return;
    setState(() => downloadingSubmissions.add(id));
    try {
      final result = await store.downloadQuestionBankSubmission(id);
      final content = result['content'];
      final filename = result['filename'];
      if (content is! String || filename is! String) {
        throw Exception('投稿文件格式异常');
      }
      downloadJsonFile(content: content, filename: filename);
      if (mounted) message(context, '已开始下载 $filename');
    } catch (exception) {
      if (mounted) {
        message(context, exception.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => downloadingSubmissions.remove(id));
    }
  }

  Widget record(Map<String, dynamic> item) => box(isUsers
      ? ListTile(
          contentPadding: EdgeInsets.zero,
          leading: UserAvatar(value: item['avatar'] as String? ?? 'book'),
          title: Text(item['nickname'] as String? ?? '齿间同学'),
          subtitle: Text(
              '${(item['university'] as String? ?? '').isEmpty ? '未填写院校' : item['university']}\n${item['email']}',
              style: const TextStyle(height: 1.6)),
          isThreeLine: true)
      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.description_outlined, color: teal),
            const SizedBox(width: 10),
            Expanded(
                child: Text(item['filename'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w700)))
          ]),
          const SizedBox(height: 10),
          SelectableText(item['email'] as String? ?? '本人投稿',
              style: const TextStyle(color: Colors.blueGrey)),
          const SizedBox(height: 8),
          Text(
              '${item['question_count']} 题 · ${bytes(item['content_bytes'] as int)}',
              style: TextStyle(color: teal)),
          Text(time(item['submitted_at'] as String),
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
          const SizedBox(height: 10),
          Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                  onPressed: downloadingSubmissions.contains(item['id'])
                      ? null
                      : () => downloadSubmission(item),
                  icon: downloadingSubmissions.contains(item['id'])
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download_outlined),
                  label: Text(downloadingSubmissions.contains(item['id'])
                      ? '正在准备…'
                      : '下载 JSON')))
        ]));

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text('$title${total == null ? '' : ' · $total $unit'}'),
          actions: [
            IconButton(
                tooltip: '刷新',
                onPressed: loading ? null : load,
                icon: const Icon(Icons.refresh))
          ]),
      body: SafeArea(
          child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: RefreshIndicator(
                      onRefresh: load,
                      child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          itemCount: records.length + 1,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, index) {
                            if (index < records.length)
                              return record(records[index]);
                            if (loading)
                              return const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Center(
                                      child: CircularProgressIndicator()));
                            if (error != null)
                              return Column(children: [
                                Text(error!,
                                    style: const TextStyle(
                                        color: Colors.blueGrey)),
                                TextButton(
                                    onPressed: load, child: const Text('重试'))
                              ]);
                            if (records.isEmpty)
                              return Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                      isUsers ? '暂时还没有已注册用户。' : '暂时还没有投稿。',
                                      textAlign: TextAlign.center));
                            if (isUsers && total! > records.length)
                              return Text('共 $total 人，当前展示 ${records.length} 人',
                                  textAlign: TextAlign.center);
                            return const SizedBox.shrink();
                          }))))));
}
