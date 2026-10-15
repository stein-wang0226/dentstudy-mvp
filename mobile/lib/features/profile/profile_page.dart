import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../app/shared.dart';
import '../../app/build_info.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool importingBank = false;
  bool loadingSubmissions = false;
  bool isSubmissionAdmin = false;
  List<Map<String, dynamic>> submissionInbox = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => refreshSubmissionInbox());
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> refreshSubmissionInbox() async {
    if (store.token.isEmpty) {
      if (mounted)
        setState(() {
          isSubmissionAdmin = false;
          submissionInbox = [];
        });
      return;
    }
    setState(() => loadingSubmissions = true);
    try {
      final result = await store.questionBankSubmissions();
      if (!mounted) return;
      setState(() {
        isSubmissionAdmin = result['isAdmin'] == true;
        submissionInbox = (result['submissions'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      });
    } catch (_) {
      // The personal learning experience stays usable if the optional inbox
      // endpoint is unavailable while an older server is being updated.
    } finally {
      if (mounted) setState(() => loadingSubmissions = false);
    }
  }

  Future<void> pickQuestionBank() async {
    setState(() => importingBank = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['json'],
          withData: true);
      if (picked == null) return;
      final file = picked.files.single;
      if (!file.name.toLowerCase().endsWith('.json') || file.bytes == null) {
        throw Exception('请选择可以读取的 .json 题库文件');
      }
      final content = utf8.decode(file.bytes!, allowMalformed: false);
      final imported = await store.importQuestionBank(content);
      if (store.token.isEmpty) {
        if (mounted) message(context, '已导入 $imported 道题到本机。');
        return;
      }
      try {
        final submitted = await store.submitQuestionBank(
            filename: file.name, content: content);
        if (mounted) {
          message(
              context,
              submitted['duplicate'] == true
                  ? '本机已导入；这份文件此前已投稿。'
                  : '已导入 $imported 道题，本文件已提交给作者审核。');
        }
        await refreshSubmissionInbox();
      } catch (error) {
        if (mounted) {
          message(context, '已导入 $imported 道题到本机；投稿上传未完成：$error');
        }
      }
    } on FormatException {
      if (mounted) message(context, '文件编码无法识别，请保存为 UTF-8 JSON 后重试。');
    } catch (error) {
      if (mounted) message(context, error.toString());
    } finally {
      if (mounted) setState(() => importingBank = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageBody(children: profile());
  List<Widget> profile() => [
        heading('把进步留在每一天',
            sub: store.email.isEmpty ? '当前为本机访客模式' : store.email),
        box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(store.syncMessage),
          SizedBox(height: 10),
          Text('待同步记录：${store.pending.length} 条',
              style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
          SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: [
            FilledButton(
                onPressed: store.syncing
                    ? null
                    : () => store.token.isEmpty
                        ? showAccountDialog(context)
                        : safely(context, store.sync),
                child: Text(store.syncing
                    ? '同步中…'
                    : store.token.isEmpty
                        ? '登录 / 注册'
                        : '立即同步')),
            if (store.token.isNotEmpty)
              OutlinedButton(
                  onPressed: store.syncing
                      ? null
                      : () => safely(context, store.importGuest),
                  child: Text('导入本机访客记录')),
            if (store.token.isNotEmpty)
              TextButton(
                  onPressed: () async {
                    await safely(context, store.logout);
                    await refreshSubmissionInbox();
                  },
                  child: Text('退出登录'))
          ])
        ])),
        heading('主题色'),
        box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('选择你喜欢的界面主色，深浅层级会自动保持一致。'),
          SizedBox(height: 14),
          Wrap(
              spacing: 12,
              runSpacing: 12,
              children: themeColors.entries.map((entry) {
                final selected = store.themeColorKey == entry.key;
                return Tooltip(
                    message: themeNames[entry.key]!,
                    child: InkWell(
                        onTap: () => safely(
                            context, () => store.setThemeColor(entry.key)),
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                            width: 42,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: entry.value,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: selected ? ink : Colors.transparent,
                                    width: 3)),
                            child: selected
                                ? Icon(Icons.check, color: Colors.white)
                                : null)));
              }).toList())
        ])),
        heading('导入题库 / 投稿'),
        box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('仅支持 JSON 题库文件。会先导入当前设备供你本地练习；登录后，原文件会提交至作者的私有投稿箱供人工查看。'),
          const SizedBox(height: 8),
          const Text('请仅上传你有权分享的资料；不要上传含个人隐私、受限或来源不明的内容。',
              style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
          const SizedBox(height: 14),
          FilledButton.icon(
              onPressed: importingBank ? null : pickQuestionBank,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(importingBank
                  ? '正在导入…'
                  : store.token.isEmpty
                      ? '选择 JSON 并本地导入'
                      : '选择 JSON 并投稿')),
        ])),
        if (isSubmissionAdmin) ...[
          heading('题库投稿箱', sub: '仅作者账号可见 · 文件保存在服务器私有目录'),
          box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                    onPressed:
                        loadingSubmissions ? null : refreshSubmissionInbox,
                    icon: const Icon(Icons.refresh),
                    label: const Text('刷新'))),
            if (submissionInbox.isEmpty)
              const Text('暂时还没有投稿。', style: TextStyle(color: Colors.blueGrey))
            else
              ...submissionInbox.map((item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined),
                  title: Text(item['filename'] as String),
                  subtitle: Text(
                      '${item['email'] ?? '本人投稿'} · ${item['question_count']} 题 · ${_formatSubmissionTime(item['submitted_at'] as String)}'),
                  trailing: Text(_formatBytes(item['content_bytes'] as int),
                      style: const TextStyle(
                          fontSize: 12, color: Colors.blueGrey))))
          ]))
        ],
        heading('学习设置'),
        box(Column(children: [
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.flag_outlined),
              title: Text('每日学习目标'),
              subtitle: Text(
                  '新题上限 ${store.dailyNewLimit} · 复习目标 ${store.dailyReviewTarget == null ? '无限制' : store.dailyReviewTarget}'),
              onTap: goalsDialog),
          Divider(),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('每日复习提醒'),
              subtitle: Text('本地通知 · 北京时间 20:00 · 未来 14 天'),
              value: store.prefs.getBool('reminders') ?? false,
              onChanged: (v) => safely(context, () async {
                    if (v && !await reminders.enable())
                      throw Exception('通知权限未获允许，请在系统设置中开启');
                    await store.prefs.setBool('reminders', v);
                    await reminders.refresh(store);
                    changed();
                  })),
          Divider(),
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.download_for_offline_outlined),
              title: Text('下载 / 更新离线题库'),
              subtitle: Text('${store.catalog.countLabel}；断网可答题'),
              onTap: () => safely(context, () async {
                    await store.download();
                    if (mounted) message(context, '离线题库已更新');
                  })),
        ])),
        heading('关于题库'),
        box(Text(
            '${store.catalog.countLabel}。\n资料整理题与演示题分别标注审核状态；题量不代表学科覆盖完整。')),
        const SizedBox(height: 20),
        const Text(
            '齿间 DentStudy · ${BuildInfo.version}\n更新于 ${BuildInfo.builtAt}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
      ];

  Future<void> goalsDialog() async {
    final newField = TextEditingController(text: '${store.dailyNewLimit}');
    final reviewField =
        TextEditingController(text: '${store.dailyReviewTarget ?? 20}');
    var unlimited = store.dailyReviewTarget == null;
    final result = await showDialog<(int, int?)>(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (c, set) => AlertDialog(
                    title: Text('每日学习目标'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: newField,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                              labelText: '每日新题上限（0–1,000,000）')),
                      SizedBox(height: 12),
                      SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('复习题不设上限'),
                          value: unlimited,
                          onChanged: (v) => set(() => unlimited = v)),
                      if (!unlimited)
                        TextField(
                            controller: reviewField,
                            keyboardType: TextInputType.number,
                            decoration:
                                InputDecoration(labelText: '每日复习题目标（0–200）')),
                      SizedBox(height: 8),
                      Text('到期复习仍需全部完成，才能解锁新题。',
                          style:
                              TextStyle(fontSize: 12, color: Colors.blueGrey)),
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c), child: Text('取消')),
                      FilledButton(
                          onPressed: () {
                            final n = int.tryParse(newField.text),
                                r = unlimited
                                    ? null
                                    : int.tryParse(reviewField.text);
                            if (n == null ||
                                n < 0 ||
                                n > 1000000 ||
                                (!unlimited &&
                                    (r == null || r < 0 || r > 200))) {
                              message(c, '新题上限为 0–1,000,000；复习目标为 0–200');
                              return;
                            }
                            Navigator.pop(c, (n, r));
                          },
                          child: Text('保存'))
                    ])));
    if (result != null && mounted)
      await safely(context, () async {
        await store.setGoals(result.$1, result.$2);
        await reminders.refresh(store);
      });
  }

  String _formatSubmissionTime(String value) =>
      value.replaceFirst('T', ' ').replaceFirst('Z', '');

  String _formatBytes(int value) => value < 1024 * 1024
      ? '${(value / 1024).toStringAsFixed(0)} KB'
      : '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
}

Future<void> showAccountDialog(BuildContext context) async {
  final email = TextEditingController(),
      password = TextEditingController(),
      confirmPassword = TextEditingController();
  bool register = false, busy = false;
  String? error;
  await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
          builder: (c, set) => AlertDialog(
                  title: Text(register ? '创建学习账号' : '同步学习进度'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(labelText: '邮箱')),
                    SizedBox(height: 10),
                    TextField(
                        controller: password,
                        obscureText: true,
                        decoration: InputDecoration(labelText: '密码（至少10位）')),
                    if (register) ...[
                      SizedBox(height: 10),
                      TextField(
                          controller: confirmPassword,
                          obscureText: true,
                          decoration: InputDecoration(labelText: '确认密码')),
                      SizedBox(height: 10),
                      const Text('务必记住密码，目前忘记密码无法找回！！！',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.deepOrange))
                    ],
                    SizedBox(height: 10),
                    Text('登录后访客记录独立保留，可在“我的”中手动导入。',
                        style: TextStyle(fontSize: 12)),
                    if (error != null)
                      Text(error!, style: TextStyle(color: Colors.red)),
                    TextButton(
                        onPressed:
                            busy ? null : () => set(() => register = !register),
                        child: Text(register ? '已有账号？登录' : '没有账号？注册'))
                  ])),
                  actions: [
                    TextButton(
                        onPressed: busy ? null : () => Navigator.pop(c),
                        child: Text('取消')),
                    FilledButton(
                        onPressed: busy
                            ? null
                            : () async {
                                if (register &&
                                    password.text != confirmPassword.text) {
                                  set(() => error = '两次输入的密码不一致');
                                  return;
                                }
                                set(() => busy = true);
                                try {
                                  await store.login(
                                      email.text, password.text, register);
                                  if (c.mounted) Navigator.pop(c);
                                } catch (e) {
                                  if (c.mounted)
                                    set(() {
                                      error = e.toString();
                                      busy = false;
                                    });
                                }
                              },
                        child: Text(busy ? '连接中…' : '继续'))
                  ])));
}
