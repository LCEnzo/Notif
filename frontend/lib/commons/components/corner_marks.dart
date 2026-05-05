import 'package:flutter/material.dart';
import 'package:notif/commons/notif_tokens.dart';

class CornerMarks extends StatelessWidget {
  final Widget child;
  final double inset;
  final double length;
  final Color? color;

  const CornerMarks({
    required this.child,
    this.inset = 6,
    this.length = 10,
    this.color,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final c = color ?? tokens.ruleStrong;

    return Stack(clipBehavior: Clip.none, children: [child, ..._ticks(c)]);
  }

  List<Widget> _ticks(Color c) {
    const thickness = 1.0;
    return [
      Positioned(left: inset, top: inset, child: _HBar(length, c, thickness)),
      Positioned(left: inset, top: inset, child: _VBar(length, c, thickness)),
      Positioned(right: inset, top: inset, child: _HBar(length, c, thickness)),
      Positioned(right: inset, top: inset, child: _VBar(length, c, thickness)),
      Positioned(
        left: inset,
        bottom: inset,
        child: _HBar(length, c, thickness),
      ),
      Positioned(
        left: inset,
        bottom: inset,
        child: _VBar(length, c, thickness),
      ),
      Positioned(
        right: inset,
        bottom: inset,
        child: _HBar(length, c, thickness),
      ),
      Positioned(
        right: inset,
        bottom: inset,
        child: _VBar(length, c, thickness),
      ),
    ];
  }
}

class _HBar extends StatelessWidget {
  final double length;
  final Color color;
  final double thickness;

  const _HBar(this.length, this.color, this.thickness);

  @override
  Widget build(BuildContext context) => SizedBox(
    width: length,
    height: thickness,
    child: ColoredBox(color: color),
  );
}

class _VBar extends StatelessWidget {
  final double length;
  final Color color;
  final double thickness;

  const _VBar(this.length, this.color, this.thickness);

  @override
  Widget build(BuildContext context) => SizedBox(
    width: thickness,
    height: length,
    child: ColoredBox(color: color),
  );
}
