import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../app/shared.dart';
import '../../app/theme_surfaces.dart';
import 'background_image.dart';

class AppearanceSettings extends StatefulWidget {
  const AppearanceSettings({super.key});
  @override
  State<AppearanceSettings> createState() => _AppearanceSettingsState();
}

class _AppearanceSettingsState extends State<AppearanceSettings> {
  bool choosingImage = false;
  String? imageError;

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
                  if (key != null) {
                    safely(
                        context,
                        () => store.setCustomTheme(
                            primary: background ? store.customPrimaryKey : key,
                            background:
                                background ? key : store.customBackgroundKey));
                  }
                })));
  }

  Future<void> pickBackground(BuildContext context) async {
    setState(() {
      choosingImage = true;
      imageError = null;
    });
    try {
      final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
          withData: true);
      if (picked == null) return;
      final file = picked.files.single;
      if (file.bytes == null ||
          !const ['jpg', 'jpeg', 'png', 'webp']
              .contains(file.extension?.toLowerCase())) {
        throw Exception('请选择 JPG、PNG 或 WebP 格式的图片');
      }
      final prepared = await prepareBackgroundImage(file.bytes!);
      await store.setCustomBackground(prepared);
      if (mounted) {
        message(context,
            '背景已保存，并按图片主色匹配为${themeNames[prepared.suggestedThemeKey]}主题');
      }
    } catch (error) {
      if (mounted) {
        setState(() =>
            imageError = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => choosingImage = false);
    }
  }

  Widget backgroundPreview() {
    final bytes = store.customBackgroundImageBytes;
    if (bytes == null) return const SizedBox.shrink();
    return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
            height: 170,
            child: Stack(children: [
              Positioned.fill(child: ColoredBox(color: paper)),
              Positioned.fill(
                  child: Opacity(
                      opacity: store.customBackgroundOpacity,
                      child: ClipRect(
                          child: Transform.scale(
                              scale: store.customBackgroundScale,
                              child: Image.memory(bytes, fit: BoxFit.cover))))),
              Positioned.fill(
                  child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: StudySurface(
                          glass: true,
                          radius: 18,
                          tint: backgroundTint,
                          borderColor: Colors.transparent,
                          padding: const EdgeInsets.all(16),
                          child: const Center(
                              child: Text('玻璃预览',
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700))))))
            ])));
  }

  Widget customBackground(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: paper,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: teal.withAlpha(32))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.wallpaper_outlined),
          SizedBox(width: 10),
          Text('自定义图片背景',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))
        ]),
        const SizedBox(height: 8),
        const Text(
            '仅保存在本设备，不上传服务器、不参与账号同步。支持 JPG / PNG / WebP；原图不超过 8 MB，建议 16:9 或 9:16 图片。系统会压缩为适合网页本机保存的背景，暂不支持 HEIC、GIF、PDF 或截图文件夹。',
            style:
                TextStyle(fontSize: 12, height: 1.5, color: Colors.blueGrey)),
        const SizedBox(height: 14),
        if (store.hasCustomBackground) ...[
          backgroundPreview(),
          const SizedBox(height: 12),
          Text('图片主色已自动匹配为${themeNames[store.customPrimaryKey]}；可继续调整。',
              style: TextStyle(fontSize: 12, color: teal)),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.zoom_out, size: 18),
            Expanded(
                child: Slider(
                    key: const ValueKey('background-scale'),
                    value: store.customBackgroundScale,
                    min: .8,
                    max: 2.4,
                    divisions: 32,
                    label: '${store.customBackgroundScale.toStringAsFixed(2)}×',
                    onChanged: (value) =>
                        store.previewCustomBackground(scale: value),
                    onChangeEnd: (_) => safely(
                        context, store.saveCustomBackgroundPresentation))),
            const Icon(Icons.zoom_in, size: 18)
          ]),
          Text('缩放 ${store.customBackgroundScale.toStringAsFixed(2)}×',
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
          const SizedBox(height: 4),
          Slider(
              key: const ValueKey('background-opacity'),
              value: store.customBackgroundOpacity,
              min: 0,
              max: 1,
              divisions: 100,
              label: '${(store.customBackgroundOpacity * 100).round()}%',
              onChanged: (value) =>
                  store.previewCustomBackground(opacity: value),
              onChangeEnd: (_) =>
                  safely(context, store.saveCustomBackgroundPresentation)),
          Text(
              '背景图片透明度 ${(store.customBackgroundOpacity * 100).round()}%（0% 完全透明，100% 完整显示）',
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
          const SizedBox(height: 10),
        ],
        Wrap(spacing: 10, runSpacing: 8, children: [
          FilledButton.icon(
              onPressed: choosingImage ? null : () => pickBackground(context),
              icon: Icon(choosingImage
                  ? Icons.hourglass_top_outlined
                  : Icons.photo_library_outlined),
              label: Text(choosingImage
                  ? '正在处理图片…'
                  : store.hasCustomBackground
                      ? '更换背景图片'
                      : '选择背景图片')),
          if (store.hasCustomBackground)
            OutlinedButton.icon(
                onPressed: () => safely(context, store.clearCustomBackground),
                icon: const Icon(Icons.hide_image_outlined),
                label: const Text('移除图片背景'))
        ]),
        if (imageError != null) ...[
          const SizedBox(height: 8),
          Text(imageError!,
              style: const TextStyle(fontSize: 12, color: Colors.deepOrange))
        ]
      ]));

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
            const SizedBox(height: 16),
            customBackground(context),
            const Divider(height: 32),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('玻璃质感'),
                subtitle: const Text('透出背景的清澈折射卡片与半透明导航'),
                secondary: const Icon(Icons.blur_on),
                value: store.glassEnabled,
                onChanged: (value) =>
                    safely(context, () => store.setGlassEnabled(value))),
          ]));
}
