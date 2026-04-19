import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:notif/commons/auth_background.dart';
import 'package:notif/commons/auth_palette.dart';
import 'package:notif/commons/components/primitives.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';
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
    final appSettings = context.watch<AppSettingsController?>();
    final authCardStyle = appSettings?.authCardStyle ?? AuthCardStyle.glass;
    final isFramed = authCardStyle == AuthCardStyle.framed;
    final tokens =
        Theme.of(context).extension<NotifTokens>() ??
        NotifTokens.build(NotifColorway.dusk1);
    final radius = isFramed
        ? BorderRadius.zero
        : BorderRadius.circular(AuthPalette.glassRadius);

    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: radius,
        splashColor: isFramed
            ? tokens.accent.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.12),
        child: SizedBox.square(
          dimension: 58,
          child: Center(
            child: IconTheme.merge(
              data: IconThemeData(
                color: isFramed ? tokens.accent : AuthPalette.fabIcon,
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
    final isFramed = authCardStyle == AuthCardStyle.framed;
    final tokens =
        Theme.of(context).extension<NotifTokens>() ??
        NotifTokens.build(NotifColorway.dusk1);
    final text$ =
        Theme.of(context).extension<NotifTextTheme>() ??
        NotifTextTheme.forSet(NotifFontSet.current);

    final content = DefaultTextStyle.merge(
      style: isFramed
          ? text$.body.copyWith(color: tokens.ink)
          : const TextStyle(color: Colors.white),
      child: IconTheme.merge(
        data: IconThemeData(
          color: isFramed ? tokens.inkDim : Colors.white70,
        ),
        child: child,
      ),
    );

    if (isFramed) {
      return CornerMarks(
        child: _AuthFramedSurface(
          padding: const EdgeInsets.all(28),
          child: content,
        ),
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
    final tokens =
        Theme.of(context).extension<NotifTokens>() ??
        NotifTokens.build(NotifColorway.dusk1);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tokens.bg1,
        border: Border.all(color: tokens.ruleStrong),
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

Future<void> showAuthFailureDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  final tokens =
      Theme.of(context).extension<NotifTokens>() ??
      NotifTokens.build(NotifColorway.dusk1);
  final text$ =
      Theme.of(context).extension<NotifTextTheme>() ??
      NotifTextTheme.forSet(NotifFontSet.current);
  final messenger = ScaffoldMessenger.of(context);

  ButtonStyle actionStyle({
    required Color foreground,
    required Color background,
    required Color border,
  }) {
    return TextButton.styleFrom(
      foregroundColor: foreground,
      backgroundColor: background,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      minimumSize: const Size(0, 44),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      side: BorderSide(color: border, width: 1),
      textStyle: text$.eyebrow.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }

  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: NotifCard(
            cornerMarks: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text$.title.copyWith(
                    color: tokens.ink,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Request details',
                  style: text$.eyebrow.copyWith(color: tokens.accent),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: tokens.bg1,
                    border: Border.all(color: tokens.rule, width: 1),
                  ),
                  child: SelectionArea(
                    child: SelectableText(
                      message,
                      style: text$.code.copyWith(color: tokens.inkDim),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: '$title\n$message'),
                          );
                          messenger
                            ..clearSnackBars()
                            ..showSnackBar(
                              SnackBar(
                                content: const Text('Copied auth error.'),
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: tokens.bg3,
                              ),
                            );
                        },
                        style: actionStyle(
                          foreground: tokens.accent,
                          background: Colors.transparent,
                          border: tokens.rule,
                        ),
                        icon: const Icon(Icons.content_copy_rounded, size: 18),
                        label: const Text('COPY'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        style: actionStyle(
                          foreground: tokens.btnInk,
                          background: tokens.btnBg,
                          border: tokens.btnBg,
                        ),
                        child: const Text('OK'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
