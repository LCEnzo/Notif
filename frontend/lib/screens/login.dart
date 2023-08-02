import 'package:flutter/material.dart';
import 'package:notif/commons/login_register_fields.dart';

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
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  /// TODO: Handle login logic via auth.dart service
                  print(
                      "Validated data:\n\temail: ${emailController.text}, password: ${passwordController.text}");
                }
              },
            ),
            const SizedBox(height: 16),
            CustomButton(
              buttonText: 'Register',
              buttonColor: Colors.blueAccent[100],
              onPressed: () {
                Navigator.pushNamed(context, '/Register');
              },
            ),

            /// TODO: add logic and/or navigation for password recovery
          ],
        ),
      ),
    );
  }
}
