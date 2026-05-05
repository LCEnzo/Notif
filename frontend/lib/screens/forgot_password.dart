import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:notif/commons/auth_chrome.dart';
import 'package:notif/commons/auth_palette.dart';
import 'package:notif/commons/auth_validators.dart';
import 'package:notif/commons/login_register_fields.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:notif/services/data.dart';
import 'package:provider/provider.dart';

class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AuthScaffold(child: _ForgotPasswordCard());
  }
}

class _ForgotPasswordCard extends StatefulWidget {
  const _ForgotPasswordCard();

  @override
  State<_ForgotPasswordCard> createState() => _ForgotPasswordCardState();
}

class _ForgotPasswordCardState extends State<_ForgotPasswordCard> {
  final TextEditingController _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFramed =
        context.watch<AppSettingsController?>()?.authCardStyle ==
        AuthCardStyle.framed;
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final authService = context.read<AuthService>();

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: isFramed
            ? AuthPanelWidth.recoveryFramed
            : AuthPanelWidth.glass,
      ),
      child: AuthPanel(
        child: _sent
            ? _buildSuccessState(isFramed, tokens, text$)
            : _buildForm(isFramed, authService),
      ),
    );
  }

  Widget _buildForm(bool isFramed, AuthService authService) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AuthPanelHeader(
            eyebrow: 'Recovery',
            title: 'Forgot password?',
            description: 'Enter your email and we will send you a reset code.',
          ),
          const SizedBox(height: 20),
          AppTextField(
            key: const Key('resetEmailField'),
            labelText: 'Email',
            hintText: 'you@example.com',
            controller: _emailController,
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            enabled: !_isSubmitting,
            validator: validateEmail,
            onFieldSubmitted: (_) => _submit(authService),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(
                color: isFramed ? Colors.red.shade700 : Colors.red.shade300,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 18),
          CustomButton(
            buttonText: 'Send reset code',
            trailingIcon: const Icon(Icons.mail_outline_rounded, size: 16),
            onPressed: () => _submit(authService),
            isLoading: _isSubmitting,
          ),
          const SizedBox(height: 12),
          CustomButton(
            buttonText: 'Back to log in',
            buttonColor: AuthPalette.secondaryButtonBase,
            onPressed: _isSubmitting ? () {} : () => context.go('/login'),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessState(
    bool isFramed,
    NotifTokens tokens,
    NotifTextTheme text$,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AuthPanelHeader(
          eyebrow: 'Recovery',
          title: 'Check your email',
          description:
              'We sent a 6-digit code to your email address. '
              'Enter it on the next screen to reset your password.',
        ),
        const SizedBox(height: 18),
        CustomButton(
          buttonText: 'Enter reset code',
          trailingIcon: const Icon(Icons.arrow_forward_rounded, size: 16),
          onPressed: () {
            final email = _emailController.text.trim();
            context.go('/reset-password?email=${Uri.encodeComponent(email)}');
          },
        ),
        const SizedBox(height: 12),
        CustomButton(
          buttonText: 'Back to log in',
          buttonColor: AuthPalette.secondaryButtonBase,
          onPressed: () => context.go('/login'),
        ),
      ],
    );
  }

  Future<void> _submit(AuthService authService) async {
    if (_isSubmitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await authService.requestPasswordReset(_emailController.text);
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = describeDataError(e));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
