import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:notif/commons/auth_chrome.dart';
import 'package:notif/commons/auth_palette.dart';
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
  void dispose() {
    emailController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: true);

    if (authService.jwt != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.pushReplacementNamed(context, '/Home');
        }
      });
    }

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
                labelText: 'Username',
                hintText: 'Enter your username',
                textController: usernameController,
              ),
              const SizedBox(height: 16),
              EmailTextField(
                labelText: 'Email',
                hintText: 'Enter your email',
                textController: emailController,
              ),
              const SizedBox(height: 16),
              PasswordTextField(
                labelText: 'Password',
                hintText: 'Enter your password',
                textController: passwordController,
              ),
              const SizedBox(height: 16),
              CustomButton(
                buttonText: 'Register',
                onPressed: () async {
                  if (formKey.currentState?.validate() ?? false) {
                    if (kDebugMode) {
                      print("Validated data:");
                      print("\t- username: ${usernameController.text}");
                      print("\t- email: ${emailController.text}");
                      print("\t- password: ${passwordController.text}");
                    }

                    try {
                      await authService.register(
                        usernameController.text,
                        emailController.text,
                        passwordController.text,
                      );
                    } catch (e) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        showDialog<dynamic>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Register Failed'),
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
                buttonText: 'Back',
                buttonColor: AuthPalette.secondaryButtonBase,
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  } else {
                    Navigator.pushReplacementNamed(context, '/LogIn');
                  }
                },
              ),

              /// TODO: add logic and/or navigation for password recovery
            ],
          ),
        ),
      ),
    );
  }
}
