import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:notif/commons/auth_chrome.dart';
import 'package:notif/commons/auth_palette.dart';
import 'package:notif/commons/login_register_fields.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:notif/services/data.dart';
import 'package:provider/provider.dart';

class ResetPasswordPage extends StatelessWidget {
  const ResetPasswordPage({super.key, this.email});
  final String? email;

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(child: _ResetPasswordCard(email: email));
  }
}

class _ResetPasswordCard extends StatefulWidget {
  const _ResetPasswordCard({this.email});
  final String? email;

  @override
  State<_ResetPasswordCard> createState() => _ResetPasswordCardState();
}

class _ResetPasswordCardState extends State<_ResetPasswordCard> {
  late final TextEditingController _emailController;
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.email ?? '');
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFramed =
        context.watch<AppSettingsController?>()?.authCardStyle ==
        AuthCardStyle.framed;
    final authService = context.read<AuthService>();

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: isFramed
            ? AuthPanelWidth.recoveryFramed
            : AuthPanelWidth.glass,
      ),
      child: AuthPanel(
        child: _done
            ? _buildSuccessState(isFramed)
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
            title: 'Reset password',
            description:
                'Enter the code from your email and choose a new password.',
          ),
          const SizedBox(height: 20),
          AppTextField(
            key: const Key('resetEmailField'),
            labelText: 'Email',
            hintText: 'you@example.com',
            controller: _emailController,
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            enabled: !_isSubmitting,
          ),
          const SizedBox(height: 16),
          AppTextField(
            key: const Key('resetCodeField'),
            labelText: 'Reset code',
            hintText: '000000',
            controller: _codeController,
            prefixIcon: Icons.pin_outlined,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            enabled: !_isSubmitting,
          ),
          const SizedBox(height: 16),
          PasswordTextField(
            key: const Key('newPasswordField'),
            labelText: 'New password',
            hintText: 'At least 8 characters',
            controller: _passwordController,
            textInputAction: TextInputAction.next,
            enabled: !_isSubmitting,
          ),
          const SizedBox(height: 16),
          PasswordTextField(
            key: const Key('confirmPasswordField'),
            labelText: 'Confirm new password',
            hintText: 'Re-enter your new password',
            controller: _confirmPasswordController,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please confirm your password';
              }
              if (value != _passwordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(authService),
            enabled: !_isSubmitting,
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
            buttonText: 'Reset password',
            trailingIcon: const Icon(Icons.lock_reset_rounded, size: 16),
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

  Widget _buildSuccessState(bool isFramed) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AuthPanelHeader(
          eyebrow: 'Recovery',
          title: 'Password reset!',
          description:
              'Your password has been changed. You can now log in '
              'with your new password.',
        ),
        const SizedBox(height: 18),
        CustomButton(
          buttonText: 'Go to log in',
          trailingIcon: const Icon(Icons.arrow_forward_rounded, size: 16),
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
      await authService.confirmPasswordReset(
        _emailController.text,
        _codeController.text,
        _passwordController.text,
      );
      if (mounted) setState(() => _done = true);
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _error = describeDataError(e));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
