import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:notif/commons/login_register_fields.dart';
import 'package:notif/services/auth.dart';
import 'package:provider/provider.dart';

class LogInPage extends StatelessWidget {
  const LogInPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool isSmallScreen = MediaQuery.of(context).size.width < 600;
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    return Scaffold(
      body: Center(
          child: isSmallScreen
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Logo(title: "Unused title text?"),
                    _FormContent(formKey: formKey),
                  ],
                )
              : Container(
                  padding: const EdgeInsets.all(32.0),
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Row(
                    children: [
                      const Expanded(child: Logo(title: "Welcome to Notif!")),
                      Expanded(
                        child: Center(child: _FormContent(formKey: formKey)),
                      ),
                    ],
                  ),
                )),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(context, '/About');
        },
        tooltip: 'About',
        backgroundColor: Theme.of(context).primaryColor,
        child: const Icon(Icons.question_mark_rounded),
      ),
    );
  }
}

class _FormContent extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  _FormContent({Key? key, required this.formKey}) : super(key: key);

  String? noValidate(String? password) {
    if (password == null || password.isEmpty) {
      return "Password cannot be empty";
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    bool rememberMe = false;
    final authService = Provider.of<AuthService>(context, listen: true);

    if (authService.jwt != null) {
      Future.delayed(Duration.zero, () {
        Navigator.pushNamed(context, '/Home');
      });
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            UsernameTextField(
              labelText: 'Username',
              hintText: 'Enter your username',
              textController: usernameController,
            ),
            const SizedBox(height: 16),
            PasswordTextField(
              labelText: 'Password',
              hintText: 'Enter your password',
              textController: passwordController,
              validator: noValidate,
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: rememberMe,
              onChanged: (value) {
                if (value == null) return;
                rememberMe = value;
              },
              title: const Text('Remember me'),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              contentPadding: const EdgeInsets.all(0),
            ),
            const SizedBox(height: 16),
            CustomButton(
              buttonText: 'Sign in',
              onPressed: () async {
                if (formKey.currentState?.validate() ?? false) {
                  if (kDebugMode) {
                    print(
                        "Validated data:\n\tusername: ${usernameController.text}, password: ${passwordController.text}");
                  }
                  try {
                    await authService.login(
                        usernameController.text, passwordController.text);
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
              },
            ),
            const SizedBox(height: 16),
            CustomButton(
              buttonText: 'Register',
              buttonColor: Theme.of(context).primaryColorLight,
              onPressed: () {
                Navigator.pushNamed(context, '/Register');
              },
            ),

            // TODO: add logic and/or navigation for password recovery
          ],
        ),
      ),
    );
  }
}
