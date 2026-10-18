"""Merge a chapter-organized prosthodontics postgraduate bank into DentStudy.

The input stays outside the repository.  This importer validates the supplied
JSON, preserves its wording/options/answers/chapters, gives its question IDs a
stable ``PROS-`` namespace, and truthfully keeps lecture, mock and recalled
question provenance distinct.  It never rewrites existing public questions.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BANK = ROOT / "mobile" / "assets" / "all_questions.json"
SUBJECT = "口腔修复学"
MODE = "考研"
SOURCE_BOOK = "《修复学 终版》讲义"
WARNING = "题目依据用户提供的讲义资料整理，当前未完成平台医学审核；请结合教材、课程与专业教师意见核对。"
LICENSE = "用户提供学习资料；仅供学习使用，公开传播前须核实著作权授权与医学审核。"
OPTION_PREFIX = re.compile(r"^\s*([A-D])\s*[.．、]\s*(.*)$")


def text(value: Any, fallback: str = "") -> str:
    return value.strip() if isinstance(value, str) and value.strip() else fallback


def options(raw: Any, source_id: str) -> dict[str, str]:
    if not isinstance(raw, list) or len(raw) != 4:
        raise ValueError(f"{source_id}: 单选题必须有 4 个选项")
    result: dict[str, str] = {}
    for index, item in enumerate(raw):
        value = text(item)
        match = OPTION_PREFIX.match(value)
        letter = match.group(1) if match else "ABCD"[index]
        label = match.group(2).strip() if match else value
        if not label or letter in result:
            raise ValueError(f"{source_id}: 选项格式不正确")
        result[letter] = label
    if set(result) != set("ABCD"):
        raise ValueError(f"{source_id}: 选项必须完整包含 A、B、C、D")
    return result


def source_metadata(raw: Any, chapter: str, chapter_index: int) -> dict[str, Any]:
    source = raw if isinstance(raw, dict) else {}
    source_type = text(source.get("type"), "original")
    if source_type == "real_exam":
        school = text(source.get("school"), "院校待核验")
        year = source.get("year") if isinstance(source.get("year"), int) else None
        note = text(source.get("note"), "考生回忆题，来源待核验")
        title = f"{school}{f'{year}年' if year else ''}口腔修复学考生回忆题"
        return {
            "reference": f"{title}（{note}）",
            "citation": {
                "verified": False,
                "publisher": None,
                "title": title,
                "edition": None,
                "chapter": chapter,
                "page": None,
                "sourceUrl": source.get("url"),
                "note": note,
            },
            "tags": ["考研", "口腔修复学", "考生回忆题", "来源待核验"],
            "sourceType": "recalled_paper",
            "school": school,
            "year": year,
            "sourceUrl": source.get("url"),
            "paperId": f"prostho-recalled-{school}-{year or 'unknown'}",
            "paperName": f"{title}（来源待核验）",
            "durationMinutes": 180,
        }
    if source_type == "mock":
        return {
            "reference": f"{SOURCE_BOOK} · {chapter} · 模拟练习",
            "citation": {
                "verified": False,
                "publisher": None,
                "title": SOURCE_BOOK,
                "edition": None,
                "chapter": chapter,
                "page": None,
                "note": "原资料标注为模拟题，非历年真题。",
            },
            "tags": ["考研", "口腔修复学", "模拟题", "待医学审核"],
            "sourceType": "mock",
            "school": None,
            "year": None,
            "sourceUrl": None,
            "paperId": f"prostho-mock-chapter-{chapter_index:02d}",
            "paperName": f"口腔修复学模拟练习 · {chapter}",
            "durationMinutes": 90,
        }
    if source_type != "original":
        raise ValueError(f"{chapter}: 不支持的来源类型 {source_type}")
    return {
        "reference": f"{SOURCE_BOOK} · {chapter}",
        "citation": {
            "verified": False,
            "publisher": None,
            "title": SOURCE_BOOK,
            "edition": None,
            "chapter": chapter,
            "page": None,
            "note": "用户提供讲义资料整理，待医学审核。",
        },
        "tags": ["考研", "口腔修复学", "资料整理", "待医学审核"],
        "sourceType": "user_material",
        "school": None,
        "year": None,
        "sourceUrl": None,
        "paperId": f"prostho-kaoyan-chapter-{chapter_index:02d}",
        "paperName": f"口腔修复学考研资料整理 · {chapter}",
        "durationMinutes": 90,
    }


def convert(payload: dict[str, Any]) -> list[dict[str, Any]]:
    chapters = payload.get("chapters")
    if not isinstance(chapters, list) or not chapters:
        raise ValueError("源文件必须包含非空 chapters 数组")
    questions: list[dict[str, Any]] = []
    source_ids: set[str] = set()
    order = 0
    for chapter_entry in chapters:
        if not isinstance(chapter_entry, dict):
            raise ValueError("章节必须是对象")
        chapter = text(chapter_entry.get("name"))
        chapter_index = chapter_entry.get("index")
        if not chapter or not isinstance(chapter_index, int):
            raise ValueError("章节缺少 name 或 index")
        raw_questions = chapter_entry.get("questions")
        if not isinstance(raw_questions, list) or not raw_questions:
            raise ValueError(f"{chapter}: 缺少题目")
        for raw in raw_questions:
            if not isinstance(raw, dict):
                raise ValueError(f"{chapter}: 题目必须是对象")
            source_id = text(raw.get("id"))
            if not source_id or source_id in source_ids:
                raise ValueError(f"题目 ID 为空或重复：{source_id or '（空）'}")
            source_ids.add(source_id)
            if text(raw.get("chapter")) != chapter:
                raise ValueError(f"{source_id}: 题目章节与所属章节不一致")
            stem = text(raw.get("question"))
            explanation = text(raw.get("explanation"))
            section = text(raw.get("section"), "未分类小节")
            knowledge_point = text(raw.get("knowledge_point"))
            if not stem or not explanation:
                raise ValueError(f"{source_id}: 题干或解析为空")
            source = source_metadata(raw.get("source"), chapter, chapter_index)
            raw_type = text(raw.get("type"), "single_choice")
            if raw_type == "single_choice":
                question_options = options(raw.get("options"), source_id)
                answer = text(raw.get("answer"))
                if answer not in question_options:
                    raise ValueError(f"{source_id}: 答案不在选项中")
                question_type, rubric = "A1", None
            elif raw_type == "term_explain":
                answer, question_options, question_type = None, {}, "简答题"
                rubric = text(raw.get("answer"))
                if not rubric:
                    raise ValueError(f"{source_id}: 简答题缺少参考要点")
            else:
                raise ValueError(f"{source_id}: 不支持的题型 {raw_type}")
            order += 1
            questions.append({
                "id": f"PROS-{source_id}",
                "subject": SUBJECT,
                "chapter": chapter,
                "type": question_type,
                "stem": stem,
                "options": question_options,
                "answer": answer,
                "rubric": rubric,
                "explanation": explanation,
                "warning": WARNING,
                "reference": source["reference"],
                "citation": source["citation"],
                "tags": source["tags"],
                "topics": [section, *([knowledge_point] if knowledge_point else [])],
                "modes": [MODE],
                "school": source["school"],
                "year": source["year"],
                "paperId": source["paperId"],
                "paperName": source["paperName"],
                "durationMinutes": source["durationMinutes"],
                "order": order,
                "points": 1,
                "isDemo": False,
                "reviewStatus": "draft",
                "sourceType": source["sourceType"],
                "sourceUrl": source["sourceUrl"],
                "license": LICENSE,
                "sourceChapter": chapter,
                "sourceSection": section,
            })
    declared = payload.get("meta", {}).get("total_questions")
    if isinstance(declared, int) and declared != len(questions):
        raise ValueError(f"题量与 meta 不一致：声明 {declared}，实际 {len(questions)}")
    return questions


def merge(base: dict[str, Any], imported: list[dict[str, Any]]) -> tuple[dict[str, Any], int]:
    if not isinstance(base.get("questions"), list):
        raise ValueError("现有题库必须包含 questions 数组")
    merged = [dict(question) for question in base["questions"]]
    by_id = {question.get("id"): question for question in merged}
    if len(by_id) != len(merged) or None in by_id:
        raise ValueError("现有题库存在空或重复 ID，拒绝导入")
    added = 0
    for question in imported:
        existing = by_id.get(question["id"])
        if existing is None:
            merged.append(question)
            by_id[question["id"]] = question
            added += 1
        elif existing != question:
            raise ValueError(f"题目 {question['id']} 已存在但内容不同，拒绝改写历史题目")
    result = dict(base)
    result.update({
        "version": 1,
        "name": "考研 · 口腔颌面外科与修复学题库",
        "isDemo": False,
        "sourceDocument": "口腔颌面外科考研题库.json；口腔修复学考研题库.json",
        "sourceNote": "共 4,210 道考研练习题：口腔颌面外科学 2,110 道（2,094 道资料整理题、16 道来源待核验回忆题/简答题）；口腔修复学 2,100 道（1,574 道资料整理题、525 道模拟练习题、1 道来源待核验回忆题）。所有题目均待医学审核，不等同于已审核真题库。",
        "questions": merged,
    })
    return result, added


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="章节式口腔修复学考研 JSON")
    parser.add_argument("--base", type=Path, default=DEFAULT_BANK)
    parser.add_argument("--output", type=Path, default=DEFAULT_BANK)
    args = parser.parse_args()
    payload = json.loads(args.source.read_text(encoding="utf-8-sig"))
    base = json.loads(args.base.read_text(encoding="utf-8"))
    imported = convert(payload)
    bank, added = merge(base, imported)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(bank, ensure_ascii=False, indent=2) + "\n",
                           encoding="utf-8")
    print(f"已合并 {added} 道题至 {args.output}：共 {len(bank['questions'])} 道题，"
          f"{len({q['chapter'] for q in bank['questions']})} 个章节")


if __name__ == "__main__":
    main()
