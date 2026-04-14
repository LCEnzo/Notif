import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:notif/commons/auth_chrome.dart';
import 'package:notif/commons/auth_palette.dart';
import 'package:notif/commons/login_register_fields.dart';
import 'package:notif/commons/notif_design_tokens.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  bool rememberMe = false;

  @override
  void initState() {
    super.initState();

    _loadUsername();
    _loadRememberMe();
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final appSettings = context.watch<AppSettingsController?>();
    final isFramed = appSettings?.authCardStyle == AuthCardStyle.framed;
    final theme = Theme.of(context);
    final rememberMeStyle = theme.textTheme.bodyLarge?.copyWith(
      color: isFramed ? NotifDesignTokens.structText2 : Colors.white70,
      fontFamily: isFramed ? NotifDesignTokens.bodyFont : null,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 330),
      child: AuthPanel(
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
              ),
              const SizedBox(height: 16),
              PasswordTextField(
                key: const Key('passwordField'),
                labelText: 'Password',
                hintText: 'Enter your password',
                controller: passwordController,
                validator: noValidate,
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: rememberMe,
                side: isFramed
                    ? const BorderSide(color: NotifDesignTokens.structBorder)
                    : null,
                checkboxShape: isFramed
                    ? const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      )
                    : null,
                fillColor: isFramed
                    ? WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return NotifDesignTokens.accentPrimary;
                        }
                        return Colors.transparent;
                      })
                    : null,
                checkColor: isFramed ? NotifDesignTokens.accentOnAccent : null,
                onChanged: (value) {
                  setState(() {
                    if (value == null) return;
                    rememberMe = value;
                    _saveRememberMe();
                  });
                },
                title: Text('Remember me', style: rememberMeStyle),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                contentPadding: const EdgeInsets.all(0),
              ),
              const SizedBox(height: 16),
              CustomButton(
                buttonText: 'Log in',
                onPressed: () async {
                  if (rememberMe) {
                    _saveUsername();
                  }

                  bool loggedIn = await loginClick(authService, context);
                  if (loggedIn && context.mounted) {
                    context.go('/home');
                  }
                },
              ),
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
    );
  }

  Future<bool> loginClick(AuthService authService, BuildContext context) async {
    if (formKey.currentState?.validate() ?? false) {
      if (kDebugMode) {
        final pw = passwordController.text;
        final masked = pw.length >= 2
            ? '${pw[0]}***${pw[pw.length - 1]}'
            : pw.isNotEmpty ? '***' : '(empty)';
        debugPrint("Validated data:\n\tusername: ${usernameController.text}, password: $masked");
      }
      try {
        await authService.login(
          usernameController.text,
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

  Future<void> _loadRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    bool? rememberMe = prefs.getBool('rememberMe');

    if (rememberMe != null && mounted) {
      setState(() {
        this.rememberMe = rememberMe;
      });
    }
  }

  Future<void> _saveRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('rememberMe', rememberMe);
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    String? username = prefs.getString('username');

    if (username != null && mounted) {
      setState(() {
        usernameController.text = username;
      });
    }
  }

  Future<void> _saveUsername() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('username', usernameController.text);
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
