import 'dart:async';

import 'package:flutter/material.dart';
import 'package:notif/commons/components/button.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';
import 'package:notif/services/auth.dart';
import 'package:provider/provider.dart';

/// Shown whenever auth state is not yet known.
///
/// Two situations reach it, and both are genuinely undecided rather than
/// signed-out: the cold-start probe is in flight, or the server could not be
/// reached to answer one. On web that second case also covers a logout the
/// server never acknowledged — only the server can clear an HttpOnly cookie, so
/// showing a login form there would claim a sign-out that did not happen.
class StartingPage extends StatelessWidget {
  const StartingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NotifTokens>()!;
    final text$ = theme.extension<NotifTextTheme>()!;
    final auth = context.watch<AuthService>();
    final state = auth.state;
    final unavailable = state is AuthUnavailable ? state : null;

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
                if (unavailable == null)
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
                  unavailable == null ? 'RESTORING' : 'BACKEND UNREACHABLE',
                  style: text$.eyebrow.copyWith(color: tokens.inkDim),
                ),
                if (unavailable != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    unavailable.reason,
                    textAlign: TextAlign.center,
                    style: text$.body.copyWith(color: tokens.inkDim),
                  ),
                  const SizedBox(height: 20),
                  NotifButton(
                    label: 'Retry',
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
