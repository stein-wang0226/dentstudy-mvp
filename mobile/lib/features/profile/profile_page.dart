import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../../app/shared.dart';
import '../../app/build_info.dart';
import 'user_avatar.dart';
import 'profile_editor.dart';
import 'author_comments_page.dart';
import 'author_records_page.dart';
import 'appearance_settings.dart';
import 'policy_page.dart';
import 'question_bank_import_help.dart';
import 'imported_bank_practice.dart';
import 'text_bank_converter.dart';
import '../practice/practice_request.dart';

class ProfilePage extends StatefulWidget {
  final StartPractice onStart;
  const ProfilePage({super.key, required this.onStart});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool importingBank = false;
  bool isSubmissionAdmin = false;
  int? submissionCount;
  bool loadingProfile = false;
  Map<String, dynamic> accountProfile = {};
  int? authorUserCount;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => refreshAccountData());
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> refreshSubmissionInbox() async {
    if (store.token.isEmpty) {
      if (mounted)
        setState(() {
          isSubmissionAdmin = false;
          submissionCount = null;
          authorUserCount = null;
        });
      return;
    }
    try {
      final result = await store.questionBankSubmissions();
      if (!mounted) return;
      setState(() {
        isSubmissionAdmin = result['isAdmin'] == true;
        submissionCount = (result['submissions'] as List).length;
      });
      if (isSubmissionAdmin) await refreshAuthorUserDirectory();
    } catch (_) {
      // The personal learning experience stays usable if the optional inbox
      // endpoint is unavailable while an older server is being updated.
    }
  }

  Future<void> refreshAccountData() async {
    await Future.wait([refreshProfile(), refreshSubmissionInbox()]);
  }

  Future<void> refreshProfile() async {
    if (store.token.isEmpty) {
      if (mounted) setState(() => accountProfile = {});
      return;
    }
    if (mounted) setState(() => loadingProfile = true);
    try {
      final result = await store.profile();
      if (mounted) setState(() => accountProfile = result);
    } catch (_) {
      // An older API must not block access to locally stored learning data.
    } finally {
      if (mounted) setState(() => loadingProfile = false);
    }
  }

  Future<void> refreshAuthorUserDirectory() async {
    if (!isSubmissionAdmin || store.token.isEmpty) return;
    try {
      final result = await store.authorUsers();
      if (mounted)
        setState(() {
          authorUserCount =
              result['totalCount'] as int? ?? (result['users'] as List).length;
        });
    } catch (_) {
      // The author inbox remains optional while a rolling deployment updates.
    }
  }

  Future<void> openAuthorRecords(AuthorRecordKind kind) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => AuthorRecordsPage(kind: kind)));
    if (mounted) await refreshSubmissionInbox();
  }

  Future<bool> ensureUploadAccount() async {
    if (store.token.isNotEmpty) return true;
    await showAccountDialog(context, onSuccess: refreshAccountData);
    return mounted && store.token.isNotEmpty;
  }

  Future<void> importAndSyncQuestionBank(
      {required String filename, required String content}) async {
    final prepared = store.prepareQuestionBankImport(content);
    final alreadyImported = store.hasImportedQuestionBank(prepared);
    final imported = alreadyImported
        ? prepared.questions.length
        : await store.importPreparedQuestionBank(prepared);
    try {
      final submitted = await store.submitQuestionBank(
          filename: filename, content: prepared.content);
      if (mounted) {
        message(
            context,
            submitted['duplicate'] == true
                ? '已导入 $imported 道题；这份题库此前已同步。'
                : '已导入 $imported 道题，已同步至私密审核箱。');
      }
      await refreshSubmissionInbox();
    } catch (error) {
      if (mounted) {
        message(context, '已导入 $imported 道题；私密同步未完成：$error');
      }
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
      if (!await ensureUploadAccount()) return;
      await importAndSyncQuestionBank(
          filename: file.name,
          content: utf8.decode(file.bytes!, allowMalformed: false));
    } on FormatException {
      if (mounted) message(context, '文件编码无法识别，请保存为 UTF-8 后重试。');
    } catch (error) {
      if (mounted) message(context, error.toString());
    } finally {
      if (mounted) setState(() => importingBank = false);
    }
  }

  Future<void> importFromWordOrText() async {
    final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('从 Word / 纯文字生成题库',
                      style:
                          TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Text(
                      '支持 .docx、.txt 或直接粘贴文字；不支持旧 .doc、PDF、图片。文件不超过 5 MB。',
                      style: TextStyle(color: Colors.blueGrey)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                      onPressed: () => Navigator.pop(sheetContext, 'file'),
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('选择 Word / 文本文件')),
                  TextButton.icon(
                      onPressed: () => Navigator.pop(sheetContext, 'paste'),
                      icon: const Icon(Icons.paste_outlined),
                      label: const Text('直接粘贴纯文字'))
                ]))));
    if (choice == null || !mounted) return;
    setState(() => importingBank = true);
    try {
      String sourceText;
      String sourceName;
      if (choice == 'file') {
        final picked = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: const ['docx', 'txt'],
            withData: true);
        if (picked == null) return;
        final file = picked.files.single;
        final extension = file.extension?.toLowerCase();
        if (file.bytes == null || !const ['docx', 'txt'].contains(extension)) {
          throw Exception('仅支持 .docx 或 .txt；暂不支持 .doc、PDF、图片');
        }
        if (file.bytes!.length > maxTextSourceBytes) {
          throw Exception('Word / 文本文件不能超过 5 MB');
        }
        sourceText = extension == 'docx'
            ? extractDocxText(file.bytes!)
            : utf8.decode(file.bytes!, allowMalformed: false);
        sourceName = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      } else {
        sourceText = '';
        sourceName = '文字转换题库';
      }
      final converted = await showTextBankConverter(context,
          initialText: sourceText, initialName: sourceName);
      if (converted == null || !mounted) return;
      if (!await ensureUploadAccount()) return;
      await importAndSyncQuestionBank(
          filename: converted.filename, content: converted.content);
    } on FormatException {
      if (mounted) message(context, '文本编码无法识别，请保存为 UTF-8 后重试。');
    } catch (error) {
      if (mounted) message(context, error.toString());
    } finally {
      if (mounted) setState(() => importingBank = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageBody(children: profile());
  List<Widget> profile() => [
        const SizedBox(height: 24),
        box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            UserAvatar(
                value: accountProfile['avatar'] as String? ?? 'book',
                radius: 34),
            const SizedBox(width: 16),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                      store.token.isEmpty
                          ? '访客同学'
                          : accountProfile['nickname'] as String? ?? '齿间同学',
                      style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                          color: ink)),
                  const SizedBox(height: 5),
                  Text(
                      store.token.isEmpty
                          ? '把进步留在每一天'
                          : ((accountProfile['university'] as String? ?? '')
                                  .isEmpty
                              ? '填写你的就读院校'
                              : accountProfile['university'] as String),
                      style: const TextStyle(color: Colors.blueGrey)),
                ])),
            if (store.token.isNotEmpty)
              IconButton(
                  tooltip: '编辑个人资料',
                  onPressed: loadingProfile ? null : editProfile,
                  icon: const Icon(Icons.edit_outlined))
          ]),
          if (store.email.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                  child: Text(store.email,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.blueGrey))),
              TextButton(
                  onPressed: store.syncing
                      ? null
                      : () async {
                          await safely(context, store.logout);
                          await refreshAccountData();
                        },
                  child: const Text('退出登录'))
            ])
          ],
          if (store.token.isEmpty) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: () =>
                    showAccountDialog(context, onSuccess: refreshAccountData),
                icon: const Icon(Icons.person_outline),
                label: const Text('登录 / 注册'))
          ]
        ])),
        heading('主题与外观'),
        box(const AppearanceSettings()),
        heading('导入题库'),
        box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('上传一次即可导入本机练习，并同步到仅作者可见的私密审核箱。'),
          const SizedBox(height: 8),
          const Text('不会自动进入公开题库。请仅上传你有权分享的资料；不要上传含个人隐私、受限或来源不明的内容。',
              style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
          const QuestionBankImportHelp(),
          const SizedBox(height: 14),
          FilledButton.icon(
              onPressed: importingBank ? null : pickQuestionBank,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(importingBank ? '正在上传…' : '上传 JSON 题库')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
              onPressed: importingBank ? null : importFromWordOrText,
              icon: const Icon(Icons.description_outlined),
              label: const Text('我只有 Word / 纯文字')),
        ])),
        if (store.importedQuestions.isNotEmpty)
          ImportedBankPractice(onStart: widget.onStart),
        if (isSubmissionAdmin) ...[
          heading('作者管理'),
          box(Column(children: [
            ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.people_outline),
                title: Text(
                    '用户目录${authorUserCount == null ? '' : ' · $authorUserCount 人'}'),
                subtitle: const Text('查看昵称、院校与邮箱'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openAuthorRecords(AuthorRecordKind.users)),
            const Divider(),
            ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_outlined),
                title: Text(
                    '题库投稿箱${submissionCount == null ? '' : ' · $submissionCount 份'}'),
                subtitle: const Text('查看用户提交的题库'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openAuthorRecords(AuthorRecordKind.submissions)),
            const Divider(),
            ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.forum_outlined),
                title: const Text('评论管理'),
                subtitle: const Text('查看发布者、题目与评论'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AuthorCommentsPage()))),
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
        heading('服务与规则'),
        box(ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.policy_outlined, color: teal),
            title: const Text('服务与规则'),
            subtitle: const Text('用户协议、隐私说明、版权投诉与数据删除'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PolicyPage())))),
        const SizedBox(height: 20),
        const Text(
            '齿间 DentStudy · ${BuildInfo.version}\n更新于 ${BuildInfo.builtAt}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
      ];

  Future<void> editProfile() async {
    await showProfileEditor(context, initialProfile: accountProfile);
    if (mounted) await refreshAccountData();
  }

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
}

Future<void> showAccountDialog(BuildContext context,
    {Future<void> Function()? onSuccess}) async {
  bool remember = store.prefs.getBool('rememberPassword') ?? true;
  final email = TextEditingController(
          text: remember ? store.prefs.getString('rememberedEmail') ?? '' : ''),
      password = TextEditingController(),
      confirmPassword = TextEditingController();
  bool register = false,
      busy = false,
      authenticated = false,
      justRegistered = false;
  String? error;
  await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
          builder: (c, set) => AlertDialog(
                  title: Text(register ? '创建学习账号' : '登录学习账号'),
                  content: AutofillGroup(
                      onDisposeAction: AutofillContextAction.cancel,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        TextField(
                            controller: email,
                            autofillHints: remember
                                ? const [
                                    AutofillHints.username,
                                    AutofillHints.email
                                  ]
                                : null,
                            autocorrect: false,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(labelText: '邮箱')),
                        SizedBox(height: 10),
                        TextField(
                            controller: password,
                            autofillHints: remember
                                ? [
                                    register
                                        ? AutofillHints.newPassword
                                        : AutofillHints.password
                                  ]
                                : null,
                            enableSuggestions: false,
                            autocorrect: false,
                            obscureText: true,
                            decoration:
                                InputDecoration(labelText: '密码（至少10位）')),
                        if (register) ...[
                          SizedBox(height: 10),
                          TextField(
                              controller: confirmPassword,
                              autofillHints: remember
                                  ? const [AutofillHints.newPassword]
                                  : null,
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
                        CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text('记住密码'),
                            subtitle: const Text('由浏览器或系统密码管理器保存',
                                style: TextStyle(fontSize: 12)),
                            value: remember,
                            onChanged: busy
                                ? null
                                : (value) =>
                                    set(() => remember = value ?? false)),
                        Text('账号学习进度会自动同步；访客记录保留在本机。',
                            style: TextStyle(fontSize: 12)),
                        if (error != null)
                          Text(error!, style: TextStyle(color: Colors.red)),
                        TextButton(
                            onPressed: busy
                                ? null
                                : () => set(() => register = !register),
                            child: Text(register ? '已有账号？登录' : '没有账号？注册'))
                      ]))),
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
                                  TextInput.finishAutofillContext(
                                      shouldSave: remember);
                                  await store.prefs
                                      .setBool('rememberPassword', remember);
                                  if (remember) {
                                    await store.prefs.setString(
                                        'rememberedEmail', email.text.trim());
                                  } else {
                                    await store.prefs.remove('rememberedEmail');
                                  }
                                  authenticated = true;
                                  justRegistered = register;
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
  Future.delayed(const Duration(milliseconds: 400), () {
    email.dispose();
    password.dispose();
    confirmPassword.dispose();
  });
  if (!authenticated || !context.mounted) return;
  if (justRegistered) {
    try {
      final profile = await store.profile();
      if (context.mounted)
        await showProfileEditor(context,
            initialProfile: profile, onboarding: true);
    } catch (_) {
      if (context.mounted) message(context, '个人资料暂时无法加载，可在“我的”中稍后完善');
    }
  }
  if (context.mounted) await onSuccess?.call();
}
