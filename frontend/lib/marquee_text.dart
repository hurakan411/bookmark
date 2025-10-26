import 'package:flutter/material.dart';

class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  const MarqueeText({required this.text, this.style});
  @override
  State<MarqueeText> createState() => MarqueeTextState();
}

class MarqueeTextState extends State<MarqueeText> with SingleTickerProviderStateMixin {
  late final ScrollController _controller;
  late final AnimationController _animController;
  double _textWidth = 0;
  double _containerWidth = 0;

  static const double marqueeSpeed = 40.0; // px/sec 統一速度
  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  _animController = AnimationController(vsync: this, duration: const Duration(seconds: 1));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 5), _measureAndAnimate);
    });
  }

  VoidCallback? _animListener;
  bool _disposed = false;
  void _measureAndAnimate() {
    final textPainter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    if (!mounted) return;
    setState(() {
      _textWidth = textPainter.width;
      _containerWidth = context.size?.width ?? 0;
    });
    // 半角15文字を超えた場合のみスクロール
    final asciiCount = widget.text.runes.fold<int>(0, (prev, rune) {
      return prev + (rune <= 0x7F ? 1 : 2); // ASCII:1, 全角:2
    });
    if (asciiCount > 15 && _textWidth > _containerWidth) {
      final extra = 50.0;
      final maxScroll = (_textWidth - _containerWidth) + extra;
      final durationMs = (maxScroll / marqueeSpeed * 1000).round();
      _animController.duration = Duration(milliseconds: durationMs);
      void startScroll() {
        if (_disposed) return;
        _animController.forward(from: 0);
      }
      _animListener = () {
        if (_disposed) return;
        double offset = (_animController.value * maxScroll).clamp(0, maxScroll);
        if (offset >= maxScroll) {
          Future.delayed(const Duration(milliseconds: 600), () async {
            if (_disposed) return;
            if (_controller.hasClients) {
              _controller.jumpTo(0.0);
            }
            await Future.delayed(const Duration(seconds: 1));
            if (_disposed) return;
            startScroll();
          });
        } else {
          if (_controller.hasClients) {
            _controller.jumpTo(offset);
          }
        }
      };
      _animController.addListener(_animListener!);
      startScroll(); // 測定後すぐにスクロール開始（既に10秒待機済み）
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_animListener != null) {
      _animController.removeListener(_animListener!);
    }
    _animController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 半角15文字以下なら普通のTextで表示
    final asciiCount = widget.text.runes.fold<int>(0, (prev, rune) {
      return prev + (rune <= 0x7F ? 1 : 2);
    });
    if (asciiCount <= 15) {
      return SizedBox(
        height: 22,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            widget.text,
            style: widget.style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    // それ以外はスクロール
    return SizedBox(
      height: 22,
      child: ListView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              widget.text,
              style: widget.style,
              maxLines: 1,
              overflow: TextOverflow.visible,
            ),
          ),
        ],
      ),
    );
  }
}
