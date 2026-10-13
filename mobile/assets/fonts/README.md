# DentStudy 字体

`DentStudySans-Regular.otf` 和 `DentStudySans-Bold.otf` 是 Noto Sans CJK SC
2.004 的精简版本，保留综合题库与 Flutter 界面实际使用的字符（包含 U+2C317
“𬌗”），修改字体名称为 DentStudy Sans。采用 SIL Open Font License 1.1，
许可见 `OFL.txt`；原版权声明保留在字体 name 表中。

官方来源：https://github.com/notofonts/noto-cjk/tree/main/Sans/OTF/SimplifiedChinese

更新题库或界面后，将官方 Regular/Bold OTF 放入 `.tools/font-build/`，
用安装了 fonttools 的 Python 运行 `scripts/subset_question_fonts.py`。
脚本会核对所有当前题库和界面字符的覆盖率；缺字时停止生成。
运行应用不需要 fonttools，也不需要访问外部字体 CDN。

`DentStudySymbols-Regular.ttf`、`DentStudyMath-Regular.ttf` 分别为
Noto Sans Regular 和 Noto Sans Math Regular 的精简备用字体，
覆盖中文字体中未包含的上/下标与数学符号。来源为
https://github.com/notofonts/noto-fonts/tree/main/hinted/ttf，
遵循 `OFL-symbols.txt`。生成脚本需同时准备 `NotoSans-Regular.ttf` 和
`NotoSansMath-Regular.ttf`。
