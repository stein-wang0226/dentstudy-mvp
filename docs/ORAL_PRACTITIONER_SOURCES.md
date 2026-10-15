# 口腔执业医师历年试题来源核验

核验日期：2026-10-15。当前新增历年真题 **0 道**，综合题库仍为 3520 道。
页面支持按考试方向、考试年份和试卷浏览，不代表已经取得历年真题内容。

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
