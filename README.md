# 齿间 DentStudy

口腔医学刷题 APP 的独立 MVP 源码。Flutter 客户端 + Python/SQLite 开发后端。名称为临时产品名，可替换。

**交付状态：后端已运行并通过 17 项测试；Dart 源文件经过语法解析检查，但未完成 Flutter 类型分析、测试执行或 Android/iOS 原生编译。当前没有 APK/IPA。** 当前机器无 Flutter/Android SDK、Xcode 开发工具；尝试获取 Flutter 的官方与镜像发行索引均失败，GitHub 连接超时。请勿将本源码当作已经过真机验收的发行版本。

## 已写入的功能

- 首页待复习任务、跨考试模式的旧题优先与新题解锁。
- 1、2、4、7、14 天复习阶梯；做错重置、蒙对回退、掌握晋级；同日/提前重做不晋级。
- 考研 / 本科期末 / 执医切换；章节、科目、考点关键词、院校、年份、题型、标签筛选。
- 普通练习、随机练习、收藏练习、限时套卷；客观题自动计分，主观题参考要点自评。
- A1/A2/A3/A4/B、简答、案例题数据模型与共用题干。
- 错题自动归集、手动移除；收藏；题目笔记；近 7 天练习量和科目正确率。
- 本机离线答题、题库下载；注册/登录、跨设备事件同步、重试去重与账号数据隔离。
- 本地通知排期代码：北京时间 20:00，最多预排未来 14 天；仍需真机验证权限、重启和系统省电行为。
- 题库校验与导入命令，包含正式内容审核字段、教材出处字段与不可变题目 ID。

## 仍需要的外部条件与后续开发

- 正式题库：目前只有 **16 道原创演示题**，没有真实院校/年份，不冒充历年真题。医学内容与教材出处未核验，正式库需要授权材料与专业审核。
- 原生工程：使用下面的 bootstrap 命令由 Flutter 生成 Android/iOS 包装工程，随后进行编译、模拟器和真机验收。应用标识暂为 `com.example.dentstudy`。
- 服务部署：提供的是本地开发 API，不是已开通的云服务。公网部署前见 `docs/DEPLOYMENT.md`。
- 远程推送：本地通知已写入，APNs/FCM/国内厂商通道、设备令牌、服务端推送任务尚未接入。
- 题库后台：本次提供 CLI 导入与审核校验，不含多人协作的图形化 CMS。
- 正式考务：未实现防作弊、服务端权威计时、主观题人工批改与考试中断恢复；模考属于学习练习功能。
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

将本目录作为 Git 仓库根目录时，`.github/workflows/check.yml` 可运行后端检查、Flutter 分析/测试以及 Android 调试包构建。本次未创建远程仓库，也未执行 GitHub Actions。

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

数据结构和接口见 [docs/API.md](docs/API.md)，排期细节见 [docs/SCHEDULER.md](docs/SCHEDULER.md)，上线差距见 [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)。
