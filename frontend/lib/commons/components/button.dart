import 'package:flutter/material.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';

enum NotifButtonVariant { primary, ghost, link }

enum NotifButtonSize { sm, md, lg }

class NotifButton extends StatelessWidget {

  const NotifButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = NotifButtonVariant.primary,
    this.size = NotifButtonSize.md,
    this.expand = false,
    super.key,
  });
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final NotifButtonVariant variant;
  final NotifButtonSize size;
  final bool expand;

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

  const _FramedButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.variant,
    required this.height,
    required this.expand,
    required this.labelStyle,
  });
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final NotifButtonVariant variant;
  final double height;
  final bool expand;
  final TextStyle labelStyle;

  @override
  State<_FramedButton> createState() => _FramedButtonState();
}

class _FramedButtonState extends State<_FramedButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  void didUpdateWidget(covariant _FramedButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onPressed == null && oldWidget.onPressed != null) {
      _clearInteraction();
    }
  }

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    setState(() {
      _hovered = hovered;
      if (!hovered) {
        _pressed = false;
      }
    });
  }

  void _setPressed(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  void _clearInteraction() {
    if (!_hovered && !_pressed) return;
    setState(() {
      _hovered = false;
      _pressed = false;
    });
  }

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
      return Semantics(
        button: true,
        enabled: false,
        child: MouseRegion(cursor: SystemMouseCursors.forbidden, child: frame),
      );
    }

    return Semantics(
      button: true,
      enabled: true,
      child: Material(
        color: Colors.transparent,
        child: MouseRegion(
          onExit: (_) => _clearInteraction(),
          child: InkResponse(
            onTap: widget.onPressed,
            onHover: _setHovered,
            onHighlightChanged: _setPressed,
            containedInkWell: true,
            highlightShape: BoxShape.rectangle,
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: frame,
          ),
        ),
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

  _ButtonColors({required this.bg, required this.fg, required this.border});
  final Color bg;
  final Color fg;
  final Color border;
}
