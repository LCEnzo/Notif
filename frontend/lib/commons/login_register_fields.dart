import 'package:flutter/material.dart';
import 'dart:math';

class Logo extends StatelessWidget {
  final String title;
  const Logo({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final bool isSmallScreen = MediaQuery.of(context).size.width < 600;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FlutterLogo(size: isSmallScreen ? 100 : 200),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: isSmallScreen
                ? Theme.of(context).textTheme.headlineSmall
                : Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(color: Colors.black),
          ),
        )
      ],
    );
  }
}

class UsernameTextField extends StatefulWidget {
  final String labelText;
  final String hintText;
  final TextEditingController textController;

  const UsernameTextField({
    super.key,
    required this.labelText,
    required this.hintText,
    required this.textController,
  });

  @override
  State<UsernameTextField> createState() => _UsernameTextFieldState();
}

class _UsernameTextFieldState extends State<UsernameTextField> {
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: widget.key,
      controller: widget.textController,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        prefixIcon: const Icon(Icons.account_box_outlined),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class EmailTextField extends StatefulWidget {
  final String labelText;
  final String hintText;
  final String? Function(String?)? validator;
  final TextEditingController textController;

  const EmailTextField(
      {super.key,
      required this.labelText,
      required this.hintText,
      this.validator,
      required this.textController});

  @override
  State<EmailTextField> createState() => _EmailTextFieldState();
}

class _EmailTextFieldState extends State<EmailTextField> {
  late String? Function(String?) validator;

  _EmailTextFieldState();

  @override
  void initState() {
    super.initState();
    validator = widget.validator ?? defaultValidator;
  }

  String? defaultValidator(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter an email address';
    } else if (!RegExp(r"^[a-zA-Z0-9.]+@[a-zA-Z0-9]+\.[a-zA-Z]+")
        .hasMatch(value)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      validator: validator,
      controller: widget.textController,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        prefixIcon: const Icon(Icons.email_outlined),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class PasswordTextField extends StatefulWidget {
  final String labelText;
  final String hintText;
  final String? Function(String?)? validator;
  final TextEditingController textController;

  const PasswordTextField(
      {super.key,
      required this.labelText,
      required this.hintText,
      this.validator,
      required this.textController});

  @override
  State<PasswordTextField> createState() => _PasswordTextFieldState();
}

class _PasswordTextFieldState extends State<PasswordTextField> {
  bool _isPasswordVisible = false;
  late String? Function(String?) validator;

  _PasswordTextFieldState();

  @override
  void initState() {
    super.initState();
    validator = widget.validator ?? EntropyValidator().validate;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.textController,
      validator: validator,
      obscureText: !_isPasswordVisible,
      decoration: InputDecoration(
          labelText: widget.labelText,
          hintText: widget.hintText,
          prefixIcon: const Icon(Icons.lock_outline_rounded),
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: Icon(
                _isPasswordVisible ? Icons.visibility_off : Icons.visibility),
            onPressed: () {
              setState(() {
                _isPasswordVisible = !_isPasswordVisible;
              });
            },
          )),
    );
  }
}

class CustomButton extends StatelessWidget {
  final String buttonText;
  final Function onPressed;
  final Color? buttonColor;

  const CustomButton(
      {super.key,
      required this.buttonText,
      required this.onPressed,
      this.buttonColor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonColor ?? Theme.of(context).colorScheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        onPressed: onPressed as void Function(),
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Text(
            buttonText,
          ),
        ),
      ),
    );
  }
}

class EntropyValidator {
  static const double timeInSeconds =
      100 * 365 * 24 * 60 * 60; // 100 years in seconds
  static const double attemptsPerSecond =
      1e9; // Estimated attempts per second for a consumer CPU
  static final double minEntropy = log(timeInSeconds * attemptsPerSecond) / ln2;

  String? validate(String? password) {
    if (password == null || password.isEmpty) {
      return "Password cannot be empty";
    }

    double passwordEntropy = calculatePasswordEntropy(password);
    if (passwordEntropy < minEntropy) {
      return getHelpText(passwordEntropy: passwordEntropy);
    }

    return null;
  }

  String getHelpText({double? passwordEntropy}) {
    // ignore: prefer_interpolation_to_compose_strings
    return "Use more and different characters. \"S0m3 password!\"";
  }

  double calculatePasswordEntropy(String password) {
    bool hasDigit = password.contains(RegExp(r'\d'));
    bool hasLower = password.contains(RegExp(r'[a-z]'));
    bool hasUpper = password.contains(RegExp(r'[A-Z]'));
    bool hasPunct = password.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'));
    bool hasOther = password.contains(RegExp(r'[^\w\s]'));

    List<bool> categories = [hasDigit, hasLower, hasUpper, hasPunct, hasOther];
    List<int> lengths = [10, 26, 26, 32, 40];
    int charSet = 0;

    for (var i = 0; i < categories.length; i++) {
      if (categories[i]) {
        charSet += lengths[i];
      }
    }

    double passwordEntropy = log(charSet) / ln2 * password.length;

    return passwordEntropy;
  }
}
