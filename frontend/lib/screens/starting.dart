import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:notif/commons/components/button.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';
import 'package:notif/services/auth.dart';
import 'package:provider/provider.dart';

/// Shown whenever auth state is not yet known.
///
/// Three situations reach it, and all are genuinely undecided rather than
/// signed-out: the cold-start probe is in flight, the server could not be
/// reached to answer one, or the app's own configuration prevents asking. On
/// web the unreachable case also covers a logout the server never acknowledged
/// — only the server can clear an HttpOnly cookie, so showing a login form
/// there would claim a sign-out that did not happen.
///
/// A configuration error gets a settings link, not just Retry: the refusal is
/// computed locally, so retrying without changing settings can never succeed.
class StartingPage extends StatelessWidget {
  const StartingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NotifTokens>()!;
    final text$ = theme.extension<NotifTextTheme>()!;
    final auth = context.watch<AuthService>();
    final state = auth.state;
    final (String headline, String? reason) = switch (state) {
      AuthUnavailable(:final reason) => ('BACKEND UNREACHABLE', reason),
      AuthConfigError(:final reason) => ('BACKEND MISCONFIGURED', reason),
      _ => ('RESTORING', null),
    };
    final isConfigError = state is AuthConfigError;

    return Scaffold(
      backgroundColor: tokens.bg0,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (reason == null)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tokens.accent,
                    ),
                  ),
                const SizedBox(height: 20),
                Text(
                  headline,
                  style: text$.eyebrow.copyWith(color: tokens.inkDim),
                ),
                if (reason != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    reason,
                    textAlign: TextAlign.center,
                    style: text$.body.copyWith(color: tokens.inkDim),
                  ),
                  const SizedBox(height: 20),
                  if (isConfigError) ...[
                    NotifButton(
                      label: 'Open settings',
                      onPressed: () => context.push('/settings'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  NotifButton(
                    label: 'Retry',
                    variant: isConfigError
                        ? NotifButtonVariant.ghost
                        : NotifButtonVariant.primary,
                    onPressed: () => unawaited(auth.retryNow()),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
