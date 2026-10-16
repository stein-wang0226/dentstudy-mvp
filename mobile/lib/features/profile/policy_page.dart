import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/shared.dart';

enum PolicyTopic { agreement, privacy, copyright, submission, deletion }

class PolicyPage extends StatelessWidget {
  final PolicyTopic? initialTopic;
  const PolicyPage({super.key, this.initialTopic});

  @override
  Widget build(BuildContext context) {
    if (initialTopic != null) {
      return PolicyDetailPage(topic: initialTopic!);
    }
    return Scaffold(
        appBar: AppBar(title: const Text('服务与规则')),
        body: PageBody(children: [
          const SizedBox(height: 12),
          Text('把需要知道的事放在这里，不打扰刷题。',
              style: TextStyle(color: Colors.blueGrey.shade600)),
          const SizedBox(height: 14),
          box(Column(children: [
            _topicTile(context, PolicyTopic.agreement, Icons.article_outlined,
                '用户协议', '免费学习项目的使用范围'),
            const Divider(height: 1),
            _topicTile(context, PolicyTopic.privacy,
                Icons.admin_panel_settings_outlined, '隐私说明', '账号、学习记录与评论如何使用'),
            const Divider(height: 1),
            _topicTile(context, PolicyTopic.copyright, Icons.copyright_outlined,
                '版权投诉', '侵权内容通知与处理流程'),
            const Divider(height: 1),
            _topicTile(context, PolicyTopic.submission,
                Icons.upload_file_outlined, '题库投稿规则', '投稿前请先确认你拥有分享权限'),
            const Divider(height: 1),
            _topicTile(context, PolicyTopic.deletion,
                Icons.delete_outline_rounded, '数据删除申请', '复制申请模板后发送给作者'),
          ])),
          const SizedBox(height: 18),
          const Text('本说明用于帮助你安全使用 DentStudy，不替代适用法律规定。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
        ]));
  }

  Widget _topicTile(BuildContext context, PolicyTopic topic, IconData icon,
          String title, String subtitle) =>
      ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: teal),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PolicyDetailPage(topic: topic))));
}

class PolicyDetailPage extends StatelessWidget {
  final PolicyTopic topic;
  const PolicyDetailPage({super.key, required this.topic});

  @override
  Widget build(BuildContext context) {
    final content = _contentFor(topic);
    return Scaffold(
        appBar: AppBar(title: Text(content.title)),
        body: PageBody(children: [
          const SizedBox(height: 12),
          box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(content.intro,
                style: TextStyle(
                    color: ink, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 18),
            for (final section in content.sections) ...[
              Text(section.title,
                  style: TextStyle(
                      color: ink, fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 6),
              Text(section.body,
                  style: const TextStyle(height: 1.65, color: Colors.blueGrey)),
              const SizedBox(height: 18),
            ],
            if (content.template != null) ...[
              Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: teal.withAlpha(13),
                      borderRadius: BorderRadius.circular(14)),
                  child: SelectableText(content.template!,
                      style: const TextStyle(fontSize: 12, height: 1.55))),
              const SizedBox(height: 12),
              FilledButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: content.template!));
                    if (context.mounted) message(context, '邮件模板已复制');
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(content.copyLabel!)),
            ]
          ])),
          const SizedBox(height: 22),
          const Text('联系邮箱：dentstudy1126@aka.yeah.net',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
        ]));
  }
}

class _PolicyContent {
  final String title;
  final String intro;
  final List<_PolicySection> sections;
  final String? template;
  final String? copyLabel;
  const _PolicyContent(this.title, this.intro, this.sections,
      {this.template, this.copyLabel});
}

class _PolicySection {
  final String title;
  final String body;
  const _PolicySection(this.title, this.body);
}

_PolicyContent _contentFor(PolicyTopic topic) {
  const email = 'dentstudy1126@aka.yeah.net';
  switch (topic) {
    case PolicyTopic.agreement:
      return const _PolicyContent('用户协议', 'DentStudy 是一个个人维护的免费学习工具。', [
        _PolicySection('使用范围',
            '网站仅用于个人学习与复习，不提供诊疗、处方或考试通过承诺。题目解析和学习建议应结合正规教材、课程及专业人士意见核对。'),
        _PolicySection('你的责任',
            '请使用合法账号并妥善保管密码；不要发布侵犯他人著作权、肖像权、隐私权或其他权益的内容，也不要上传含个人病历、联系方式等敏感信息的材料。'),
        _PolicySection('内容处理',
            '对涉嫌违法、侵权或明显不适合公开的内容，DentStudy 可先行隐藏、限制使用或删除；必要时会配合处理合法有效的投诉。'),
      ]);
    case PolicyTopic.privacy:
      return const _PolicyContent('隐私说明', '只收集让学习、同步和交流正常运作所需的信息。', [
        _PolicySection('可能处理的信息',
            '注册邮箱、密码的安全校验信息、昵称、头像、院校、学习记录、评论，以及你主动提交的题库文件。访客的学习数据主要保留在当前设备。'),
        _PolicySection('用途与保存',
            '这些信息用于登录、跨设备同步、展示评论身份、处理反馈和维护服务。数据保存在中国大陆的服务环境及合理的备份中；不会出售个人信息，也不会用于广告画像。'),
        _PolicySection('你的选择',
            '你可以在“我的”修改昵称、头像和院校，并删除自己的评论。需要删除账号相关资料、评论、题库投稿或学习记录时，可使用本页的数据删除申请。'),
      ]);
    case PolicyTopic.copyright:
      return _PolicyContent(
          '版权投诉',
          '非商业用途不等于可以自由转载；权利人可直接通知处理。',
          const [
            _PolicySection('可投诉的内容',
                '包括未经授权的题目、解析、图片、教材片段、试卷或其他受保护内容。请尽量提供准确题目链接、题目 ID 或截图，方便定位。'),
            _PolicySection('处理方式',
                '收到材料后通常会在 24 小时内确认收到；核验期间可先临时隐藏相关内容。材料不足时会请你补充，处理结果会通过你留下的联系方式回复。'),
            _PolicySection('请提供',
                '你的姓名或机构名称、有效联系方式、权属说明及初步证明、涉嫌侵权内容的位置和处理请求。恶意或明显失实的通知可能需要承担相应责任。'),
          ],
          template:
              '收件人：$email\n主题：DentStudy 版权投诉\n\n权利人姓名/机构：\n联系方式：\n涉嫌侵权内容的位置（链接、题目 ID 或截图说明）：\n我主张的权利及初步证明：\n希望采取的处理措施：\n\n本人确认上述信息真实、准确。',
          copyLabel: '复制投诉邮件模板');
    case PolicyTopic.submission:
      return const _PolicyContent('题库投稿规则', '分享前先确认：这份资料确实可以由你分享。', [
        _PolicySection('可以投稿什么',
            '你原创、已取得明确授权，或依法可以传播的 JSON 格式学习资料。请尽量标注来源、年份、适用范围和审核状态，方便准确使用。'),
        _PolicySection(
            '不要投稿什么', '不要上传来源不明的题库、付费课程或教材的原文内容、受限制的考试资料、带有他人个人信息或医疗健康信息的文件。'),
        _PolicySection('投稿后的规则',
            '选择提交即表示你确认拥有必要的分享权限。内容如被举报、无法核验来源或不适合公开使用，可能被拒绝、隐藏或删除；本地导入的资料仍由你自行负责。'),
      ]);
    case PolicyTopic.deletion:
      final account = store.email.isEmpty ? '（请填写注册邮箱）' : store.email;
      return _PolicyContent(
          '数据删除申请',
          '需要删除服务器侧资料时，发邮件申请即可。',
          const [
            _PolicySection('可以申请删除',
                '账号资料、头像、昵称、院校、评论、题库投稿和学习记录。为避免误删，会先通过注册邮箱或其他合理方式核验身份。'),
            _PolicySection('处理前请知道',
                '收到申请后会先回复核验；删除请求不代表即时完成。为遵守法律义务、处理争议或维护备份安全而必须保留的最小信息，可能在合理期限后再清除。'),
            _PolicySection('本地数据', '访客记录和离线缓存可能仍在你的设备或浏览器中，需要你自行清除网站数据或卸载应用。'),
          ],
          template:
              '收件人：$email\n主题：DentStudy 数据删除申请\n\n注册邮箱：$account\n希望删除的内容（可多选）：账号资料 / 头像 / 评论 / 题库投稿 / 学习记录 / 账号\n需要定位的内容（如题目 ID、评论时间等）：\n补充说明：\n\n请从注册邮箱发送，以便核验。',
          copyLabel: '复制删除申请模板');
  }
}
