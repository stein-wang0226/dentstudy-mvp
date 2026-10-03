"""Convert the reviewed kouwai JSON into DentStudy's validated bank schema and merge it."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVIEW = ROOT / "review" / "kouwai-1200-待审阅"
ASSETS = ROOT / "mobile" / "assets"
SOURCE_TITLE = "kouwai.doc"


def load_review_questions():
    manifest = json.loads((REVIEW / "manifest.json").read_text())
    questions = []
    for entry in manifest["chapters"]:
        payload = json.loads((REVIEW / entry["file"]).read_text())
        questions.extend(payload["questions"])
    if len(questions) != 1200:
        raise ValueError(f"审阅题库应为 1200 题，实际为 {len(questions)}")
    return questions


def convert(questions):
    converted = []
    for index, question in enumerate(questions, 1):
        answer = question["answer"]
        options = {letter: question["options"][i] for i, letter in enumerate("ABCD")}
        converted.append({
            "id": f"DS-OMFS-{index:05d}-v1",
            "subject": "口腔颌面外科学",
            "chapter": question["chapter"],
            "type": "A1",
            "stem": question["stem"],
            "options": options,
            "answer": answer,
            "explanation": question["explanation"],
            "warning": "题目依据用户提供讲义整理，供考研和执医复习；使用前建议结合最新版教材核对。",
            "topics": [question.get("knowledgePoint", question["chapter"])],
            "tags": ["资料改编", "口外", "待医学审核"],
            "modes": ["考研", "执医"],
            "school": None,
            "year": None,
            "paperId": "oral-maxillofacial-surgery-kouwai-draft-v1",
            "paperName": "口腔颌面外科考研与执医题库（资料整理稿）",
            "durationMinutes": 180,
            "order": index,
            "points": 1,
            "reference": f"{SOURCE_TITLE} · {question['chapter']} · {question['id']}",
            "citation": {
                "publisher": None,
                "title": SOURCE_TITLE,
                "edition": None,
                "chapter": question["chapter"],
                "page": None,
                "verified": False,
                "sourceId": question["id"],
                "excerpt": question["explanation"].removeprefix("讲义要点："),
            },
            "reviewStatus": "draft",
            "isDemo": False,
            "sourceType": "user_material",
            "license": "用户提供资料，待专业审核",
            "rubric": None,
        })
    return converted


def main():
    new_questions = convert(load_review_questions())
    bank = {
        "version": 1,
        "name": "口腔颌面外科",
        "isDemo": False,
        "sourceDocument": SOURCE_TITLE,
        "sourceNote": "依据用户提供的 kouwai.doc 整理；为学习资料题库，需结合教材进一步医学审核。",
        "questions": new_questions,
    }
    standalone = ASSETS / "oral_maxillofacial_surgery_questions.json"
    standalone.write_text(json.dumps(bank, ensure_ascii=False, indent=2) + "\n")

    combined_path = ASSETS / "all_questions.json"
    combined = json.loads(combined_path.read_text())
    existing = {question["id"] for question in combined["questions"]}
    duplicate = existing.intersection(question["id"] for question in new_questions)
    if duplicate:
        raise ValueError(f"发现重复题目 ID：{sorted(duplicate)[:3]}")
    combined["name"] = "齿间综合题库（修复学、牙周病学与口腔颌面外科）"
    combined["isDemo"] = False
    combined["sourceNote"] = "综合题库：保留现有修复学与牙周病学题库，并加入口腔颌面外科资料整理稿。"
    combined["questions"].extend(new_questions)
    combined_path.write_text(json.dumps(combined, ensure_ascii=False, indent=2) + "\n")
    print(f"已生成独立题库：{standalone.name}，{len(new_questions)} 题")
    print(f"已更新综合题库：{len(combined['questions'])} 题")


if __name__ == "__main__":
    main()
