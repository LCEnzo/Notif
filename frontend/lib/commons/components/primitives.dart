import 'package:flutter/material.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';

// ═══════════════════════════════════════════════════════════════
// Eyebrow — tracked-out uppercase mono label above content blocks.
// Structural; never decorative.
// ═══════════════════════════════════════════════════════════════

enum EyebrowSize { regular, micro }

enum EyebrowTone { mute, dim, accent }

class Eyebrow extends StatelessWidget {
  final String text;
  final EyebrowSize size;
  final EyebrowTone tone;

  const Eyebrow(
    this.text, {
    this.size = EyebrowSize.regular,
    this.tone = EyebrowTone.mute,
    super.key,
  });

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

// ═══════════════════════════════════════════════════════════════
// Rule — plain 1px hairline.
// ═══════════════════════════════════════════════════════════════

enum RuleStrength { faint, strong }

class Rule extends StatelessWidget {
  final RuleStrength strength;
  final EdgeInsetsGeometry? margin;

  const Rule({this.strength = RuleStrength.faint, this.margin, super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final color = strength == RuleStrength.strong
        ? tokens.ruleStrong
        : tokens.rule;
    return Container(margin: margin, height: 1, color: color);
  }
}

// ═══════════════════════════════════════════════════════════════
// IndexRule — zero-padded section number + title + hairline + optional meta.
// The numbered spine of the printed-document feel.
// ═══════════════════════════════════════════════════════════════

class IndexRule extends StatelessWidget {
  final int index;
  final String title;
  final String? meta;

  const IndexRule({
    required this.index,
    required this.title,
    this.meta,
    super.key,
  });

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

// ═══════════════════════════════════════════════════════════════
// CornerMarks — blueprint tick marks inside a card.
// ═══════════════════════════════════════════════════════════════

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
    final tokens =
        Theme.of(context).extension<NotifTokens>() ??
        NotifTokens.build(NotifColorway.dusk1);
    final c = color ?? tokens.ruleStrong;

    return Stack(clipBehavior: Clip.none, children: [child, ..._ticks(c)]);
  }

  List<Widget> _ticks(Color c) {
    const thickness = 1.0;
    return [
      // top-left
      Positioned(left: inset, top: inset, child: _HBar(length, c, thickness)),
      Positioned(left: inset, top: inset, child: _VBar(length, c, thickness)),
      // top-right
      Positioned(right: inset, top: inset, child: _HBar(length, c, thickness)),
      Positioned(right: inset, top: inset, child: _VBar(length, c, thickness)),
      // bottom-left
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
      // bottom-right
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

// ═══════════════════════════════════════════════════════════════
// NotifCard — framed compartment. No elevation, no floating.
// ═══════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════
// NotifButton — primary / ghost / link variants. Rectangular.
// Uppercase labels with mono letter-spacing.
// ═══════════════════════════════════════════════════════════════

enum NotifButtonVariant { primary, ghost, link }

enum NotifButtonSize { sm, md, lg }

class NotifButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final NotifButtonVariant variant;
  final NotifButtonSize size;
  final bool expand;

  const NotifButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = NotifButtonVariant.primary,
    this.size = NotifButtonSize.md,
    this.expand = false,
    super.key,
  });

  double get _height {
    switch (size) {
      case NotifButtonSize.sm:
        return 32;
      case NotifButtonSize.md:
        return 44;
      case NotifButtonSize.lg:
        return 52;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final enabled = onPressed != null;

    final labelStyle = text$.eyebrow.copyWith(letterSpacing: 1.5);

    if (variant == NotifButtonVariant.link) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              label.toUpperCase(),
              style: labelStyle.copyWith(
                color: enabled ? tokens.accent : tokens.inkMute,
              ),
            ),
          ),
        ),
      );
    }

    return _FramedButton(
      label: label,
      icon: icon,
      onPressed: onPressed,
      variant: variant,
      height: _height,
      expand: expand,
      labelStyle: labelStyle,
    );
  }
}

class _FramedButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final NotifButtonVariant variant;
  final double height;
  final bool expand;
  final TextStyle labelStyle;

  const _FramedButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.variant,
    required this.height,
    required this.expand,
    required this.labelStyle,
  });

  @override
  State<_FramedButton> createState() => _FramedButtonState();
}

class _FramedButtonState extends State<_FramedButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final enabled = widget.onPressed != null;

    final _ButtonColors colors = _resolveColors(tokens, enabled);

    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: 18, color: colors.fg),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            widget.label.toUpperCase(),
            overflow: TextOverflow.fade,
            softWrap: false,
            style: widget.labelStyle.copyWith(color: colors.fg),
          ),
        ),
      ],
    );

    Widget frame = AnimatedContainer(
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border.all(color: colors.border, width: 1),
      ),
      alignment: Alignment.center,
      child: FittedBox(fit: BoxFit.scaleDown, child: content),
    );

    if (widget.expand) {
      frame = SizedBox(width: double.infinity, child: frame);
    }

    if (!enabled) {
      return MouseRegion(
        cursor: SystemMouseCursors.forbidden,
        child: frame,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkResponse(
        onTap: widget.onPressed,
        onHover: (hovered) {
          setState(() => _hovered = hovered);
        },
        onHighlightChanged: (pressed) {
          setState(() => _pressed = pressed);
        },
        splashColor: colors.bg == Colors.transparent
            ? tokens.ink.withValues(alpha: 0.08)
            : tokens.accent.withValues(alpha: 0.08),
        highlightColor: colors.bg == Colors.transparent
            ? tokens.ink.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.06),
        child: frame,
      ),
    );
  }

  _ButtonColors _resolveColors(NotifTokens tokens, bool enabled) {
    if (!enabled) {
      return _ButtonColors(
        bg: widget.variant == NotifButtonVariant.ghost
            ? Colors.transparent
            : tokens.ruleStrong,
        fg: tokens.inkMute,
        border: widget.variant == NotifButtonVariant.ghost
            ? tokens.rule
            : tokens.ruleStrong,
      );
    }

    switch (widget.variant) {
      case NotifButtonVariant.primary:
        if (_pressed) {
          return _ButtonColors(
            bg: Color.lerp(tokens.btnBg, Colors.black, 0.12)!,
            fg: tokens.btnInk,
            border: tokens.btnBg,
          );
        }
        if (_hovered) {
          return _ButtonColors(
            bg: tokens.ink,
            fg: tokens.bg1,
            border: tokens.ink,
          );
        }
        return _ButtonColors(
          bg: tokens.btnBg,
          fg: tokens.btnInk,
          border: tokens.btnBg,
        );
      case NotifButtonVariant.ghost:
        if (_pressed) {
          return _ButtonColors(
            bg: tokens.ink.withValues(alpha: 0.08),
            fg: tokens.ink,
            border: tokens.ink,
          );
        }
        if (_hovered) {
          return _ButtonColors(
            bg: tokens.ink.withValues(alpha: 0.04),
            fg: tokens.ink,
            border: tokens.ink,
          );
        }
        return _ButtonColors(
          bg: Colors.transparent,
          fg: tokens.ink,
          border: tokens.ruleStrong,
        );
      case NotifButtonVariant.link:
        throw StateError('Link variant handled outside _FramedButton');
    }
  }
}

class _ButtonColors {
  final Color bg;
  final Color fg;
  final Color border;
  _ButtonColors({required this.bg, required this.fg, required this.border});
}

// ═══════════════════════════════════════════════════════════════
// KV — key/value row with a dashed bottom rule.
// Paper-form aesthetic; non-editable metadata.
// ═══════════════════════════════════════════════════════════════

class KV extends StatelessWidget {
  final String label;
  final Widget value;
  final String? meta;
  final double minLabelWidth;

  const KV({
    required this.label,
    required this.value,
    this.meta,
    this.minLabelWidth = 120,
    super.key,
  });

  /// Convenience constructor for plain-text values.
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
  final String value;
  const _KVText({required this.value});

  @override
  Widget build(BuildContext context) => Text(value);
}

class _DashedRulePainter extends CustomPainter {
  static const double _dashWidth = 4;
  static const double _gap = 3;

  final Color color;

  _DashedRulePainter({required this.color});

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

// ═══════════════════════════════════════════════════════════════
// Tag — micro-mono bordered chip.
// ═══════════════════════════════════════════════════════════════

enum TagTone { defaultTone, accent, muted }

class Tag extends StatelessWidget {
  final String label;
  final TagTone tone;

  const Tag(this.label, {this.tone = TagTone.defaultTone, super.key});

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

// ═══════════════════════════════════════════════════════════════
// StatusDot — small colored dot with a soft pulse ring.
// ═══════════════════════════════════════════════════════════════

enum StatusDotState { live, synced, idle, warning, error }

class StatusDot extends StatelessWidget {
  final StatusDotState state;
  final String? label;

  const StatusDot({this.state = StatusDotState.idle, this.label, super.key});

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
