import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:notif/commons/auth_chrome.dart';
import 'package:notif/commons/auth_palette.dart';
import 'package:notif/commons/login_register_fields.dart';
import 'package:notif/services/auth.dart';
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
  _FormContentState createState() => _FormContentState();
}

class _FormContentState extends State<_FormContent> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();

    _loadUsername();
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
                  key: const Key('usernameField'),
                  labelText: 'Username',
                  hintText: 'Enter your username',
                  controller: usernameController,
                  prefixIcon: Icons.account_box_outlined,
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
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
                ),
                const SizedBox(height: 16),
                CustomButton(
                  buttonText: 'Log in',
                  onPressed: () => _submitLogin(authService),
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 16),
                  CustomButton(
                    buttonText: 'Debug login',
                    buttonColor: const Color(0x805E4A92),
                    onPressed: () => _submitDebugLogin(authService),
                  ),
                ],
                const SizedBox(height: 16),
                CustomButton(
                  buttonText: 'Register',
                  buttonColor: AuthPalette.secondaryButtonBase,
                  onPressed: () {
                    context.go('/register');
                  },
                ),

                // TODO: add logic and/or navigation for password recovery
              ],
            ),
          ),
        ),
      ),
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
            showDialog<dynamic>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Login Failed'),
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
      return "Password cannot be empty";
    }

    return null;
  }
}
