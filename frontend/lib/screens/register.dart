import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:notif/commons/auth_palette.dart';
import 'package:notif/commons/login_register_fields.dart';
import 'package:notif/services/auth.dart';
import 'package:provider/provider.dart';

class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});

  @override
  Widget build(BuildContext context) {
    const String appTitle = "Welcome to Notif!";
    final bool isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      body: PageBackground(
        child: Center(
          child: isSmallScreen
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Logo(
                      title: appTitle,
                      textColor: AuthPalette.logoText,
                    ),
                    _FormContent(),
                  ],
                )
              : Container(
                  padding: const EdgeInsets.all(32.0),
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Row(
                    children: [
                      Expanded(
                        child: Logo(
                          title: appTitle,
                          textColor: AuthPalette.logoText,
                        ),
                      ),
                      Expanded(
                        child: Center(child: _FormContent()),
                      ),
                    ],
                  ),
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
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

class _FormContent extends StatelessWidget {
  final formKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  _FormContent();

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
      constraints: const BoxConstraints(maxWidth: 300),
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
                      await authService.register(usernameController.text,
                          emailController.text, passwordController.text);
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
                buttonColor: Theme.of(context).colorScheme.primaryContainer,
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
