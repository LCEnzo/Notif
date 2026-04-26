import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:notif/commons/auth_chrome.dart';
import 'package:notif/commons/auth_palette.dart';
import 'package:notif/commons/login_register_fields.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';
import 'package:notif/services/app_settings.dart';
import 'package:provider/provider.dart';

class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AuthScaffold(child: _ForgotPasswordCard());
  }
}

class _ForgotPasswordCard extends StatelessWidget {
  const _ForgotPasswordCard();

  @override
  Widget build(BuildContext context) {
    final isFramed =
        context.watch<AppSettingsController?>()?.authCardStyle ==
        AuthCardStyle.framed;
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: AuthPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AuthPanelHeader(
              eyebrow: 'Recovery',
              title: 'Forgot the passphrase?',
              description:
                  'Password reset is not wired up in this build yet.',
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isFramed
                    ? tokens.bg0
                    : AuthPalette.panel.withValues(alpha: 0.12),
                border: Border.all(
                  color: isFramed ? tokens.ruleStrong : AuthPalette.panelBorder,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'What works right now',
                    style: (isFramed
                            ? text$.body.copyWith(color: tokens.ink)
                            : (Theme.of(context).textTheme.titleMedium ??
                                    const TextStyle(
                                      fontSize: 16,
                                      height: 20 / 16,
                                    ))
                                .copyWith(color: Colors.white))
                        .copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'If you self-host this build, recover the account on the '
                    'server or create a new one here.',
                    style: isFramed
                        ? text$.body.copyWith(color: tokens.inkDim)
                        : const TextStyle(color: Colors.white70, height: 20 / 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            CustomButton(
              buttonText: 'Back to log in',
              onPressed: () => context.go('/login'),
            ),
            const SizedBox(height: 12),
            CustomButton(
              buttonText: 'Create account',
              buttonColor: AuthPalette.secondaryButtonBase,
              onPressed: () => context.go('/register'),
            ),
          ],
        ),
      ),
    );
  }
}
