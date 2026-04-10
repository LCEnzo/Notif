import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:notif/commons/auth_background.dart';
import 'package:notif/commons/auth_palette.dart';
import 'package:notif/commons/login_register_fields.dart';
import 'package:notif/services/auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LogInPage extends StatelessWidget {
  const LogInPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageBackground(
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: _FormContent(),
          ),
        ),
      ),
      floatingActionButton: GlassHelpButton(
        onPressed: () {
          Navigator.pushNamed(context, '/About');
        },
        tooltip: 'About',
        child: const Icon(
          Icons.question_mark_rounded,
          color: AuthPalette.fabIcon,
        ),
      ),
    );
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final AuthService authService;
      authService = Provider.of<AuthService>(context, listen: false);
      if (authService.jwt != null) {
        Navigator.pushReplacementNamed(context, '/Home');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final theme = Theme.of(context);
    final rememberMeStyle = theme.textTheme.bodyLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
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
              UsernameTextField(
                key: const Key('usernameField'),
                labelText: 'Username',
                hintText: 'Enter your username',
                textController: usernameController,
              ),
              const SizedBox(height: 16),
              PasswordTextField(
                key: const Key('passwordField'),
                labelText: 'Password',
                hintText: 'Enter your password',
                textController: passwordController,
                validator: noValidate,
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: rememberMe,
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
                    Navigator.pushReplacementNamed(context, '/Home');
                  }
                },
              ),
              const SizedBox(height: 16),
              CustomButton(
                buttonText: 'Register',
                buttonColor: AuthPalette.secondaryButtonBase,
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/Register');
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
        print(
            "Validated data:\n\tusername: ${usernameController.text}, password: ${passwordController.text}");
      }
      try {
        await authService.login(
            usernameController.text, passwordController.text);
        return true;
      } catch (e) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          showDialog<dynamic>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Login Failed'),
              content: Text('$e'),
              actions: [
                TextButton(
                  onPressed: () => {Navigator.pop(context)},
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        });
      }
    }

    return false;
  }

  Future<void> _loadRememberMe() async {
    final perfs = await SharedPreferences.getInstance();
    bool? rememberMe = perfs.getBool('rememberMe');

    if (rememberMe != null) {
      setState(() {
        this.rememberMe = rememberMe;
      });
    }
  }

  Future<void> _saveRememberMe() async {
    final perfs = await SharedPreferences.getInstance();
    perfs.setBool('rememberMe', rememberMe);
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    String? username = prefs.getString('username');

    if (username != null) {
      setState(() {
        usernameController.text = username;
      });
    }
  }

  Future<void> _saveUsername() async {
    final perfs = await SharedPreferences.getInstance();
    perfs.setString('username', usernameController.text);
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
