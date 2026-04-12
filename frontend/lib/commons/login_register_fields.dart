import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:notif/commons/auth_palette.dart';
import 'package:notif/commons/auth_validators.dart';

class Logo extends StatelessWidget {
  final String title;
  final Color? textColor;

  const Logo({super.key, required this.title, this.textColor});

  @override
  Widget build(BuildContext context) {
    final bool isSmallScreen = MediaQuery.of(context).size.width < 600;
    final colorScheme = Theme.of(context).colorScheme;
    final baseStyle = isSmallScreen
        ? Theme.of(context).textTheme.headlineSmall
        : Theme.of(context).textTheme.headlineMedium;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FlutterLogo(size: isSmallScreen ? 100 : 200),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style:
                baseStyle?.copyWith(color: textColor ?? colorScheme.onSurface),
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
    validator = widget.validator ?? validateEmail;
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
    final backgroundColor = buttonColor ?? AuthPalette.primaryButtonBase;
    final isPrimary = buttonColor == null;
    final foregroundColor = isPrimary
        ? AuthPalette.buttonForeground
        : AuthPalette.secondaryButtonForeground;

    final radius = BorderRadius.circular(4);

    return SizedBox(
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: AuthPalette.buttonShadow,
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: radius,
                border: Border.all(color: AuthPalette.buttonBorder),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onPressed as void Function(),
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Center(
                      child: Text(
                        buttonText,
                        style: TextStyle(
                          color: foregroundColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
