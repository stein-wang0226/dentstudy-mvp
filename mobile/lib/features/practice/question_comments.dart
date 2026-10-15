import 'package:flutter/material.dart';
import '../../models.dart';
import '../../app/shared.dart' show box, message, store, teal;
import '../profile/user_avatar.dart';

class QuestionComments extends StatefulWidget {
  final Question question;
  const QuestionComments({super.key, required this.question});

  @override
  State<QuestionComments> createState() => _QuestionCommentsState();
}

class _QuestionCommentsState extends State<QuestionComments> {
  final field = TextEditingController();
  List<Map<String, dynamic>> comments = [];
  bool loading = true, sending = false, composing = false;
  String? loadError;
  int participantCount = 0;
  Map<String, dynamic>? replyingTo;
  final voting = <String>{};
  final deleting = <String>{};
  int loadGeneration = 0;
  final composerKey = GlobalKey();

  void _compose([Map<String, dynamic>? comment]) {
    if (store.token.isEmpty) {
      message(context, '登录后即可参与讨论');
      return;
    }
    setState(() {
      replyingTo = comment;
      composing = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && composerKey.currentContext != null) {
        Scrollable.ensureVisible(composerKey.currentContext!,
            duration: const Duration(milliseconds: 220), alignment: .5);
      }
    });
  }

  @override
  void didUpdateWidget(covariant QuestionComments oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question.id != widget.question.id) {
      field.clear();
      comments = [];
      participantCount = 0;
      replyingTo = null;
      composing = false;
      _load();
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++loadGeneration;
    if (mounted)
      setState(() {
        loading = true;
        loadError = null;
      });
    try {
      final result = await store.questionComments(widget.question.id);
      if (mounted && generation == loadGeneration)
        setState(() {
          comments = (result['comments'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          participantCount = result['participantCount'] as int? ?? 0;
        });
    } catch (_) {
      if (mounted && generation == loadGeneration)
        setState(() => loadError = '讨论暂时无法加载');
    } finally {
      if (mounted && generation == loadGeneration)
        setState(() => loading = false);
    }
  }

  Future<void> _send() async {
    if (store.token.isEmpty) {
      message(context, '登录后即可参与讨论');
      return;
    }
    final body = field.text.trim();
    if (body.isEmpty) {
      message(context, '写点内容再发布吧');
      return;
    }
    setState(() => sending = true);
    try {
      await store.postQuestionComment(widget.question.id, body,
          parentId: replyingTo?['id'] as String?);
      field.clear();
      if (mounted)
        setState(() {
          composing = false;
          replyingTo = null;
        });
      await _load();
    } catch (error) {
      if (mounted) message(context, error.toString());
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _vote(Map<String, dynamic> comment, int value) async {
    if (store.token.isEmpty) {
      message(context, '登录后即可赞同或点踩');
      return;
    }
    final id = comment['id'] as String;
    if (voting.contains(id)) return;
    setState(() => voting.add(id));
    try {
      final result =
          await store.voteComment(id, comment['myVote'] == value ? 0 : value);
      if (mounted) setState(() => comment.addAll(result));
    } catch (e) {
      if (mounted) message(context, e.toString());
    } finally {
      if (mounted) setState(() => voting.remove(id));
    }
  }

  Future<void> _delete(Map<String, dynamic> comment) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('删除这条评论？'),
                content: const Text('删除后不再显示评论内容，其他同学的回复会保留。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('删除'))
                ]));
    if (confirmed != true || !mounted) return;
    final id = comment['id'] as String;
    setState(() => deleting.add(id));
    try {
      await store.deleteComment(id);
      if (!mounted) return;
      if (replyingTo?['id'] == id) setState(() => replyingTo = null);
      await _load();
    } catch (error) {
      if (mounted) message(context, error.toString());
    } finally {
      if (mounted) setState(() => deleting.remove(id));
    }
  }

  Widget _voteButton(Map<String, dynamic> comment, int value) {
    final selected = comment['myVote'] == value;
    final color = value == 1
        ? teal
        : (teal == const Color(0xFFAD4148) ? Colors.indigo : Colors.deepOrange);
    return TextButton.icon(
        onPressed:
            voting.contains(comment['id']) ? null : () => _vote(comment, value),
        style: TextButton.styleFrom(
            foregroundColor: selected ? color : Colors.blueGrey),
        icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Icon(
                value == 1
                    ? (selected ? Icons.thumb_up : Icons.thumb_up_outlined)
                    : (selected ? Icons.thumb_down : Icons.thumb_down_outlined),
                key: ValueKey('$value:$selected'),
                size: 18)),
        label: Text('${comment[value == 1 ? 'likes' : 'dislikes'] ?? 0}'));
  }

  String _time(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    final local = date.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child:
          box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.forum_outlined, size: 20),
          const SizedBox(width: 8),
          Text('题目讨论 · $participantCount 人',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(
              tooltip: '刷新讨论',
              onPressed: loading ? null : _load,
              icon: const Icon(Icons.refresh, size: 20))
        ]),
        const SizedBox(height: 6),
        if (loading)
          const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()))
        else if (loadError != null)
          Text(loadError!, style: const TextStyle(color: Colors.blueGrey))
        else if (comments.isEmpty)
          const Text('暂时还没有讨论，留下你的理解吧。',
              style: TextStyle(color: Colors.blueGrey))
        else
          ...comments.map((comment) => Padding(
              padding: const EdgeInsets.only(top: 14),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                UserAvatar(
                    value: comment['avatar'] as String? ?? '', radius: 18),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                          '${comment['nickname'] ?? '齿间同学'}${(comment['university'] as String? ?? '').isEmpty ? '' : ' · ${comment['university']}'}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(_time(comment['createdAt'] as String? ?? ''),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.blueGrey)),
                      const SizedBox(height: 5),
                      if (comment['parentId'] != null)
                        Text('回复 ${comment['replyTo'] ?? '齿间同学'}',
                            style: TextStyle(fontSize: 12, color: teal)),
                      Text(
                          comment['deletedAt'] != null
                              ? '此评论已由发布者删除'
                              : comment['body'] as String,
                          style: const TextStyle(height: 1.55)),
                      if (comment['deletedAt'] == null)
                        Wrap(spacing: 2, children: [
                          _voteButton(comment, 1),
                          _voteButton(comment, -1),
                          TextButton(
                              onPressed: () {
                                if (store.token.isEmpty) {
                                  message(context, '登录后即可回复');
                                  return;
                                }
                                _compose(comment);
                              },
                              child: const Text('回复')),
                          if (comment['canDelete'] == true)
                            TextButton(
                                onPressed: deleting.contains(comment['id'])
                                    ? null
                                    : () => _delete(comment),
                                child: Text(deleting.contains(comment['id'])
                                    ? '删除中…'
                                    : '删除'))
                        ]),
                    ]))
              ]))),
        const SizedBox(height: 16),
        if (!composing)
          Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                  onPressed: () => _compose(),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('写评论')))
        else ...[
          if (replyingTo != null)
            ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('回复 ${replyingTo!['nickname']}'),
                trailing: IconButton(
                    onPressed: () => setState(() => replyingTo = null),
                    icon: const Icon(Icons.close))),
          TextField(
              key: composerKey,
              autofocus: true,
              controller: field,
              minLines: 2,
              maxLines: 5,
              maxLength: 500,
              decoration: const InputDecoration(hintText: '分享你的理解或易错点'),
              enabled: !sending),
          const SizedBox(height: 8),
          Align(
              alignment: Alignment.centerRight,
              child: Wrap(spacing: 8, children: [
                TextButton(
                    onPressed: sending
                        ? null
                        : () => setState(() => composing = false),
                    child: const Text('取消')),
                FilledButton.icon(
                    onPressed: sending ? null : _send,
                    icon: const Icon(Icons.send_outlined),
                    label: Text(sending ? '发布中…' : '发布评论'))
              ]))
        ]
      ])));
}
