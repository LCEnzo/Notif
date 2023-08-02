import 'package:flutter/material.dart';
import 'package:notif/commons/login_register_fields.dart';

class RegisterPage extends StatelessWidget {
  const RegisterPage({Key? key}) : super(key: key);

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
                      const Logo(title: "Welcome to Flutter!"),
                      _FormContent(formKey: formKey),
                    ],
                  )
                : Container(
                    padding: const EdgeInsets.all(32.0),
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Row(
                      children: [
                        const Expanded(
                            child: Logo(title: "Welcome to Flutter!")),
                        Expanded(
                          child: Center(child: _FormContent(formKey: formKey)),
                        ),
                      ],
                    ),
                  )));
  }
}

class _FormContent extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController emailController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  _FormContent({Key? key, required this.formKey}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    bool rememberMe = false;

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
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  /// TODO: Handle login logic via auth.dart service
                  print("Validated data:");
                  print("\t- username: ${usernameController.text}");
                  print("\t- email: ${emailController.text}");
                  print("\t- password: ${passwordController.text}");
                }
              },
            ),
            const SizedBox(height: 16),
            CustomButton(
              buttonText: 'Back',
              buttonColor: Colors.blueAccent[100],
              onPressed: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else {
                  Navigator.pushNamed(context, '/LogIn');
                }
              },
            ),

            /// TODO: add logic and/or navigation for password recovery
          ],
        ),
      ),
    );
  }
}
