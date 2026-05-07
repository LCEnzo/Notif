import 'package:flutter/material.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';

enum StatusDotState { live, synced, idle, warning, error }

class StatusDot extends StatelessWidget {
  const StatusDot({this.state = StatusDotState.idle, this.label, super.key});
  final StatusDotState state;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    final Color color;
    switch (state) {
      case StatusDotState.live:
        color = tokens.accent;
        break;
      case StatusDotState.synced:
        color = tokens.accent2;
        break;
      case StatusDotState.idle:
        color = tokens.inkMute;
        break;
      case StatusDotState.warning:
        color = NotifFeedback.warning;
        break;
      case StatusDotState.error:
        color = NotifFeedback.error;
        break;
    }

    final dot = Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.2),
            blurRadius: 0,
            spreadRadius: 3,
          ),
        ],
      ),
    );

    if (label == null) return dot;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        dot,
        const SizedBox(width: 8),
        Text(
          label!.toUpperCase(),
          style: text$.micro.copyWith(color: tokens.inkDim),
        ),
      ],
    );
  }
}
