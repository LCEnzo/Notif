import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:notif/commons/auth_palette.dart';
import 'package:notif/commons/auth_validators.dart';
import 'package:notif/commons/notif_design_tokens.dart';
import 'package:notif/services/app_settings.dart';
import 'package:provider/provider.dart';

bool _useFramedAuthMode(BuildContext context) {
  return context.watch<AppSettingsController?>()?.authCardStyle ==
      AuthCardStyle.framed;
}

TextStyle _buildAuthFieldTextStyle(BuildContext context) {
  final isFramed = _useFramedAuthMode(context);

  return TextStyle(
    color: isFramed ? NotifDesignTokens.structText : Colors.white,
    fontFamily: isFramed ? NotifDesignTokens.bodyFont : null,
    fontSize: isFramed ? 15 : null,
    height: isFramed ? 22 / 15 : null,
  );
}

InputDecoration _buildAuthInputDecoration({
  required BuildContext context,
  required String labelText,
  required String hintText,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  final isFramed = _useFramedAuthMode(context);

  if (isFramed) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      labelStyle: const TextStyle(
        color: NotifDesignTokens.structText2,
        fontFamily: NotifDesignTokens.bodyFont,
      ),
      floatingLabelStyle: const TextStyle(
        color: NotifDesignTokens.accentText,
        fontFamily: NotifDesignTokens.bodyFont,
      ),
      hintStyle: const TextStyle(
        color: NotifDesignTokens.structText3,
        fontFamily: NotifDesignTokens.bodyFont,
      ),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      prefixIconColor: NotifDesignTokens.structText2,
      suffixIconColor: NotifDesignTokens.structText2,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: NotifDesignTokens.spaceMd,
        vertical: NotifDesignTokens.spaceMd,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: NotifDesignTokens.structBorder),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(
          color: NotifDesignTokens.accentDim,
          width: NotifDesignTokens.borderFocusWidth,
        ),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: FeedbackColors.error),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: FeedbackColors.error, width: 2),
      ),
      disabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: NotifDesignTokens.structDivider),
      ),
    );
  }

  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    labelStyle: const TextStyle(color: Colors.white70),
    hintStyle: const TextStyle(color: Colors.white54),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    prefixIconColor: Colors.white70,
    suffixIconColor: Colors.white70,
    enabledBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: Color(0x40FFFFFF)),
    ),
    focusedBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: Color(0x99FFFFFF), width: 1.4),
    ),
  );
}

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
            style: baseStyle?.copyWith(
              color: textColor ?? colorScheme.onSurface,
            ),
          ),
        ),
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
    final isFramed = _useFramedAuthMode(context);

    return TextFormField(
      key: widget.key,
      controller: widget.textController,
      style: _buildAuthFieldTextStyle(context),
      cursorColor: isFramed ? NotifDesignTokens.accentText : Colors.white,
      decoration: _buildAuthInputDecoration(
        context: context,
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

  const EmailTextField({
    super.key,
    required this.labelText,
    required this.hintText,
    this.validator,
    required this.textController,
  });

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

  @override
  Widget build(BuildContext context) {
    final isFramed = _useFramedAuthMode(context);

    return TextFormField(
      validator: validator,
      controller: widget.textController,
      style: _buildAuthFieldTextStyle(context),
      cursorColor: isFramed ? NotifDesignTokens.accentText : Colors.white,
      decoration: _buildAuthInputDecoration(
        context: context,
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
  late String? Function(String?) validator;

  _PasswordTextFieldState();

  @override
  void initState() {
    super.initState();
    validator = widget.validator ?? EntropyValidator().validate;
  }

  @override
  Widget build(BuildContext context) {
    final isFramed = _useFramedAuthMode(context);

    return TextFormField(
      controller: widget.textController,
      validator: validator,
      obscureText: !_isPasswordVisible,
      style: _buildAuthFieldTextStyle(context),
      cursorColor: isFramed ? NotifDesignTokens.accentText : Colors.white,
      decoration: _buildAuthInputDecoration(
        context: context,
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
    final isFramed = _useFramedAuthMode(context);
    final backgroundColor = buttonColor ?? AuthPalette.primaryButtonBase;
    final isPrimary = buttonColor == null;
    final foregroundColor = isPrimary
        ? AuthPalette.buttonForeground
        : AuthPalette.secondaryButtonForeground;

    if (isFramed) {
      return SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: onPressed,
          style: NotifDesignTokens.framedButtonStyle(isPrimary: isPrimary),
          child: Text(buttonText),
        ),
      );
    }

    final radius = BorderRadius.circular(AuthPalette.glassRadius);

    return SizedBox(
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: AuthPalette.buttonShadow,
              blurRadius: 16,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
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
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 14,
                    ),
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
