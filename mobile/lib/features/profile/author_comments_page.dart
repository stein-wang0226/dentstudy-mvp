import 'package:flutter/material.dart';
import '../../app/shared.dart';
import '../library/question_preview.dart';
import 'user_avatar.dart';

class AuthorCommentsPage extends StatefulWidget {
  const AuthorCommentsPage({super.key});
  @override
  State<AuthorCommentsPage> createState() => _AuthorCommentsPageState();
}

class _AuthorCommentsPageState extends State<AuthorCommentsPage> {
  final List<Map<String, dynamic>> comments = [];
  bool loading = false;
  int? nextOffset, total;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool more = false}) async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result =
          await store.authorComments(offset: more ? nextOffset ?? 0 : 0);
      if (!mounted) return;
      setState(() {
        if (!more) comments.clear();
        comments.addAll((result['comments'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map)));
        nextOffset = result['nextOffset'] as int?;
        total = result['totalCount'] as int;
      });
    } catch (e) {
      if (mounted) setState(() => error = '评论暂时无法加载：$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String time(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return value;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
  }

  void openQuestion(Map<String, dynamic> comment) {
    final questions = store.resolveQuestions([comment['questionId']]);
    if (questions.isEmpty) {
      message(context, '本机暂未收录这道题，请先更新离线题库');
      return;
    }
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => QuestionPreviewPage(questions: questions)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text('评论管理${total == null ? '' : ' · $total 条'}'),
          actions: [
            IconButton(
                tooltip: '刷新评论',
                onPressed: loading ? null : () => load(),
                icon: const Icon(Icons.refresh))
          ]),
      body: PageBody(children: [
        const SizedBox(height: 16),
        if (comments.isEmpty && !loading && error == null)
          const Padding(padding: EdgeInsets.all(24), child: Text('还没有评论。')),
        ...comments.map((comment) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: box(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                UserAvatar(value: comment['avatar'] as String? ?? 'book'),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(comment['nickname'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                          (comment['university'] as String).isEmpty
                              ? '未填写院校'
                              : comment['university'] as String,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.blueGrey))
                    ]))
              ]),
              const SizedBox(height: 8),
              Text(
                  '${comment['email']} · ${time(comment['createdAt'] as String)}',
                  style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
              const Divider(height: 26),
              Text('${comment['subject']} · ${comment['chapter']}',
                  style: TextStyle(fontSize: 12, color: teal)),
              const SizedBox(height: 6),
              Text(comment['stem'] as String,
                  maxLines: 3, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 12),
              if (comment['parentId'] != null)
                const Text('回复评论',
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
              SelectableText(comment['body'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                      onPressed: () => openQuestion(comment),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('查看题目与讨论')))
            ])))),
        if (error != null) ...[
          Text(error!, style: const TextStyle(color: Colors.deepOrange)),
          TextButton(
              onPressed: () => load(more: comments.isNotEmpty),
              child: const Text('重试'))
        ],
        if (loading)
          const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator())),
        if (nextOffset != null && !loading && error == null)
          OutlinedButton(
              onPressed: () => load(more: true), child: const Text('加载更多')),
      ]));
}
