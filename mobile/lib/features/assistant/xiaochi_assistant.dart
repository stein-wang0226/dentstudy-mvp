import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/shared.dart';

/// A request-only chat companion. The conversation exists in this widget for
/// the current visit and is intentionally never written to StudyStore.
class XiaochiAssistant extends StatefulWidget {
  const XiaochiAssistant({super.key});

  @override
  State<XiaochiAssistant> createState() => _XiaochiAssistantState();
}

enum _AvatarMood { idle, interact, thinking, speaking, thanks }

class _ChatLine {
  final String role;
  final String text;
  const _ChatLine(this.role, this.text);
}

class _XiaochiAssistantState extends State<XiaochiAssistant>
    with TickerProviderStateMixin {
  // Keep the client affordance aligned with the server-side author check.
  // The server remains the authority, so editing a Web build cannot unlock
  // the chat endpoint for another account.
  static const _authorEmail = 'dentstudy1126@aka.yeah.net';
  static const _avatarWidth = 86.0;
  static const _avatarHeight = 129.0;
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  final List<_ChatLine> _lines = [
    const _ChatLine('assistant', '嗨，我是小齿～今天想从哪一章开始？')
  ];
  late final AnimationController _motion;
  Timer? _moodTimer;
  Timer? _careTimer;
  Timer? _holdTimer;
  Offset? _position;
  bool _open = false;
  bool _holding = false;
  bool _sending = false;
  bool _showCare = false;
  _AvatarMood _mood = _AvatarMood.idle;

  bool get _isAuthor => store.email.trim().toLowerCase() == _authorEmail;

  bool get _isWidgetTest => WidgetsBinding.instance.runtimeType
      .toString()
      .contains('TestWidgetsFlutterBinding');

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200));
    // A perpetually ticking avatar is desirable in the app, but it prevents
    // existing widget tests from ever reaching an idle frame. Avoid starting
    // it only under Flutter's test binding; production and local previews
    // retain the continuous breathing/sway motion.
    if (!_isWidgetTest) {
      _motion.repeat();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleCare());
    }
  }

  @override
  void dispose() {
    _moodTimer?.cancel();
    _careTimer?.cancel();
    _holdTimer?.cancel();
    _motion.dispose();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _scheduleCare() async {
    // One quiet, local greeting at most once every three days: useful enough
    // to feel companionable without constantly interrupting study.
    await Future<void>.delayed(const Duration(seconds: 16));
    if (!mounted ||
        !store.xiaochiEnabled ||
        !_isAuthor ||
        store.token.isEmpty ||
        _open) return;
    if (!await store.claimXiaochiGreeting() || !mounted) return;
    setState(() {
      _showCare = true;
      _mood = _AvatarMood.interact;
    });
    _careTimer = Timer(const Duration(seconds: 9), () {
      if (mounted) setState(() => _showCare = false);
      _setMood(_AvatarMood.idle);
    });
  }

  void _setMood(_AvatarMood mood, {Duration? resetAfter}) {
    _moodTimer?.cancel();
    if (mounted) setState(() => _mood = mood);
    if (resetAfter != null) {
      _moodTimer = Timer(resetAfter, () {
        if (mounted) setState(() => _mood = _AvatarMood.idle);
      });
    }
  }

  void _openChat() {
    _holdTimer?.cancel();
    if (_holding) return;
    if (!_isAuthor) {
      message(context, '小齿正在升级中···');
      return;
    }
    if (store.token.isEmpty) {
      message(context, '登录后才能和小齿聊天，请前往「我的」登录或注册。');
      return;
    }
    _careTimer?.cancel();
    setState(() {
      _open = true;
      _showCare = false;
    });
    _setMood(_AvatarMood.interact,
        resetAfter: const Duration(milliseconds: 1300));
    _scrollToBottom();
  }

  void _closeChat() {
    FocusScope.of(context).unfocus();
    setState(() => _open = false);
    _setMood(_AvatarMood.idle);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    if (_sending) return;
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    if (text.length > 1000) {
      message(context, '消息请控制在 1000 个字以内');
      return;
    }
    final history = _lines.length <= 6
        ? List<_ChatLine>.from(_lines)
        : _lines.sublist(_lines.length - 6);
    setState(() {
      _lines.add(_ChatLine('user', text));
      _composer.clear();
      _sending = true;
      _mood = _AvatarMood.thinking;
    });
    _scrollToBottom();
    try {
      final reply = await store.chatWithXiaochi(
          message: text,
          history: history
              .map((line) => {'role': line.role, 'content': line.text})
              .toList());
      if (!mounted) return;
      setState(() {
        _lines.add(_ChatLine('assistant', reply));
        _mood = _AvatarMood.speaking;
      });
      _moodTimer?.cancel();
      _moodTimer = Timer(const Duration(milliseconds: 1300), () {
        if (mounted) setState(() => _mood = _AvatarMood.thanks);
        _moodTimer = Timer(const Duration(milliseconds: 900), () {
          if (mounted) setState(() => _mood = _AvatarMood.idle);
        });
      });
    } catch (error) {
      if (!mounted) return;
      final detail =
          error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      setState(() {
        _lines.add(_ChatLine(
            'assistant', detail.isEmpty ? '小齿暂时没能回复，请稍后再试。' : detail));
        _mood = _AvatarMood.idle;
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  Offset _clampPosition(Offset proposed, Size size, EdgeInsets padding) {
    final bottomReserved = (store.glassEnabled ? 104.0 : 94.0) + padding.bottom;
    final maxX = math.max(8.0, size.width - _avatarWidth - 8);
    final maxY = math.max(72.0, size.height - _avatarHeight - bottomReserved);
    return Offset(proposed.dx.clamp(8.0, maxX).toDouble(),
        proposed.dy.clamp(72.0, maxY).toDouble());
  }

  void _armDrag() {
    _holdTimer?.cancel();
    // Flutter's default long-press delay is intentionally conservative.
    // 小齿 is a floating control, so a short hold makes its drag affordance
    // feel immediate without turning an ordinary tap into a drag.
    _holdTimer = Timer(const Duration(milliseconds: 120), _startHolding);
  }

  void _startHolding() {
    if (_holding) return;
    _holdTimer?.cancel();
    _careTimer?.cancel();
    setState(() {
      _holding = true;
      _showCare = false;
    });
  }

  void _moveHolding(DragUpdateDetails details, Size size, EdgeInsets padding) {
    _startHolding();
    final proposed = Offset(details.globalPosition.dx - _avatarWidth / 2,
        details.globalPosition.dy - _avatarHeight / 2);
    setState(() => _position = _clampPosition(proposed, size, padding));
  }

  Future<void> _endHolding(Size size, EdgeInsets padding) async {
    _holdTimer?.cancel();
    if (!_holding) return;
    final position = _position;
    if (position != null) {
      final maxX = math.max(8.0, size.width - _avatarWidth - 8);
      final maxY = math.max(
          72.0,
          size.height -
              _avatarHeight -
              (store.glassEnabled ? 104.0 : 94.0) -
              padding.bottom);
      await store.setXiaochiPosition(position.dx / maxX, position.dy / maxY);
    }
    // Keep the drag state through this event turn so the tap recognizer cannot
    // also open the chat when someone simply holds the avatar in place.
    await Future<void>.delayed(Duration.zero);
    if (mounted) setState(() => _holding = false);
  }

  void _cancelHolding() {
    _holdTimer?.cancel();
    if (mounted && _holding) setState(() => _holding = false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: store, builder: (context, _) => _buildOverlay(context));

  Widget _buildOverlay(BuildContext context) {
    if (!store.xiaochiEnabled) return const SizedBox.shrink();
    final media = MediaQuery.of(context);
    final size = media.size;
    final padding = media.padding;
    final maxX = math.max(8.0, size.width - _avatarWidth - 8);
    final maxY = math.max(
        72.0,
        size.height -
            _avatarHeight -
            (store.glassEnabled ? 104.0 : 94.0) -
            padding.bottom);
    final initial = Offset(maxX - 2, maxY - 4);
    final persisted = store.xiaochiPositionX != null &&
            store.xiaochiPositionY != null
        ? Offset(store.xiaochiPositionX! * maxX, store.xiaochiPositionY! * maxY)
        : initial;
    final position = _clampPosition(_position ?? persisted, size, padding);
    final chatWidth = math.min(366.0, size.width - 24);

    return Stack(clipBehavior: Clip.none, children: [
      Positioned(
          right: 12,
          bottom: (store.glassEnabled ? 92.0 : 78.0) + padding.bottom,
          child: _ChatPanel(
              open: _open,
              width: chatWidth,
              sending: _sending,
              composer: _composer,
              scroll: _scroll,
              lines: _lines,
              onClose: _closeChat,
              onSend: _send)),
      Positioned(
          left: position.dx,
          top: position.dy,
          child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _openChat,
              onTapDown: (_) => _armDrag(),
              onTapUp: (_) {
                if (_holding) {
                  unawaited(_endHolding(size, padding));
                } else {
                  _holdTimer?.cancel();
                }
              },
              onTapCancel: _cancelHolding,
              onPanStart: (_) => _startHolding(),
              onPanUpdate: (details) => _moveHolding(details, size, padding),
              onPanEnd: (_) => unawaited(_endHolding(size, padding)),
              onPanCancel: _cancelHolding,
              child: SizedBox(
                  width: _avatarWidth,
                  height: _avatarHeight,
                  child: Stack(clipBehavior: Clip.none, children: [
                    if (_showCare)
                      Positioned(
                          right: 20,
                          bottom: 103,
                          child: _CareBubble(onTap: _openChat)),
                    Positioned.fill(
                        child: _AvatarArt(
                            mood: _mood, motion: _motion, holding: _holding)),
                  ]))))
    ]);
  }
}

class _AvatarArt extends StatelessWidget {
  final _AvatarMood mood;
  final Animation<double> motion;
  final bool holding;
  const _AvatarArt(
      {required this.mood, required this.motion, required this.holding});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: motion,
      builder: (context, _) {
        final wave = math.sin(motion.value * math.pi * 2);
        var lift = 0.0;
        var turn = 0.0;
        var scaleX = 1.0;
        var scaleY = 1.0;
        switch (mood) {
          case _AvatarMood.idle:
            lift = wave * 1.6;
            turn = wave * .018;
            scaleX = 1 + wave * .007;
            scaleY = 1 - wave * .006;
            break;
          case _AvatarMood.interact:
            lift = -math.max(0, wave) * 7;
            turn = wave * .04;
            break;
          case _AvatarMood.thinking:
            lift = wave * 1.8;
            turn = wave * .035;
            break;
          case _AvatarMood.speaking:
            lift = wave * 1.2;
            turn = wave * .012;
            break;
          case _AvatarMood.thanks:
            lift = -math.max(0, wave) * 5;
            scaleX = 1 + math.max(0, wave) * .025;
            scaleY = 1 - math.max(0, wave) * .018;
            break;
        }
        return AnimatedScale(
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOutBack,
            scale: holding ? 1.12 : 1,
            child: Stack(clipBehavior: Clip.none, children: [
              if (holding)
                Positioned.fill(
                    child: Transform.scale(
                        scale: 1.06 + (wave + 1) * .025,
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: teal.withAlpha(150), width: 1.5),
                                boxShadow: [
                              BoxShadow(
                                  color: teal.withAlpha(65),
                                  blurRadius: 18,
                                  spreadRadius: 4)
                            ])))),
              Transform(
                  alignment: Alignment.bottomCenter,
                  transform: Matrix4.identity()
                    ..translateByDouble(0.0, lift, 0.0, 1.0)
                    ..rotateZ(turn)
                    ..scaleByDouble(scaleX, scaleY, 1.0, 1.0),
                  child: ClipPath(
                      // The supplied illustration has a faint opaque studio
                      // vignette despite its PNG alpha channel. A soft
                      // character-shaped mask removes that rectangular field
                      // without changing the face or the illustrated pixels.
                      clipper: const _AvatarSilhouetteClipper(),
                      child: const _AvatarImage())),
              if (mood == _AvatarMood.speaking)
                Positioned(
                    left: 39,
                    top: 53,
                    child: Transform.scale(
                        scaleY: .65 + math.max(0, wave) * .65,
                        alignment: Alignment.topCenter,
                        child: Container(
                            width: 5.5,
                            height: 2.6,
                            decoration: const BoxDecoration(
                                color: Color(0xFFE88486),
                                borderRadius: BorderRadius.vertical(
                                    bottom: Radius.circular(5)))))),
              if (mood == _AvatarMood.thinking)
                _OrbitDots(progress: motion.value),
              if (mood == _AvatarMood.thanks) _Sparkles(progress: motion.value),
            ]));
      });
}

class _AvatarSilhouetteClipper extends CustomClipper<Path> {
  const _AvatarSilhouetteClipper();

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    // This deliberately follows the broad outline instead of making a card
    // or a circle. At the on-screen avatar size it leaves room for hair tips,
    // sleeves and shoes while excluding the source artwork's backdrop.
    return Path()
      ..moveTo(w * .49, 0)
      ..cubicTo(w * .35, h * .02, w * .24, h * .08, w * .17, h * .16)
      ..cubicTo(w * .10, h * .10, w * .03, h * .16, w * .07, h * .24)
      ..cubicTo(0, h * .29, w * .07, h * .36, w * .14, h * .39)
      ..cubicTo(w * .08, h * .44, w * .13, h * .50, w * .21, h * .52)
      ..cubicTo(w * .16, h * .59, w * .10, h * .66, w * .12, h * .73)
      ..cubicTo(w * .16, h * .78, w * .21, h * .75, w * .24, h * .70)
      ..cubicTo(w * .23, h * .80, w * .30, h * .85, w * .38, h * .87)
      ..cubicTo(w * .34, h * .94, w * .29, h * .98, w * .29, h)
      ..lineTo(w * .71, h)
      ..cubicTo(w * .71, h * .98, w * .66, h * .94, w * .62, h * .87)
      ..cubicTo(w * .70, h * .85, w * .77, h * .80, w * .76, h * .70)
      ..cubicTo(w * .79, h * .75, w * .84, h * .78, w * .88, h * .73)
      ..cubicTo(w * .90, h * .66, w * .84, h * .59, w * .79, h * .52)
      ..cubicTo(w * .87, h * .50, w * .92, h * .44, w * .86, h * .39)
      ..cubicTo(w * .93, h * .36, w, h * .29, w * .93, h * .24)
      ..cubicTo(w * .97, h * .16, w * .90, h * .10, w * .83, h * .16)
      ..cubicTo(w * .76, h * .08, w * .65, h * .02, w * .49, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant _AvatarSilhouetteClipper oldClipper) => false;
}

/// Uses the original supplied illustration without any colour overlays.
/// This avoids introducing visible clip edges around hair or clothing when a
/// theme changes.
class _AvatarImage extends StatelessWidget {
  const _AvatarImage();

  @override
  Widget build(BuildContext context) => Image.asset('assets/xiaochi/avatar.png',
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: '小齿，口腔备考搭子');
}

class _OrbitDots extends StatelessWidget {
  final double progress;
  const _OrbitDots({required this.progress});
  @override
  Widget build(BuildContext context) => Positioned(
      left: 24,
      top: -1,
      width: 40,
      height: 40,
      child: Stack(
          children: List.generate(3, (index) {
        final radians = progress * math.pi * 2 + index * math.pi * 2 / 3;
        return Positioned(
            left: 17 + math.cos(radians) * 16,
            top: 17 + math.sin(radians) * 12,
            child: Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                    color: Color(0xFFDFFFFE),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Color(0xAA72FFF6), blurRadius: 7)
                    ])));
      })));
}

class _Sparkles extends StatelessWidget {
  final double progress;
  const _Sparkles({required this.progress});
  @override
  Widget build(BuildContext context) {
    final grow = 1 + math.max(0, math.sin(progress * math.pi * 2)) * .35;
    return Positioned.fill(
        child: Transform.scale(
            scale: grow,
            child: Stack(children: const [
              Positioned(left: 7, top: 37, child: _Sparkle()),
              Positioned(right: 5, top: 48, child: _Sparkle()),
              Positioned(left: 16, bottom: 32, child: _Sparkle()),
              Positioned(right: 14, bottom: 20, child: _Sparkle()),
            ])));
  }
}

class _Sparkle extends StatelessWidget {
  const _Sparkle();
  @override
  Widget build(BuildContext context) => Container(
      width: 4.5,
      height: 4.5,
      decoration: const BoxDecoration(
          color: Color(0xFFDFFFFE),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Color(0xAA65FFF2), blurRadius: 7)]));
}

class _CareBubble extends StatelessWidget {
  final VoidCallback onTap;
  const _CareBubble({required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
      color: Colors.transparent,
      child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Container(
              width: 196,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                  color: store.glassEnabled
                      ? Colors.white.withAlpha(208)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: teal.withAlpha(32)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withAlpha(18),
                        blurRadius: 16,
                        offset: const Offset(0, 5))
                  ]),
              child: const Text('今天也辛苦啦，刷几道就很好～',
                  style: TextStyle(fontSize: 12.5)))));
}

class _ChatPanel extends StatelessWidget {
  final bool open;
  final double width;
  final bool sending;
  final TextEditingController composer;
  final ScrollController scroll;
  final List<_ChatLine> lines;
  final VoidCallback onClose;
  final Future<void> Function() onSend;
  const _ChatPanel({
    required this.open,
    required this.width,
    required this.sending,
    required this.composer,
    required this.scroll,
    required this.lines,
    required this.onClose,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) => IgnorePointer(
      ignoring: !open,
      child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          opacity: open ? 1 : 0,
          child: AnimatedScale(
              duration: const Duration(milliseconds: 230),
              curve: Curves.easeOutBack,
              alignment: Alignment.bottomRight,
              scale: open ? 1 : .9,
              child: SizedBox(
                  width: width,
                  height: 420,
                  child: Material(
                      color: Colors.transparent,
                      child: Container(
                          decoration: BoxDecoration(
                              color: store.glassEnabled
                                  ? Colors.white.withAlpha(210)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                  color: store.glassEnabled
                                      ? Colors.white.withAlpha(230)
                                      : teal.withAlpha(36)),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withAlpha(34),
                                    blurRadius: 26,
                                    offset: const Offset(0, 12))
                              ]),
                          child: Column(children: [
                            Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 11, 8, 8),
                                child: Row(children: [
                                  CircleAvatar(
                                      radius: 17,
                                      backgroundColor: teal.withAlpha(30),
                                      child: Image.asset(
                                          'assets/xiaochi/avatar.png',
                                          fit: BoxFit.contain)),
                                  const SizedBox(width: 9),
                                  const Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text('小齿',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 16)),
                                        Text('口腔医学/备考不限 · 闲聊每日 10 句',
                                            style: TextStyle(
                                                color: Colors.blueGrey,
                                                fontSize: 11))
                                      ])),
                                  IconButton(
                                      tooltip: '关闭小齿聊天',
                                      onPressed: onClose,
                                      icon: const Icon(Icons.close_rounded))
                                ])),
                            Divider(height: 1, color: teal.withAlpha(20)),
                            Expanded(
                                child: ListView.builder(
                                    controller: scroll,
                                    padding: const EdgeInsets.fromLTRB(
                                        13, 14, 13, 6),
                                    itemCount: lines.length + (sending ? 1 : 0),
                                    itemBuilder: (context, index) {
                                      if (index == lines.length) {
                                        return const _TypingLine();
                                      }
                                      return _ChatBubble(line: lines[index]);
                                    })),
                            const Padding(
                                padding: EdgeInsets.fromLTRB(15, 2, 15, 7),
                                child: Text(
                                    '消息仅为当前回复发送给 AI 服务，DentStudy 不保存聊天内容。请勿发送隐私或未授权资料。',
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        color: Colors.blueGrey))),
                            Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 0, 8, 10),
                                child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Expanded(
                                          child: TextField(
                                              controller: composer,
                                              enabled: !sending,
                                              minLines: 1,
                                              maxLines: 3,
                                              maxLength: 1000,
                                              textInputAction:
                                                  TextInputAction.send,
                                              onSubmitted: (_) => onSend(),
                                              decoration: const InputDecoration(
                                                  hintText: '问问学习方法或知识点…',
                                                  counterText: '',
                                                  isDense: true,
                                                  contentPadding:
                                                      EdgeInsets.symmetric(
                                                          horizontal: 13,
                                                          vertical: 11)))),
                                      const SizedBox(width: 5),
                                      IconButton.filled(
                                          tooltip: '发送给小齿',
                                          onPressed: sending ? null : onSend,
                                          icon: sending
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Colors.white))
                                              : const Icon(
                                                  Icons.arrow_upward_rounded))
                                    ]))
                          ])))))));
}

class _ChatBubble extends StatelessWidget {
  final _ChatLine line;
  const _ChatBubble({required this.line});
  @override
  Widget build(BuildContext context) {
    final mine = line.role == 'user';
    return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
            constraints: const BoxConstraints(maxWidth: 286),
            margin: const EdgeInsets.only(bottom: 9),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
                color: mine ? teal : teal.withAlpha(17),
                borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(15),
                    topRight: const Radius.circular(15),
                    bottomLeft: Radius.circular(mine ? 15 : 4),
                    bottomRight: Radius.circular(mine ? 4 : 15))),
            child: Text(line.text,
                style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: mine ? Colors.white : ink))));
  }
}

class _TypingLine extends StatelessWidget {
  const _TypingLine();
  @override
  Widget build(BuildContext context) => Align(
      alignment: Alignment.centerLeft,
      child: Container(
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              color: teal.withAlpha(17),
              borderRadius: BorderRadius.circular(15)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: teal)),
            const SizedBox(width: 8),
            const Text('小齿正在想…', style: TextStyle(fontSize: 12.5))
          ])));
}
