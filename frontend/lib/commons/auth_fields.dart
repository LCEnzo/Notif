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
    final isSmallScreen = MediaQuery.of(context).size.width < 600;
    final colorScheme = Theme.of(context).colorScheme;
    final baseStyle = isSmallScreen
        ? Theme.of(context).textTheme.headlineSmall
        : Theme.of(context).textTheme.headlineMedium;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FlutterLogo(size: isSmallScreen ? 100 : 200),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: baseStyle?.copyWith(
              color: textColor ?? colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

class UsernameTextField extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return TextFormField(
      key: key,
      controller: textController,
      decoration: _buildInputDecoration(
        labelText: labelText,
        hintText: hintText,
        prefixIcon: const Icon(Icons.account_box_outlined),
      ),
    );
  }
}

class EmailTextField extends StatelessWidget {
  final String labelText;
  final String hintText;
  final String? Function(String?)? validator;
  final TextEditingController textController;

  const EmailTextField({
    super.key,
    required this.labelText,
    required this.hintText,
    this.validator,
    required this.textController,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: textController,
      validator: validator ?? validateEmail,
      decoration: _buildInputDecoration(
        labelText: labelText,
        hintText: hintText,
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

  const PasswordTextField({
    super.key,
    required this.labelText,
    required this.hintText,
    this.validator,
    required this.textController,
  });

  @override
  State<PasswordTextField> createState() => _PasswordTextFieldState();
}

class _PasswordTextFieldState extends State<PasswordTextField> {
  bool _isPasswordVisible = false;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.textController,
      validator: widget.validator ?? const EntropyValidator().validate,
      obscureText: !_isPasswordVisible,
      decoration: _buildInputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          icon: Icon(
            _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
          ),
          onPressed: () {
            setState(() {
              _isPasswordVisible = !_isPasswordVisible;
            });
          },
        ),
      ),
    );
  }
}

class CustomButton extends StatelessWidget {
  final String buttonText;
  final VoidCallback onPressed;
  final Color? buttonColor;

  const CustomButton({
    super.key,
    required this.buttonText,
    required this.onPressed,
    this.buttonColor,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor = buttonColor ?? AuthPalette.primaryButtonBase;
    final foregroundColor = buttonColor == null
        ? AuthPalette.buttonForeground
        : AuthPalette.secondaryButtonForeground;
    final radius = BorderRadius.circular(4);

    return SizedBox(
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: const [
            BoxShadow(
              color: AuthPalette.buttonShadow,
              blurRadius: 10,
              offset: Offset(0, 6),
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
                  onTap: onPressed,
                  borderRadius: radius,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
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

InputDecoration _buildInputDecoration({
  required String labelText,
  required String hintText,
  required Widget prefixIcon,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
  );
}
