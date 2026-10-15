import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../app/shared.dart';
import 'user_avatar.dart';
import 'avatar_crop.dart';

Future<String?> pickProfileAvatar(BuildContext dialogContext) async {
  final picked =
      await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
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

Future<Map<String, dynamic>?> showProfileEditor(BuildContext context,
    {required Map<String, dynamic> initialProfile,
    bool onboarding = false}) async {
  final nickname = TextEditingController(
      text: initialProfile['nickname'] as String? ?? '齿间同学');
  final university = TextEditingController(
      text: initialProfile['university'] as String? ?? '');
  var avatar = initialProfile['avatar'] as String? ?? 'book';
  var picking = false;
  String? avatarError;
  final result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: !onboarding,
      builder: (c) => StatefulBuilder(
          builder: (c, set) => AlertDialog(
                  title: Text(onboarding ? '完善个人资料' : '编辑个人资料'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                                  final selected = await pickProfileAvatar(c);
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
                          style:
                              TextStyle(fontSize: 12, color: Colors.blueGrey)),
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
                                    child: UserAvatar(value: item))))
                            .toList()),
                    const SizedBox(height: 12),
                    const Text('昵称、头像和院校会显示在题目讨论中；邮箱不会公开。',
                        style: TextStyle(fontSize: 12, color: Colors.blueGrey))
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: Text(onboarding ? '跳过，稍后完善' : '取消')),
                    FilledButton(
                        onPressed: picking
                            ? null
                            : () => Navigator.pop(c, {
                                  'nickname': nickname.text,
                                  'university': university.text,
                                  'avatar': avatar,
                                }),
                        child: Text(onboarding ? '保存并开始' : '保存'))
                  ])));
  Future.delayed(const Duration(milliseconds: 400), () {
    nickname.dispose();
    university.dispose();
  });
  if (result == null || !context.mounted) return null;
  try {
    return await store.updateProfile(
        nickname: result['nickname']!,
        avatar: result['avatar']!,
        university: result['university']!);
  } catch (error) {
    if (context.mounted) message(context, '个人资料未能保存：$error');
    return null;
  }
}
