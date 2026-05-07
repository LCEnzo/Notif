import 'package:flutter/material.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';

enum EyebrowSize { regular, micro }

enum EyebrowTone { mute, dim, accent }

class Eyebrow extends StatelessWidget {
  const Eyebrow(
    this.text, {
    this.size = EyebrowSize.regular,
    this.tone = EyebrowTone.mute,
    super.key,
  });
  final String text;
  final EyebrowSize size;
  final EyebrowTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    final base = size == EyebrowSize.regular ? text$.eyebrow : text$.micro;

    final Color color;
    switch (tone) {
      case EyebrowTone.mute:
        color = tokens.inkMute;
        break;
      case EyebrowTone.dim:
        color = tokens.inkDim;
        break;
      case EyebrowTone.accent:
        color = tokens.accent;
        break;
    }

    return Text(text.toUpperCase(), style: base.copyWith(color: color));
  }
}
