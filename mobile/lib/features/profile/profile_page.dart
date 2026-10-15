import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../../app/shared.dart';
import '../../app/build_info.dart';
import 'user_avatar.dart';
import 'avatar_crop.dart';
import 'author_comments_page.dart';

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
  bool loadingProfile = false;
  Map<String, dynamic> accountProfile = {};
  List<Map<String, dynamic>> authorUserDirectory = [];
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
          submissionInbox = [];
          authorUserDirectory = [];
          authorUserCount = null;
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
      if (isSubmissionAdmin) await refreshAuthorUserDirectory();
    } catch (_) {
      // The personal learning experience stays usable if the optional inbox
      // endpoint is unavailable while an older server is being updated.
    } finally {
      if (mounted) setState(() => loadingSubmissions = false);
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
          authorUserDirectory = (result['users'] as List)
              .map((user) => Map<String, dynamic>.from(user as Map))
              .toList();
          authorUserCount =
              result['totalCount'] as int? ?? authorUserDirectory.length;
        });
    } catch (_) {
      // The author inbox remains optional while a rolling deployment updates.
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
                  ? '本机已导入；这份文件此前已提交。'
                  : '已导入 $imported 道题，文件已提交保存。');
        }
        await refreshSubmissionInbox();
      } catch (error) {
        if (mounted) {
          message(context, '已导入 $imported 道题到本机；文件提交未完成：$error');
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
            Text(store.email,
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey))
          ]
        ])),
        const SizedBox(height: 12),
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
                        ? showAccountDialog(context,
                            onSuccess: refreshAccountData)
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
                    await refreshAccountData();
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
        heading('导入题库'),
        box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('仅支持 JSON 题库文件，会先导入当前设备供你本地练习；登录后可提交保存。'),
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
                      : '选择 JSON 并提交')),
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
        if (isSubmissionAdmin) ...[
          heading(
              '用户目录${authorUserCount == null ? '' : ' · $authorUserCount 人'}',
              sub: '仅作者账号可见 · 邮箱不会公开显示在评论中'),
          box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                    onPressed: refreshAuthorUserDirectory,
                    icon: const Icon(Icons.refresh),
                    label: const Text('刷新'))),
            if (authorUserDirectory.isEmpty)
              const Text('暂时还没有已注册用户。',
                  style: TextStyle(color: Colors.blueGrey))
            else
              ...authorUserDirectory.map((user) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _profileAvatar(user['avatar'] as String? ?? 'book'),
                  title: Text(user['nickname'] as String? ?? '齿间同学'),
                  subtitle: Text(
                      '${(user['university'] as String? ?? '').isEmpty ? '未填写院校' : user['university']}\n${user['email']}'),
                  isThreeLine: true))
          ]))
        ],
        if (isSubmissionAdmin) ...[
          heading('评论管理'),
          box(ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.forum_outlined),
              title: const Text('查看全部题目评论'),
              subtitle: const Text('查看发布者、题目、评论内容与时间'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AuthorCommentsPage())))),
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

  Widget _profileAvatar(String value) => UserAvatar(value: value);

  Future<String?> pickAvatar(BuildContext dialogContext) async {
    final picked = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (picked == null) return null;
    final bytes = picked.files.single.bytes;
    if (bytes == null || bytes.length > 10 * 1024 * 1024) {
      throw Exception('请选择不超过 10 MB 的图片');
    }
    final image = await decodeAvatarImage(bytes);
    try {
      if (!dialogContext.mounted) return null;
      return await Navigator.of(dialogContext).push<String>(
          MaterialPageRoute(builder: (_) => AvatarCropPage(image: image)));
    } finally {
      // The crop route can still paint during its exit transition.
      Future.delayed(const Duration(milliseconds: 400), image.dispose);
    }
  }

  Future<void> editProfile() async {
    final nickname = TextEditingController(
        text: accountProfile['nickname'] as String? ?? '齿间同学');
    final university = TextEditingController(
        text: accountProfile['university'] as String? ?? '');
    var avatar = accountProfile['avatar'] as String? ?? 'book';
    var picking = false;
    String? avatarError;
    final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (c, set) => AlertDialog(
                    title: const Text('编辑个人资料'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      UserAvatar(value: avatar, radius: 40),
                      TextButton.icon(
                          onPressed: picking
                              ? null
                              : () async {
                                  set(() {
                                    picking = true;
                                    avatarError = null;
                                  });
                                  try {
                                    final selected = await pickAvatar(c);
                                    if (c.mounted && selected != null)
                                      set(() => avatar = selected);
                                  } catch (_) {
                                    if (c.mounted)
                                      set(() => avatarError =
                                          '图片无法读取，请选择 10 MB 以内的 JPG 或 PNG 图片');
                                  } finally {
                                    if (c.mounted) set(() => picking = false);
                                  }
                                },
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(picking ? '正在处理…' : '从图库上传头像')),
                      if (avatarError != null)
                        Text(avatarError!,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.deepOrange)),
                      if (avatar.startsWith('data:image/'))
                        const Text('已选择裁剪后的照片',
                            style: TextStyle(
                                fontSize: 12, color: Colors.blueGrey)),
                      TextField(
                          controller: nickname,
                          maxLength: 24,
                          decoration: const InputDecoration(labelText: '昵称')),
                      const SizedBox(height: 8),
                      TextField(
                          controller: university,
                          maxLength: 60,
                          decoration:
                              const InputDecoration(labelText: '就读院校（可自行填写）')),
                      const SizedBox(height: 12),
                      const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('或使用预设头像',
                              style: TextStyle(fontWeight: FontWeight.w700))),
                      const SizedBox(height: 8),
                      Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            'book',
                            'tooth',
                            'science',
                            'leaf',
                            'star',
                            'smile'
                          ]
                              .map((item) => InkWell(
                                  onTap: picking
                                      ? null
                                      : () => set(() {
                                            avatar = item;
                                            avatarError = null;
                                          }),
                                  borderRadius: BorderRadius.circular(24),
                                  child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: avatar == item
                                                  ? teal
                                                  : Colors.transparent,
                                              width: 2)),
                                      child: _profileAvatar(item))))
                              .toList()),
                      const SizedBox(height: 12),
                      const Text('昵称、头像和院校会显示在题目讨论中；邮箱不会公开。',
                          style:
                              TextStyle(fontSize: 12, color: Colors.blueGrey))
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('取消')),
                      FilledButton(
                          onPressed: picking
                              ? null
                              : () => Navigator.pop(c, {
                                    'nickname': nickname.text,
                                    'university': university.text,
                                    'avatar': avatar,
                                  }),
                          child: const Text('保存'))
                    ])));
    Future.delayed(const Duration(milliseconds: 400), () {
      nickname.dispose();
      university.dispose();
    });
    if (result == null || !mounted) return;
    await safely(context, () async {
      final updated = await store.updateProfile(
          nickname: result['nickname']!,
          avatar: result['avatar']!,
          university: result['university']!);
      if (mounted) setState(() => accountProfile = updated);
      if (isSubmissionAdmin) await refreshAuthorUserDirectory();
    });
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

  String _formatSubmissionTime(String value) =>
      value.replaceFirst('T', ' ').replaceFirst('Z', '');

  String _formatBytes(int value) => value < 1024 * 1024
      ? '${(value / 1024).toStringAsFixed(0)} KB'
      : '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
}

Future<void> showAccountDialog(BuildContext context,
    {Future<void> Function()? onSuccess}) async {
  bool remember = store.prefs.getBool('rememberPassword') ?? true;
  final email = TextEditingController(
          text: remember ? store.prefs.getString('rememberedEmail') ?? '' : ''),
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
                        Text('登录后访客记录独立保留，可在“我的”中手动导入。',
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
                                  if (c.mounted) Navigator.pop(c);
                                  await onSuccess?.call();
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
}
