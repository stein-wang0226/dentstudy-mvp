import 'package:flutter/material.dart';
import '../../app/shared.dart';

class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({super.key});

  Widget _swatch(String key, {double size = 20, bool pale = false}) =>
      Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: pale
                  ? Color.lerp(Colors.white, themeColors[key], .045)
                  : themeColors[key],
              border: Border.all(color: ink.withAlpha(30))));

  Widget _picker(BuildContext context, {required bool background}) {
    final value =
        background ? store.customBackgroundKey : store.customPrimaryKey;
    return InputDecorator(
        decoration: InputDecoration(labelText: background ? '淡背景色' : '主色调'),
        child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
                key: ValueKey(background
                    ? 'custom-background-color'
                    : 'custom-primary-color'),
                value: value,
                isExpanded: true,
                isDense: true,
                items: themeColors.keys
                    .map((key) => DropdownMenuItem(
                        value: key,
                        child: Row(children: [
                          _swatch(key, pale: background),
                          const SizedBox(width: 10),
                          Text(themeNames[key]!)
                        ])))
                    .toList(),
                onChanged: (key) {
                  if (key != null)
                    safely(
                        context,
                        () => store.setCustomTheme(
                            primary: background ? store.customPrimaryKey : key,
                            background:
                                background ? key : store.customBackgroundKey));
                })));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: store,
      builder: (context, _) =>
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('选择主题，或自由搭配主色与淡背景。'),
            const SizedBox(height: 16),
            Wrap(
                spacing: 12,
                runSpacing: 12,
                children: themeColors.entries.map((entry) {
                  final selected = store.themeColorKey == entry.key;
                  return Tooltip(
                      message: themeNames[entry.key]!,
                      child: Semantics(
                          label: themeNames[entry.key],
                          selected: selected,
                          button: true,
                          child: InkWell(
                              onTap: () => safely(context,
                                  () => store.setThemeColor(entry.key)),
                              borderRadius: BorderRadius.circular(24),
                              child: Container(
                                  width: 42,
                                  height: 42,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                      color: entry.value,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: selected
                                              ? ink
                                              : Colors.transparent,
                                          width: 3)),
                                  child: selected
                                      ? const Icon(Icons.check,
                                          color: Colors.white)
                                      : null))));
                }).toList()),
            const SizedBox(height: 14),
            Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                      onPressed: () =>
                          safely(context, () => store.setThemeColor('custom')),
                      icon: Icon(store.themeColorKey == 'custom'
                          ? Icons.check_circle_outline
                          : Icons.palette_outlined),
                      label: const Text('自定义')),
                  Text(
                      store.themeColorKey == 'custom'
                          ? '自定义配色已启用'
                          : '当前：${themeNames[store.themeColorKey] ?? '青绿'}',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.blueGrey)),
                ]),
            if (store.themeColorKey == 'custom') ...[
              const SizedBox(height: 16),
              LayoutBuilder(
                  builder: (context, constraints) => constraints.maxWidth < 440
                      ? Column(children: [
                          _picker(context, background: false),
                          const SizedBox(height: 16),
                          _picker(context, background: true)
                        ])
                      : Row(children: [
                          Expanded(child: _picker(context, background: false)),
                          const SizedBox(width: 16),
                          Expanded(child: _picker(context, background: true))
                        ])),
              const SizedBox(height: 12),
              Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: paper,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: teal.withAlpha(35))),
                  child: Row(children: [
                    Icon(Icons.auto_stories_outlined, color: teal),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(
                            '主色：${themeNames[store.customPrimaryKey]} · 背景：淡${themeNames[store.customBackgroundKey]}',
                            style: TextStyle(color: ink)))
                  ])),
            ],
            const Divider(height: 32),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('玻璃质感'),
                subtitle: const Text('透出背景的磨砂卡片、玻璃高光与半透明导航'),
                secondary: const Icon(Icons.blur_on),
                value: store.glassEnabled,
                onChanged: (value) =>
                    safely(context, () => store.setGlassEnabled(value))),
          ]));
}
