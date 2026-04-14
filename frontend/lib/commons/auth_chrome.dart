import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:notif/commons/auth_background.dart';
import 'package:notif/commons/auth_palette.dart';
import 'package:notif/commons/notif_design_tokens.dart';
import 'package:notif/services/app_settings.dart';
import 'package:provider/provider.dart';

class AuthScaffold extends StatefulWidget {
  final Widget child;

  const AuthScaffold({super.key, required this.child});

  @override
  State<AuthScaffold> createState() => _AuthScaffoldState();
}

class _AuthScaffoldState extends State<AuthScaffold> {
  @override
  void initState() {
    super.initState();
    // Lock to portrait on phones so the auth card doesn't break in landscape.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final shortestSide = MediaQuery.of(context).size.shortestSide;
      if (shortestSide < 600) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
    });
  }

  @override
  void dispose() {
    // Restore all orientations when leaving auth screens.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: PageBackground(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: widget.child,
                  ),
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: GlassHelpButton(
        onPressed: () {
          context.push('/about');
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
    final appSettings = context.watch<AppSettingsController?>();
    final authCardStyle = appSettings?.authCardStyle ?? AuthCardStyle.glass;
    final isFramed = authCardStyle == AuthCardStyle.framed;
    final radius = BorderRadius.circular(
      isFramed ? NotifDesignTokens.radiusNone : AuthPalette.glassRadius,
    );

    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: radius,
        splashColor: isFramed
            ? NotifDesignTokens.accentText.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.12),
        child: SizedBox.square(
          dimension: 58,
          child: Center(
            child: IconTheme.merge(
              data: IconThemeData(
                color: isFramed
                    ? NotifDesignTokens.accentText
                    : AuthPalette.fabIcon,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );

    return Tooltip(
      message: tooltip,
      child: isFramed
          ? _AuthFramedSurface(padding: EdgeInsets.zero, child: button)
          : _AuthGlassSurface(borderRadius: radius, child: button),
    );
  }
}

class AuthPanel extends StatelessWidget {
  final Widget child;

  const AuthPanel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final appSettings = context.watch<AppSettingsController?>();
    final authCardStyle = appSettings?.authCardStyle ?? AuthCardStyle.glass;

    final content = DefaultTextStyle.merge(
      style: TextStyle(
        color: authCardStyle == AuthCardStyle.glass
            ? Colors.white
            : NotifDesignTokens.structText,
        fontFamily: authCardStyle == AuthCardStyle.glass
            ? null
            : NotifDesignTokens.bodyFont,
        fontSize: authCardStyle == AuthCardStyle.glass ? null : 15,
        height: authCardStyle == AuthCardStyle.glass ? null : 22 / 15,
      ),
      child: IconTheme.merge(
        data: IconThemeData(
          color: authCardStyle == AuthCardStyle.glass
              ? Colors.white70
              : NotifDesignTokens.structText2,
        ),
        child: child,
      ),
    );

    if (authCardStyle == AuthCardStyle.framed) {
      return _AuthFramedSurface(
        padding: const EdgeInsets.all(28),
        child: content,
      );
    }

    return _AuthGlassSurface(
      borderRadius: BorderRadius.circular(AuthPalette.glassRadius),
      padding: const EdgeInsets.all(28),
      child: content,
    );
  }
}

class _AuthFramedSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const _AuthFramedSurface({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: NotifDesignTokens.structSurface,
        border: Border.all(color: NotifDesignTokens.structBorder),
      ),
      child: child,
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
