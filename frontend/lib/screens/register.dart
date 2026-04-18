import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:notif/commons/auth_chrome.dart';
import 'package:notif/commons/auth_palette.dart';
import 'package:notif/commons/auth_validators.dart';
import 'package:notif/commons/login_register_fields.dart';
import 'package:notif/services/auth.dart';
import 'package:provider/provider.dart';

class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});

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
  final formKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    emailController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 330),
      child: AuthPanel(
        child: AutofillGroup(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppTextField(
                  labelText: 'Username',
                  hintText: 'Enter your username',
                  controller: usernameController,
                  prefixIcon: Icons.account_box_outlined,
                  autofillHints: const [AutofillHints.newUsername],
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  labelText: 'Email',
                  hintText: 'Enter your email',
                  controller: emailController,
                  prefixIcon: Icons.email_outlined,
                  validator: validateEmail,
                  autofillHints: const [AutofillHints.email],
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                ),
                const SizedBox(height: 16),
                PasswordTextField(
                  labelText: 'Password',
                  hintText: 'Enter your password',
                  controller: passwordController,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submitRegister(authService),
                ),
                const SizedBox(height: 16),
                CustomButton(
                  buttonText: 'Register',
                  onPressed: () => _submitRegister(authService),
                ),
                const SizedBox(height: 16),
                CustomButton(
                  buttonText: 'Back',
                  buttonColor: AuthPalette.secondaryButtonBase,
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/login');
                    }
                  },
                ),

                /// TODO: add logic and/or navigation for password recovery
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submitRegister(AuthService authService) async {
    if (!(formKey.currentState?.validate() ?? false)) {
      return;
    }

    if (kDebugMode) {
      final pw = passwordController.text;
      final masked = pw.length >= 2
          ? '${pw[0]}***${pw[pw.length - 1]}'
          : pw.isNotEmpty
          ? '***'
          : '(empty)';
      debugPrint("Validated data:");
      debugPrint("\t- username: ${usernameController.text}");
      debugPrint("\t- email: ${emailController.text}");
      debugPrint("\t- password: $masked");
    }

    try {
      await authService.register(
        usernameController.text.trim(),
        emailController.text.trim(),
        passwordController.text,
      );
      if (mounted) {
        TextInput.finishAutofillContext(shouldSave: true);
      }
    } catch (e) {
      if (context.mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          showDialog<dynamic>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Register Failed'),
              content: Text('$e'),
              actions: [
                TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        });
      }
    }
  }
}
