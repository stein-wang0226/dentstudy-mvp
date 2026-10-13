"""Build local Noto subsets from bank/UI text; requires fonttools only at build time.

Download NotoSansCJKsc-{Regular,Bold}.otf from the official notofonts/noto-cjk
Sans/OTF/SimplifiedChinese directory and NotoSans-Regular.ttf from
notofonts/noto-fonts/hinted/ttf/NotoSans plus NotoSansMath-Regular.ttf from the
NotoSansMath directory into .tools/font-build before running.
"""
import json
import unicodedata
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / ".tools/font-build"
OUTPUT = ROOT / "mobile/assets/fonts"


def strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from strings(item)


def main():
    text = "".join(strings(json.loads(
        (ROOT / "mobile/assets/all_questions.json").read_text(encoding="utf-8"))))
    text += "".join(path.read_text(encoding="utf-8")
                    for path in (ROOT / "mobile/lib").rglob("*.dart"))
    requested = {ord(c) for c in text if not unicodedata.category(c).startswith("C")}
    requested.update(range(0x20, 0x7f))
    fallback_sources = {
        'DentStudySymbols': TTFont(SOURCE / 'NotoSans-Regular.ttf'),
        'DentStudyMath': TTFont(SOURCE / 'NotoSansMath-Regular.ttf'),
    }
    symbol_coverage = set().union(*(set(f.getBestCmap()) for f in fallback_sources.values()))
    symbol_needed = set()
    for weight in ("Regular", "Bold"):
        font = TTFont(SOURCE / f"NotoSansCJKsc-{weight}.otf")
        covered = set(font.getBestCmap())
        missing = requested - covered
        print(f"{weight}: {len(requested)} requested; "
              f"missing: {''.join(chr(c) for c in sorted(missing))!r}")
        assert 0x2c317 in covered, "Source font must cover 𬌗"
        assert missing <= symbol_coverage, "Current bank/UI glyphs must all be covered"
        symbol_needed.update(missing)
        options = subset.Options()
        options.name_IDs = [0, 1, 2, 3, 4, 5, 6, 13, 14]
        options.name_legacy = True
        options.name_languages = [0x409]
        builder = subset.Subsetter(options=options)
        builder.populate(unicodes=requested & covered)
        builder.subset(font)
        names = {
            1: "DentStudy Sans", 2: weight,
            3: f"DentStudySans-{weight}-2.004-subset",
            4: f"DentStudy Sans {weight}", 6: f"DentStudySans-{weight}",
        }
        for record in font["name"].names:
            if record.nameID in names:
                record.string = names[record.nameID].encode(record.getEncoding())
        if "CFF " in font:
            cff = font["CFF "].cff
            cff.fontNames = [f"DentStudySans-{weight}"]
            cff.topDictIndex[0].FamilyName = "DentStudy Sans"
            cff.topDictIndex[0].FullName = f"DentStudy Sans {weight}"
        target = OUTPUT / f"DentStudySans-{weight}.otf"
        font.save(target)
        result = TTFont(target)
        assert requested <= set(result.getBestCmap()) | symbol_coverage
        print(f"Saved {target.name}: {target.stat().st_size:,} bytes; "
              f"copyright: {result['name'].getDebugName(0)}")
    for family, symbols in fallback_sources.items():
        needed = symbol_needed & set(symbols.getBestCmap())
        options = subset.Options()
        options.name_IDs = [0, 1, 2, 3, 4, 5, 6, 13, 14]
        builder = subset.Subsetter(options=options)
        builder.populate(unicodes=needed)
        builder.subset(symbols)
        for record in symbols['name'].names:
            if record.nameID in (1, 3, 4, 6):
                record.string = family.encode(record.getEncoding())
        target = OUTPUT / f'{family}-Regular.ttf'
        symbols.save(target)
        assert needed <= set(TTFont(target).getBestCmap())
        print(f'{family}: {len(needed)} glyphs, {target.stat().st_size:,} bytes')


if __name__ == "__main__":
    main()
