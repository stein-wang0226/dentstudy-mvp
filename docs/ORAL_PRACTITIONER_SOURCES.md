# 口腔执业医师历年试题来源核验

核验日期：2026-10-15。当前新增历年真题 **0 道**；用户随后同意导入开放数据练习题，本批增加 **130 道**，综合题库为 **3650 道**。
页面支持按考试方向、考试年份和试卷浏览，不代表已经取得历年真题内容。

## 开放数据分科导入（0.2.18）

来源为 [FreedomIntelligence/CMB](https://github.com/FreedomIntelligence/CMB)，[发布方数据集卡](https://huggingface.co/datasets/FreedomIntelligence/CMB)明确标注 Apache-2.0；仓库包含同名完整许可。没有使用限制为研究用途的 CMExam，也未复制商业题库。
许可原文与改动声明随网站发布在 `mobile/web/licenses/CMB-APACHE-2.0.txt`、`CMB-NOTICE.txt`，可由网站 `/licenses/` 对应路径访问。

固定上游修订 `6c8ece46097dae736c6805dd3b831e1a38c08971`，ZIP Git blob `c05ff2040d8257408aee77a774d41f29727401bf`。每题保存原始行号、原记录 SHA-256、来源链接、许可、学科映射及解析改动说明。
仅挑选 `医师考试 / 执业医师 / 口腔执业医师` 的单选记录；不混入助理医师、临床医师或职称考试。原数据没有可靠考试年份，全部 `year: null`、`sourceType: open_dataset`，不进入历年试题目录。

| 新增科目 | 题数 | 执医入口状态 |
| --- | ---: | --- |
| 口腔修复学 | 50 | 可练习 |
| 牙体牙髓病学 | 50 | 可练习 |
| 牙周病学 | 10 | 建设中，可看解析 |
| 口腔颌面外科学 | 10 | 合并原有 1200 题，可练习 |
| 口腔组织病理学 | 5 | 建设中，可看解析 |
| 口腔黏膜病学 | 5 | 建设中，可看解析 |

解析不是上游原解析：CMB 训练记录只有题目、选项与答案。本站逐题增加 AI 辅助解释，明确标成待专业医学审核，不补造审核人、教材页码或官方真题来源。新增 ID 使用 `cmb-train-<原始零起始行号>-v1`，现有 3520 道题及历史事件均不改写。

质量筛选排除了共享材料不完整、损坏字符、非口腔专科、过时治疗表述和明显疑似答案冲突的候选。举例：原始零起始行号 30294（光固化时机选项冲突）、30470（根尖病变急性发作判断）、33341（修复体抗力形选项冲突）、33783（全脱位牙再植时效表述）、45516（牙髓状态与治疗选择不符）均未收录；这些只是排除原因，不表示已经完成上游数据勘误。

一般知识交叉检查参考 [AAE 诊断术语](https://www.aae.org/specialty/wp-content/uploads/sites/2/2017/07/aaeconsensusconferencerecommendeddiagnosticterminology.pdf)、[ADA 龋病治疗说明](https://www.ada.org/about/press-releases/american-dental-association-releases-new-tooth-decay-treatment-guideline)、[ADA 修复材料](https://www.ada.org/resources/ada-library/oral-health-topics/materials-for-direct-restorations/)、[NIDCR 牙周病资料](https://www.nidcr.nih.gov/health-info/gum-disease)、[AAP 牙周分类](https://www.perio.org/research-science/2017-classification-of-periodontal-and-peri-implant-diseases-and-conditions/)。这些是知识核对资料，不是题目出处，也不代表逐题通过医学审核。临床处理以现行指南和专业判断为准。

### 可复现导入

分科 JSON：`question-bank/open-practice/`。它们是综合库的导出视图，不能把六份分库再加到总数上。
人工筛选索引、分类及补充解析：`data/curation/cmb_practice_annotations.json`。
脚本默认只检查，指定 `--apply` 才写入；拒绝覆盖内容不同的已有 ID 或分科文件，归一化题干去重，完整保留第五选项。

为减少下载非口腔资料，取官方 ZIP 中训练集条目开头的固定 6000001 字节（只解析完整 JSON 记录）：

```bash
curl -fL -H 'Accept: application/vnd.github.raw+json' \
  -H 'Range: bytes=1308925-7308925' \
  'https://api.github.com/repos/FreedomIntelligence/CMB/git/blobs/c05ff2040d8257408aee77a774d41f29727401bf?part=train-first6m' \
  -o /tmp/dentstudy-cmb-train-prefix.bin
python3 scripts/import_cmb_practice.py /tmp/dentstudy-cmb-train-prefix.bin
python3 scripts/import_cmb_practice.py /tmp/dentstudy-cmb-train-prefix.bin --apply
```

片段 SHA-256 必须为 `1f23527ce1bfb50942c8c59d9095a4071ae056e006c9c4ec26f16c340a053633`，否则停止。末尾不完整记录不导入。上线时前后端综合库必须同版本；字体需按新题库重新生成，避免新增牙位符号缺字。

## 搜索结果

| 来源 | 找到的内容 | 本次处理 |
| --- | --- | --- |
| [国家医学考试中心公告列表](https://www1.nmec.org.cn/Pages/ArticleList-4-0-0-1.html)及[声明转载](https://www.med66.com/yishizigekaoshi/kaoshishijian/li2608148637.shtml) | 2026-08-11 发布历年实测试题著作权声明，主张包含口腔类别的试题使用须取得书面授权 | 尚无可用于本站公开题库的授权文件，未复制试题 |
| [CMB](https://github.com/FreedomIntelligence/CMB) | 公开医学评测数据，含口腔执业医师分类；公开样例结构没有考试年份，多数集合不带完整解析 | 未作为按年份真题导入 |
| [CMExam](https://github.com/williamliujl/CMExam) | 有答案与解析的医学评测数据；项目标注研究用途，公开说明不足以确认每题的口腔执医考试年份 | 未作为按年份真题导入 |
| [LLM-Chinese-NMLE](https://github.com/zonghui0228/LLM-Chinese-NMLE) | 2017–2021 医师、药师、护士数据；公开说明不能确认所列医师卷是口腔类别 | 未混入口腔题库 |
| [银符试卷目录](https://www.yfzxmn.com/examTab_get.action?ex_type=&so_Id=48&sort=ex_Showtime&su_Id=11) | 列出多个年份，访问受机构授权范围限制，部分试卷只有部分解析 | 未绕过访问限制，未导入 |

## 后续资料的 JSON 约定

继续使用现有 DentStudy 题目结构，保留题干、原始选项（执医题常见 A–E 五选项）、答案、解析、题目 ID 和 `paperId`。不要为了套四选项格式删掉第五选项。
来源、年份与医学审核各自记录；教材引文已核验不等于真题年份已核验。

每题在原有字段之外需提供：

```json
{
  "modes": ["执医"],
  "year": 2024,
  "sourceType": "past_paper",
  "sourceUrl": "https://资料来源地址",
  "examProvenance": {
    "examName": "口腔执业医师",
    "yearVerified": true,
    "sourceVerified": true
  }
}
```

以上只是元数据示意，不是可导入题库，也不是授权证明。仅在已核验的资料上设置验证标志；
原始回忆资料使用 `recalled_paper`，页面显示“考生回忆题”。未核实考试年份的资料不会生成年度目录，
上传日期、题集出版年份不能代替考试年份。`reviewStatus`、`reviewer`、`reviewedAt` 仍表示医学审核，不能自动补成已审核。

具备可公开使用来源的完整 DentStudy JSON 可使用：

```bash
python3 scripts/split_exam_year_banks.py /path/to/supplied-bank.json --output /path/to/year-banks
python3 backend/bank.py validate /path/to/year-banks/oral_practitioner_2024.json
```

拆分命令先校验全部记录，再按年份输出独立 JSON；不抓取网络题目、不生成答案、不修改综合库。
可以通过“我的 → 导入题库”本地导入，或者再使用已有合并命令，保留现有 ID：

```bash
python3 backend/bank.py import /path/to/year-banks/oral_practitioner_2024.json --output mobile/assets/all_questions.json
```

正式站点发布前需要核实资料使用范围。套题内容到齐后应在同一发布中同步客户端和后端题库，避免评论、作答事件引用后端不认识的题目 ID。
