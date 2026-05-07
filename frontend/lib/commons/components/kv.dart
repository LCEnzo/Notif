import 'package:flutter/material.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';

class KV extends StatelessWidget {
  const KV({
    required this.label,
    required this.value,
    this.meta,
    this.minLabelWidth = 120,
    super.key,
  });

  factory KV.text({
    required String label,
    required String value,
    String? meta,
    double minLabelWidth = 120,
    Key? key,
  }) {
    return KV(
      key: key,
      label: label,
      meta: meta,
      minLabelWidth: minLabelWidth,
      value: _KVText(value: value),
    );
  }
  final String label;
  final Widget value;
  final String? meta;
  final double minLabelWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SizedBox(
                width: minLabelWidth,
                child: Text(
                  label.toUpperCase(),
                  style: text$.micro.copyWith(color: tokens.inkMute),
                ),
              ),
              Expanded(
                child: DefaultTextStyle.merge(
                  style: text$.body.copyWith(color: tokens.ink),
                  child: value,
                ),
              ),
              if (meta != null)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    meta!.toUpperCase(),
                    style: text$.micro.copyWith(color: tokens.inkMute),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          CustomPaint(
            size: const Size.fromHeight(1),
            painter: _DashedRulePainter(color: tokens.rule),
          ),
        ],
      ),
    );
  }
}

class _KVText extends StatelessWidget {
  const _KVText({required this.value});
  final String value;

  @override
  Widget build(BuildContext context) => Text(value);
}

class _DashedRulePainter extends CustomPainter {
  _DashedRulePainter({required this.color});
  static const double _dashWidth = 4;
  static const double _gap = 3;

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + _dashWidth, 0), paint);
      x += _dashWidth + _gap;
    }
  }

  @override
  bool shouldRepaint(_DashedRulePainter old) => old.color != color;
}
