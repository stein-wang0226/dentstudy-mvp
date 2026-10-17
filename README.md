# 齿间 DentStudy

齿间 DentStudy：中文、移动端优先的口腔医学学习应用。Flutter 客户端 + Python/SQLite 开发后端。

当前可运行本地 Flutter Web；本机 Flutter SDK 位于 `tools/flutter`，页面默认预览地址为 `http://127.0.0.1:8080`。Python API 默认在 8787 端口。Web 运行与静态检查不代表 Android/iOS 编译、签名或真机验收完成。阶段验证结果见 `docs/LEARNING_LOOP_VERIFICATION.md`；`docs/VERIFICATION.md` 保留早期历史记录。

## 当前题库与统计口径

- 默认客户端与后端读取 `mobile/assets/all_questions.json`：3650 个唯一题目 ID，包含 3504 道原有资料整理题、130 道 CMB 开放数据练习题、16 道演示题。原有 3520 条记录逐条保留。
- CMB 新增按科目分为：口腔修复学 50、牙体牙髓病学 50、牙周病学 10、口腔颌面外科学 10、口腔组织病理学 5、口腔黏膜病学 5。题干、五个选项和答案保留上游版本；解析为 DentStudy AI 辅助补充，逐题标注，全部保持 `draft`，不称已审核或历年真题。
- 当前考试方向下达到 50 道非演示题的学科才开放常规练习。考研可练仍为 3504 题；执医收录 1330 道非演示题，其中可练 1310 题（口外 1210、修复 50、牙体牙髓 50）。其他 20 题所在科目显示建设中，可查看已收录解析，不开放常规练习。本科期末目前只有演示题。达到门槛不表示科目覆盖完整。
- 三个分库内容已经合并在综合库中，不再重复相加。`questions.json` 的 1120 题包括 16 道跨学科演示题，并非纯修复学题量。
- 根目录 `question-bank/` 原有 3649 题生成草稿、`review/` 的 1200 题审阅稿不是客户端运行数据源。本次新增 `question-bank/open-practice/` 六份分科 JSON，它们已经合并在综合库，不可重复计数；原有草稿未改动。
- 更新后的离线缓存会在下次启动加载。历史记录引用的题目继续保留。
- 题库首页分为考研、本科期末、执医三类；执医提供“历年试题 → 年份 → 试卷 → 题目”入口。目前新增历年真题 0 道，待取得可公开使用、年份明确的资料；来源核验与按年 JSON 拆分方法见 [来源记录](docs/ORAL_PRACTITIONER_SOURCES.md)。

## 学习闭环与本机记录

今日计划先安排到期复习，再安排新题，每轮最多 20 道复习、10 道新题，同时遵守现有每日目标和额度。每日计划默认逐题深度模式；自定义练习可选学科、章节、10/20/50/100 题、随机与三种模式。

学习进度按不同题目统计；正确率按客观题作答次数统计；主观题不自动计入正确率。疑问题复用最近掌握度 `guessed`。学习用时仅从新版开始按本机会话记录，后台暂停，旧记录无耗时不补算；预计时间按每题 1.5 分钟估算。

答案、评级、进度、原模考截止时间和已提交题目保存为账号隔离的本机断点；本机会话元数据与用时暂不跨设备同步。答题、收藏、笔记、移出错题仍使用原事件与同步协议；排期仍由原 reducer 计算。

## 已写入的功能

- 首页待复习任务、跨考试模式的旧题优先与新题解锁。
- 1、2、4、7、14 天复习阶梯；做错重置、蒙对回退、掌握晋级；同日/提前重做不晋级。
- 考研 / 本科期末 / 执医切换；章节、科目、考点关键词、院校、年份、题型、标签筛选。
- 普通练习、随机练习、收藏练习、限时套卷；客观题自动计分，主观题参考要点自评。
- A1/A2/A3/A4/B、简答、案例题数据模型与共用题干。
- 错题自动归集、手动移除；收藏；题目笔记；近 7 天练习量、周统计与薄弱章节建议。
- 本机离线答题、题库下载；注册/登录、跨设备事件同步、重试去重与账号数据隔离。
- 用户可在“我的”选择符合模板的 JSON 题库，本地导入后立即练习；登录用户可将原文件投稿到作者私有审核箱。投稿文件不公开，上传前须确认拥有分享权限。
- Word/TXT 导入同时提供本地格式整理与 AI 智能整理：AI 仅在用户点击后把本次文字发送至阿里云百炼，服务端不保存原文；只提取原文已有的题干、选项和明确答案，不补题、不猜答案。每账号每天最多 3 次、单次最多 6 万字，整理结果仍是待医学审核的本地导入题库。
- “小齿”是右下角可拖动的口腔备考聊天搭子，带待机、互动、思考、说话、感谢五种状态动画；可在“我的 → 学习设置”关闭。聊天为临时会话，不保存聊天内容，不会替用户操作网站、下载内容或协助侵权资料；服务端仅以匿名额度计数限制频率与预算。
- 题库关键词搜索：题干、选项、解析、考点与题目编号；支持学科/章节范围、多关键词和不区分英文大小写，“咬合”可搜到“𬌗”。
- 章节解析连续浏览、章末下一章入口；错题/收藏/搜索结果内连续切题。解析阅读位置按账号和方向保存在本机，不产生作答事件。
- 本地精简中文字体覆盖当前题库与界面字符，包含“𬌗”；主题与版本更新时间可在“我的”查看。
- 本地通知排期代码：北京时间 20:00，最多预排未来 14 天；仍需真机验证权限、重启和系统省电行为。
- 题库校验与导入命令，包含正式内容审核字段、教材出处字段与不可变题目 ID。

## 仍需要的外部条件与后续开发

- 正式题库：当前资料整理题和演示题均未通过正式内容审核；真实审核状态必须以题目字段为准。
- 原生工程：本机已有 Android/iOS 包装工程；缺失时可使用下面的 bootstrap 命令生成。本轮未进行原生编译、签名或真机验收。应用标识暂为 `com.example.dentstudy`。
- 服务部署：网站与同源 API 已部署至 https://dentstudy.uno，使用阿里云 ECS、Nginx 和 HTTPS；当前手动发布，推送 GitHub 不会自动更新网站。实际部署见 `docs/DEPLOY_ALIYUN.md`。项目当前不提供支付或 VIP 功能；邮件验证码也尚未开通。
- 远程推送：本地通知已写入，APNs/FCM/国内厂商通道、设备令牌、服务端推送任务尚未接入。
- 题库后台：本次提供 CLI 导入与审核校验，不含多人协作的图形化 CMS。
- 正式考务：未实现防作弊、服务端权威计时、主观题人工批改与跨设备统一的考试中断恢复；本机可保留作答和原截止时间，模考仍属于学习练习功能。
- 大规模题库：当前用完整事件同步与 SharedPreferences，适合 MVP；正式规模需分页增量同步、本地 SQLite 与服务端 PostgreSQL。

## 启动后端

依赖 Python 3.10+，无第三方运行时依赖。

```bash
cd backend
python3 server.py
```

默认只监听 `127.0.0.1:8787`，首次启动生成本地 SQLite 数据库。Android 模拟器通过 `http://10.0.2.2:8787` 访问；iOS 模拟器使用 `http://localhost:8787`。真机调试需在受信网络运行 `python3 server.py --host 0.0.0.0`，APP 中填写电脑的局域网地址；iOS 真机建议使用受信任的 HTTPS 开发地址。

```bash
cd backend
python3 -m unittest discover -s tests -v
```

## 生成并运行 Flutter 客户端

先准备 Flutter 3.35+、Android SDK/JDK 17。iOS 另需 macOS、Xcode 与 CocoaPods。参考 [Flutter 安装](https://docs.flutter.dev/install)、[iOS 环境配置](https://docs.flutter.dev/platform-integration/ios/setup)。

```bash
cd mobile
bash bootstrap.sh
dart format lib test
flutter analyze
flutter test
flutter run --dart-define=API_URL=http://10.0.2.2:8787
```

`bootstrap.sh` 会保留 `lib/`、`test/`、`pubspec.yaml`，生成平台项目并设置通知权限和调试网络。若 `python3` 不是可用解释器，可用 `PYTHON_BIN=/path/to/python3 bash bootstrap.sh`。

模拟器或设备必须实际启动并被 `flutter devices` 检出。当前 API 地址可在“我的 → 配置后端地址”修改；登录后换服务器前需先退出账号。首次答题可完全离线，登录不是先决条件。

```bash
# Android 调试安装包（尚未在本环境执行）
flutter build apk --debug
# Android 发行包：先配置自己的应用 ID、签名与 HTTPS API
flutter build appbundle --release --dart-define=API_URL=https://your-api.example.com
# iOS：需开发者签名与配置好的 Xcode
flutter build ipa --release --dart-define=API_URL=https://your-api.example.com
```

Git 远程仓库为 `stein-wang0226/dentstudy-mvp`。`.github/workflows/check.yml` 定义后端检查、Flutter 分析/测试以及 Android 调试包构建；当前本地改版不代表已推送或远程 CI 已通过。

## 演示验收路径

1. 打开“今日”，初始无历史记录，因此新题开放。
2. 开始学习新题，选择答案，点击查看解析，再标记“做错 / 蒙对 / 完全掌握”。答错时只能标记做错。
3. 返回首页或打开“题本”，检查错题/收藏；进入解析页保存笔记。
4. 次日北京时间 00:00 后，首页出现到期题；未完成时不能从其他学习模式绕过门槛练新题。
5. 在“我的”注册并同步。访客记录保留在独立空间，按“导入本机访客记录”才合并到该账号。
6. 第二台设备使用相同 API 与账号登录，验证笔记、收藏、答题记录和排期。
7. 开启复习提醒后，用真机验证通知授权、进入后台、设备重启和当天完成后的重排。

## 导入题库

```bash
python3 backend/bank.py validate mobile/assets/questions.json
# 正式库必须通过完整审核字段校验；演示库会被此模式拒绝
python3 backend/bank.py validate /path/to/reviewed-bank.json --production
python3 backend/bank.py import /path/to/reviewed-bank.json --production
```

导入采用追加合并；不能用同一个题目 ID 改写历史内容。修订答案/题干时分配新版本 ID。正式发布前应新建不含演示题的发布库或使用 `--output /path/to/new-bank.json` 输出独立题库，再配置服务端 `DENTSTUDY_BANK` 路径。不要删除已有用户历史所引用的题目。

Word/TXT 的“AI 智能整理”不是医学审校或题目生成器：它会先要求题库名称、科目、章节和学习方向，再仅结构化用户明确提供答案的客观题。原文字仅在本次请求中交给阿里云百炼，不写入 DentStudy 数据库或日志；请勿上传隐私、受限或无权使用的资料。服务端默认使用 `qwen3.7-flash` 非思考模式，并设置每账号每日 3 次、每月 ¥20 等值的服务器总预算保护；免费试用额度耗尽或预算到顶时会停止服务而非继续扣费。

数据结构和接口见 [docs/API.md](docs/API.md)，排期细节见 [docs/SCHEDULER.md](docs/SCHEDULER.md)，上线差距见 [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)。
