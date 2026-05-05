import 'package:flutter/material.dart';
import 'package:notif/commons/components/corner_marks.dart';
import 'package:notif/commons/notif_tokens.dart';

class NotifCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool bordered;
  final bool cornerMarks;
  final VoidCallback? onTap;

  const NotifCard({
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.bordered = true,
    this.cornerMarks = false,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);

    final container = Container(
      decoration: BoxDecoration(
        color: tokens.bg2,
        border: bordered ? Border.all(color: tokens.rule, width: 1) : null,
      ),
      padding: padding,
      child: child,
    );

    final wrapped = cornerMarks ? CornerMarks(child: container) : container;

    if (onTap == null) return wrapped;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: tokens.accent.withValues(alpha: 0.08),
        highlightColor: tokens.accent.withValues(alpha: 0.04),
        child: wrapped,
      ),
    );
  }
}
