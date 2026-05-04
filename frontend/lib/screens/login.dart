import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:notif/commons/auth_chrome.dart';
import 'package:notif/commons/auth_palette.dart';
import 'package:notif/commons/login_register_fields.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:notif/services/data.dart';
import 'package:provider/provider.dart';

const _debugLoginUsername = String.fromEnvironment(
  'DEV_LOGIN_USERNAME',
  defaultValue: 'LCEnzo',
);
const _debugLoginPassword = String.fromEnvironment(
  'DEV_LOGIN_PASSWORD',
  defaultValue: '1ukacolic',
);

class LogInPage extends StatelessWidget {
  const LogInPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AuthScaffold(child: _FormContent());
  }
}

class _FormContent extends StatefulWidget {
  const _FormContent();

  @override
  State<_FormContent> createState() => _FormContentState();
}

class _FormContentState extends State<_FormContent> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.read<AuthService>();
    final isFramed =
        context.watch<AppSettingsController?>()?.authCardStyle ==
        AuthCardStyle.framed;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: isFramed
            ? AuthPanelWidth.loginFramed
            : AuthPanelWidth.glass,
      ),
      child: AuthPanel(
        child: AutofillGroup(
          child: Form(
            key: formKey,
            child: isFramed
                ? _buildFramedForm(authService)
                : _buildGlassForm(authService),
          ),
        ),
      ),
    );
  }

  Widget _buildFramedForm(AuthService authService) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          key: const Key('usernameField'),
          labelText: 'Username',
          hintText: 'Enter your username',
          controller: usernameController,
          prefixIcon: Icons.account_box_outlined,
          autofillHints: const [AutofillHints.username],
          textInputAction: TextInputAction.next,
          autocorrect: false,
          enabled: !_isSubmitting,
        ),
        const SizedBox(height: 16),
        PasswordTextField(
          key: const Key('passwordField'),
          labelText: 'Password',
          hintText: 'Enter your password',
          controller: passwordController,
          validator: noValidate,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submitLogin(authService),
          enabled: !_isSubmitting,
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: AuthInlineAction(
            label: 'Forgot password?',
            onPressed:
                _isSubmitting ? () {} : () => context.go('/forgot-password'),
          ),
        ),
        const SizedBox(height: 18),
        CustomButton(
          buttonText: 'Log in',
          trailingIcon: const Icon(Icons.arrow_forward_rounded, size: 16),
          onPressed: () => _submitLogin(authService),
          isLoading: _isSubmitting,
        ),
        if (kDebugMode) ...[
          const SizedBox(height: 12),
          CustomButton(
            buttonText: 'Debug login',
            buttonColor: AuthPalette.secondaryButtonBase,
            onPressed: () => _submitDebugLogin(authService),
            isLoading: _isSubmitting,
          ),
        ],
        const SizedBox(height: 12),
        const AuthRuleDivider(),
        const SizedBox(height: 12),
        CustomButton(
          key: const Key('loginRegisterButton'),
          buttonText: 'Create account',
          buttonColor: AuthPalette.secondaryButtonBase,
          onPressed:
              _isSubmitting ? () {} : () => context.go('/register'),
        ),
      ],
    );
  }

  Widget _buildGlassForm(AuthService authService) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AppTextField(
          key: const Key('usernameField'),
          labelText: 'Username',
          hintText: 'Enter your username',
          controller: usernameController,
          prefixIcon: Icons.account_box_outlined,
          autofillHints: const [AutofillHints.username],
          textInputAction: TextInputAction.next,
          autocorrect: false,
          enabled: !_isSubmitting,
        ),
        const SizedBox(height: 16),
        PasswordTextField(
          key: const Key('passwordField'),
          labelText: 'Password',
          hintText: 'Enter your password',
          controller: passwordController,
          validator: noValidate,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submitLogin(authService),
          enabled: !_isSubmitting,
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: AuthInlineAction(
            label: 'Forgot password?',
            onPressed:
                _isSubmitting ? () {} : () => context.go('/forgot-password'),
          ),
        ),
        const SizedBox(height: 16),
        CustomButton(
          buttonText: 'Log in',
          onPressed: () => _submitLogin(authService),
          isLoading: _isSubmitting,
        ),
        if (kDebugMode) ...[
          const SizedBox(height: 16),
          CustomButton(
            buttonText: 'Debug login',
            buttonColor: const Color(0x805E4A92),
            onPressed: () => _submitDebugLogin(authService),
            isLoading: _isSubmitting,
          ),
        ],
        const SizedBox(height: 16),
        CustomButton(
          key: const Key('loginRegisterButton'),
          buttonText: 'Create account',
          buttonColor: AuthPalette.secondaryButtonBase,
          onPressed:
              _isSubmitting ? () {} : () => context.go('/register'),
        ),
      ],
    );
  }

  Future<void> _submitLogin(AuthService authService) async {
    final loggedIn = await loginClick(authService, context);
    if (!mounted || !loggedIn) {
      return;
    }
    TextInput.finishAutofillContext(shouldSave: true);
    context.go('/home');
  }

  Future<void> _submitDebugLogin(AuthService authService) async {
    usernameController.text = _debugLoginUsername;
    passwordController.text = _debugLoginPassword;
    await _submitLogin(authService);
  }

  Future<bool> loginClick(AuthService authService, BuildContext context) async {
    if (formKey.currentState?.validate() ?? false) {
      if (kDebugMode) {
        final pw = passwordController.text;
        final masked = pw.length >= 2
            ? '${pw[0]}***${pw[pw.length - 1]}'
            : pw.isNotEmpty
            ? '***'
            : '(empty)';
        debugPrint(
          "Validated data:\n\tusername: ${usernameController.text}, password: $masked",
        );
      }
      setState(() => _isSubmitting = true);
      try {
        await authService.login(
          usernameController.text.trim(),
          passwordController.text,
        );
        return true;
      } catch (e) {
        if (context.mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            showAuthFailureDialog(
              context,
              title: 'Login failed',
              message: describeDataError(e),
            );
          });
        }
      } finally {
        if (mounted) setState(() => _isSubmitting = false);
      }
    }

    return false;
  }

  Future<void> _loadUsername() async {
    final username = await loadLastSuccessfulUsername();

    if (username != null && mounted) {
      setState(() {
        usernameController.text = username;
      });
    }
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  String? noValidate(String? password) {
    if (password == null || password.isEmpty) {
      return 'Password cannot be empty';
    }

    return null;
  }
}
