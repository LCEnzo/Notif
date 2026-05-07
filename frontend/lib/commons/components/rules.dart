import 'package:flutter/material.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';

enum RuleStrength { faint, strong }

class Rule extends StatelessWidget {
  const Rule({this.strength = RuleStrength.faint, this.margin, super.key});
  final RuleStrength strength;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final color = strength == RuleStrength.strong
        ? tokens.ruleStrong
        : tokens.rule;
    return Container(margin: margin, height: 1, color: color);
  }
}

class IndexRule extends StatelessWidget {
  const IndexRule({
    required this.index,
    required this.title,
    this.meta,
    super.key,
  });
  final int index;
  final String title;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final padded = index.toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(padded, style: text$.micro.copyWith(color: tokens.inkMute)),
          const SizedBox(width: 12),
          Text(
            title.toUpperCase(),
            style: text$.eyebrow.copyWith(color: tokens.inkDim),
          ),
          const SizedBox(width: 12),
          Expanded(child: Container(height: 1, color: tokens.rule)),
          if (meta != null) ...[
            const SizedBox(width: 12),
            Text(
              meta!.toUpperCase(),
              style: text$.micro.copyWith(color: tokens.inkMute),
            ),
          ],
        ],
      ),
    );
  }
}
