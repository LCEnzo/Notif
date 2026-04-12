import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:notif/commons/auth_background.dart';
import 'package:notif/commons/auth_palette.dart';

class AuthScaffold extends StatelessWidget {
  final Widget child;

  const AuthScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageBackground(
        child: Center(
          child: Padding(padding: const EdgeInsets.all(32), child: child),
        ),
      ),
      floatingActionButton: GlassHelpButton(
        onPressed: () {
          Navigator.pushNamed(context, '/About');
        },
        tooltip: 'About',
        child: const Icon(Icons.question_mark_rounded),
      ),
    );
  }
}

class GlassHelpButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String tooltip;
  final Widget child;

  const GlassHelpButton({
    super.key,
    required this.onPressed,
    required this.tooltip,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AuthPalette.glassRadius);

    return Tooltip(
      message: tooltip,
      child: _AuthGlassSurface(
        borderRadius: radius,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: radius,
            splashColor: Colors.white.withValues(alpha: 0.12),
            child: SizedBox.square(
              dimension: 58,
              child: Center(
                child: IconTheme.merge(
                  data: const IconThemeData(color: AuthPalette.fabIcon),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthPanel extends StatelessWidget {
  final Widget child;

  const AuthPanel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return _AuthGlassSurface(
      borderRadius: BorderRadius.circular(AuthPalette.glassRadius),
      padding: const EdgeInsets.all(28),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: IconTheme.merge(
          data: const IconThemeData(color: Colors.white70),
          child: child,
        ),
      ),
    );
  }
}

class _AuthGlassSurface extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;

  const _AuthGlassSurface({
    required this.child,
    required this.borderRadius,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: const [
          BoxShadow(
            color: AuthPalette.panelShadow,
            blurRadius: AuthPalette.glassShadowBlur,
            offset: Offset(0, AuthPalette.glassShadowOffsetY),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: AuthPalette.glassBlurSigma,
            sigmaY: AuthPalette.glassBlurSigma,
          ),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: AuthPalette.panel.withValues(
                alpha: AuthPalette.panelAlpha,
              ),
              borderRadius: borderRadius,
              border: Border.all(color: AuthPalette.panelBorder),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
