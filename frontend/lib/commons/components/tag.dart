import 'package:flutter/material.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';

enum TagTone { defaultTone, accent, muted }

class Tag extends StatelessWidget {

  const Tag(this.label, {this.tone = TagTone.defaultTone, super.key});
  final String label;
  final TagTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    final Color text;
    final Color border;
    switch (tone) {
      case TagTone.defaultTone:
        text = tokens.inkDim;
        border = tokens.rule;
        break;
      case TagTone.accent:
        text = tokens.accent;
        border = tokens.accent;
        break;
      case TagTone.muted:
        text = tokens.inkMute;
        border = tokens.rule;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: border, width: 1)),
      child: Text(
        label.toUpperCase(),
        style: text$.micro.copyWith(color: text),
      ),
    );
  }
}
