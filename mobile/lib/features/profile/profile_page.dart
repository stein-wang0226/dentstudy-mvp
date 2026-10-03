import 'package:flutter/material.dart';
import '../../app/shared.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  void changed() {
    if (mounted) setState(() {});
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
                        ? accountDialog()
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
                  onPressed: () => safely(context, store.logout),
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
        heading('VIP 会员'),
        box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(store.isVip ? Icons.workspace_premium : Icons.star_outline,
                color: store.isVip ? Color(0xFFD09A2D) : teal, size: 32),
            SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(store.isVip ? 'VIP 已开通' : '普通用户',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(
                      '今日 ${store.todayPracticeCount} / ${store.dailyPracticeLimit ?? '不限量'} 道',
                      style: TextStyle(fontSize: 12, color: Colors.blueGrey))
                ])),
            if (!store.isVip)
              FilledButton(
                  onPressed: vipDialog, child: Text('${purchases.price} 开通'))
          ]),
          SizedBox(height: 12),
          Text(store.isVip ? 'VIP 每日刷题不限量' : '普通用户每日 200 道；VIP 不限量'),
        ])),
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
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.dns_outlined),
              title: Text('配置后端地址'),
              subtitle: Text(store.baseUrl),
              onTap: apiDialog)
        ])),
        heading('关于题库'),
        box(Text(
            '${store.catalog.countLabel}。\n资料整理题与演示题分别标注审核状态；题量不代表学科覆盖完整。'))
      ];

  Future<void> vipDialog() async {
    purchases.addListener(changed);
    try {
      await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (c) {
            return AnimatedBuilder(
                animation: purchases,
                builder: (c, _) {
                  return SafeArea(
                      child: Padding(
                          padding: EdgeInsets.all(24),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.workspace_premium,
                                size: 56, color: Color(0xFFD09A2D)),
                            SizedBox(height: 12),
                            Text('齿间 VIP',
                                style: TextStyle(
                                    fontSize: 26, fontWeight: FontWeight.bold)),
                            SizedBox(height: 8),
                            Text('${purchases.price} · 一次购买'),
                            SizedBox(height: 18),
                            ListTile(
                                leading: Icon(Icons.bolt, color: teal),
                                title: Text('每日刷题不限量'),
                                subtitle: Text('普通用户每日最多 200 道')),
                            Text(purchases.message,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 12, color: Colors.blueGrey)),
                            SizedBox(height: 16),
                            SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                    onPressed: purchases.loading ||
                                            !purchases.available ||
                                            purchases.product == null
                                        ? null
                                        : () => safely(c, purchases.buy),
                                    child: Text(purchases.loading
                                        ? '处理中…'
                                        : '${purchases.price} 开通 VIP'))),
                            TextButton(
                                onPressed:
                                    purchases.loading || !purchases.available
                                        ? null
                                        : () => safely(c, purchases.restore),
                                child: Text('恢复购买')),
                            Text('付款由 Apple App Store 或 Google Play 完成。',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.blueGrey))
                          ])));
                });
          });
    } finally {
      purchases.removeListener(changed);
    }
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

  Future<void> apiDialog() async {
    final field = TextEditingController(text: store.baseUrl);
    final value = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text('后端地址'),
                content: TextField(
                    controller: field,
                    decoration:
                        InputDecoration(hintText: 'https://api.example.com')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c), child: Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, field.text),
                      child: Text('保存'))
                ]));
    if (value != null) {
      final uri = Uri.tryParse(value.trim());
      if (uri == null ||
          !['https', 'http'].contains(uri.scheme) ||
          uri.host.isEmpty) {
        if (mounted) message(context, '请输入有效地址');
        return;
      }
      if (store.token.isNotEmpty && value.trim() != store.baseUrl) {
        if (mounted) message(context, '切换服务器前请先退出登录');
        return;
      }
      store.baseUrl = value.trim();
      await store.prefs.setString('baseUrl', store.baseUrl);
      changed();
    }
  }

  Future<void> accountDialog() async {
    final address = TextEditingController(text: store.baseUrl),
        email = TextEditingController(),
        password = TextEditingController();
    bool register = false, busy = false;
    String? error;
    await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => StatefulBuilder(
            builder: (c, set) => AlertDialog(
                    title: Text(register ? '创建学习账号' : '同步学习进度'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: address,
                          decoration: InputDecoration(labelText: 'API 地址')),
                      SizedBox(height: 10),
                      TextField(
                          controller: email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(labelText: '邮箱')),
                      SizedBox(height: 10),
                      TextField(
                          controller: password,
                          obscureText: true,
                          decoration: InputDecoration(labelText: '密码（至少10位）')),
                      SizedBox(height: 10),
                      Text('登录后访客记录独立保留，可在“我的”中手动导入。',
                          style: TextStyle(fontSize: 12)),
                      if (error != null)
                        Text(error!, style: TextStyle(color: Colors.red)),
                      TextButton(
                          onPressed: busy
                              ? null
                              : () => set(() => register = !register),
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
                                  set(() => busy = true);
                                  try {
                                    await store.login(address.text, email.text,
                                        password.text, register);
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
}
