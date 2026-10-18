"""Convert a chapter-oriented oral-maxillofacial postgraduate JSON bank.

The source format is deliberately kept outside the app. This converter only
adapts its structure to DentStudy's public-bank schema: question wording,
options, answers, chapters, explanations and source notes are preserved.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "mobile" / "assets" / "all_questions.json"
SUBJECT = "口腔颌面外科学"
MODE = "考研"
SOURCE_BOOK = "《口外终版》讲义"
WARNING = "题目依据用户提供的讲义资料整理，当前未完成平台医学审核；请结合教材、课程与专业教师意见核对。"
LICENSE = "用户提供学习资料；仅供学习使用，公开传播前须核实著作权授权与医学审核。"
OPTION_PREFIX = re.compile(r"^\s*([A-D])\s*[.．、]\s*(.*)$")


def _text(value: Any, fallback: str = "") -> str:
    return value.strip() if isinstance(value, str) and value.strip() else fallback


def _options(raw: Any, question_id: str) -> dict[str, str]:
    if not isinstance(raw, list) or len(raw) != 4:
        raise ValueError(f"{question_id}: 单选题必须有 4 个选项")
    options: dict[str, str] = {}
    for index, item in enumerate(raw):
        value = _text(item)
        match = OPTION_PREFIX.match(value)
        letter = match.group(1) if match else "ABCD"[index]
        label = match.group(2).strip() if match else value
        if not label or letter in options:
            raise ValueError(f"{question_id}: 选项格式不正确")
        options[letter] = label
    if set(options) != set("ABCD"):
        raise ValueError(f"{question_id}: 选项必须完整包含 A、B、C、D")
    return options


def _source_metadata(source: Any, chapter: str, chapter_index: int) -> dict[str, Any]:
    raw = source if isinstance(source, dict) else {}
    if raw.get("type") == "real_exam":
        school = _text(raw.get("school"), "院校待核验")
        year = raw.get("year") if isinstance(raw.get("year"), int) else None
        note = _text(raw.get("note"), "来源待核验")
        title = f"{school}{f'{year}年' if year else ''}口腔颌面外科考研题（{note}）"
        paper_name = f"{school}{f'{year}年' if year else ''}口腔颌面外科考研题（来源待核验）"
        return {
            "reference": title,
            "citation": {
                "verified": False,
                "publisher": None,
                "title": title,
                "edition": None,
                "chapter": chapter,
                "page": None,
                "sourceUrl": raw.get("url"),
                "note": note,
            },
            "tags": ["考研", "口腔颌面外科", "回忆题", "来源待核验"],
            "sourceType": "recalled_paper",
            "school": school,
            "year": year,
            "sourceUrl": raw.get("url"),
            "paperId": f"omfs-recalled-{school}-{year or 'unknown'}",
            "paperName": paper_name,
            "durationMinutes": 180,
        }
    return {
        "reference": f"{SOURCE_BOOK} · {chapter}",
        "citation": {
            "verified": False,
            "publisher": None,
            "title": SOURCE_BOOK,
            "edition": None,
            "chapter": chapter,
            "page": None,
        },
        "tags": ["考研", "口腔颌面外科", "资料整理", "待医学审核"],
        "sourceType": "user_material",
        "school": None,
        "year": None,
        "sourceUrl": None,
        "paperId": f"omfs-kaoyan-chapter-{chapter_index:02d}",
        "paperName": f"口腔颌面外科考研资料整理 · {chapter}",
        "durationMinutes": 90,
    }


def convert(payload: dict[str, Any]) -> list[dict[str, Any]]:
    chapters = payload.get("chapters")
    if not isinstance(chapters, list) or not chapters:
        raise ValueError("源文件必须包含非空 chapters 数组")
    questions: list[dict[str, Any]] = []
    ids: set[str] = set()
    order = 0
    for chapter_entry in chapters:
        if not isinstance(chapter_entry, dict):
            raise ValueError("章节必须是对象")
        chapter = _text(chapter_entry.get("name"))
        chapter_index = chapter_entry.get("index")
        if not chapter or not isinstance(chapter_index, int):
            raise ValueError("章节缺少 name 或 index")
        raw_questions = chapter_entry.get("questions")
        if not isinstance(raw_questions, list) or not raw_questions:
            raise ValueError(f"{chapter}: 缺少题目")
        for raw in raw_questions:
            if not isinstance(raw, dict):
                raise ValueError(f"{chapter}: 题目必须是对象")
            question_id = _text(raw.get("id"))
            if not question_id or question_id in ids:
                raise ValueError(f"题目 ID 为空或重复：{question_id or '（空）'}")
            ids.add(question_id)
            order += 1
            section = _text(raw.get("section"), "未分类小节")
            knowledge_point = _text(raw.get("knowledge_point"))
            source = _source_metadata(raw.get("source"), chapter, chapter_index)
            source_type = _text(raw.get("type"), "single_choice")
            if source_type == "single_choice":
                options = _options(raw.get("options"), question_id)
                answer = _text(raw.get("answer"))
                if answer not in options:
                    raise ValueError(f"{question_id}: 答案不在选项中")
                question_type = "A1"
                rubric = None
            elif source_type == "term_explain":
                options = {}
                answer = None
                question_type = "简答题"
                rubric = _text(raw.get("answer"))
                if not rubric:
                    raise ValueError(f"{question_id}: 简答题缺少参考要点")
            else:
                raise ValueError(f"{question_id}: 不支持的源题型 {source_type}")
            questions.append({
                "id": question_id,
                "subject": SUBJECT,
                "chapter": chapter,
                "type": question_type,
                "stem": _text(raw.get("question")),
                "options": options,
                "answer": answer,
                "rubric": rubric,
                "explanation": _text(raw.get("explanation")),
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


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="章节式口腔颌面外科 JSON")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    payload = json.loads(args.source.read_text(encoding="utf-8-sig"))
    questions = convert(payload)
    bank = {
        "version": 1,
        "name": "考研 · 口腔颌面外科题库",
        "isDemo": False,
        "sourceDocument": args.source.name,
        "sourceNote": "依据用户提供的《口外终版》讲义资料整理：2,094 道资料整理单选题与 16 道来源待核验的回忆题/简答题。未完成平台医学审核，不等同于正式真题库。",
        "questions": questions,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(bank, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"已生成 {args.output}：{len(questions)} 道题，{len({q['chapter'] for q in questions})} 个章节")


if __name__ == "__main__":
    main()
