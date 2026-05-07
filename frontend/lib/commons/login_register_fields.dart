import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:notif/commons/auth_palette.dart';
import 'package:notif/commons/auth_validators.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';
import 'package:notif/services/app_settings.dart';
import 'package:provider/provider.dart';

bool _useFramedAuthMode(BuildContext context) {
  return context.watch<AppSettingsController?>()?.authCardStyle ==
      AuthCardStyle.framed;
}

NotifTokens _authTokens(BuildContext context) {
  return NotifTokens.of(context);
}

NotifTextTheme _authTextTheme(BuildContext context) {
  return NotifTextTheme.of(context);
}

TextStyle _buildAuthFieldTextStyle(BuildContext context) {
  if (_useFramedAuthMode(context)) {
    final tokens = _authTokens(context);
    final text$ = _authTextTheme(context);
    return text$.body.copyWith(color: tokens.ink);
  }

  return const TextStyle(color: Colors.white);
}

InputDecoration _buildAuthInputDecoration({
  required BuildContext context,
  required String labelText,
  required String hintText,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  if (_useFramedAuthMode(context)) {
    final tokens = _authTokens(context);
    final text$ = _authTextTheme(context);

    return InputDecoration(
      labelText: labelText.isEmpty ? null : labelText,
      hintText: hintText.isEmpty ? null : hintText,
      labelStyle: text$.body.copyWith(color: tokens.inkDim),
      hintStyle: text$.body.copyWith(color: tokens.inkMute),
      floatingLabelStyle: text$.body.copyWith(color: tokens.accent),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      prefixIconColor: tokens.inkDim,
      suffixIconColor: tokens.inkDim,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      filled: true,
      fillColor: tokens.bg0,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: tokens.rule),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: tokens.accent, width: 2),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: NotifFeedback.error),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: NotifFeedback.error, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: tokens.rule),
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

class AuthPanelHeader extends StatelessWidget {

  const AuthPanelHeader({
    super.key,
    required this.title,
    required this.eyebrow,
    this.description,
  });
  final String title;
  final String eyebrow;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final isFramed = _useFramedAuthMode(context);

    if (!isFramed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: 8),
            Text(description!, style: const TextStyle(color: Colors.white70)),
          ],
        ],
      );
    }

    final tokens = _authTokens(context);
    final text$ = _authTextTheme(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: text$.eyebrow.copyWith(color: tokens.accent),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: text$.title.copyWith(
            color: tokens.ink,
            fontStyle: FontStyle.italic,
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: 8),
          Text(description!, style: text$.body.copyWith(color: tokens.inkDim)),
        ],
      ],
    );
  }
}

class AuthInlineAction extends StatelessWidget {

  const AuthInlineAction({
    super.key,
    required this.label,
    required this.onPressed,
  });
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isFramed = _useFramedAuthMode(context);

    if (!isFramed) {
      return TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white70,
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: Text(label),
      );
    }

    final tokens = _authTokens(context);
    final text$ = _authTextTheme(context);

    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: tokens.accent,
        textStyle: text$.eyebrow,
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: Text(label.toUpperCase()),
    );
  }
}

class AuthRuleDivider extends StatelessWidget {

  const AuthRuleDivider({super.key, this.label = 'or'});
  final String label;

  @override
  Widget build(BuildContext context) {
    if (!_useFramedAuthMode(context)) {
      return Row(
        children: [
          const Expanded(child: Divider(color: Colors.white24)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(label, style: const TextStyle(color: Colors.white54)),
          ),
          const Expanded(child: Divider(color: Colors.white24)),
        ],
      );
    }

    final tokens = _authTokens(context);
    final text$ = _authTextTheme(context);

    return Row(
      children: [
        Expanded(child: Divider(color: tokens.rule, thickness: 1, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label.toUpperCase(),
            style: text$.eyebrow.copyWith(color: tokens.inkMute),
          ),
        ),
        Expanded(child: Divider(color: tokens.rule, thickness: 1, height: 1)),
      ],
    );
  }
}

class Logo extends StatelessWidget {

  const Logo({super.key, required this.title, this.textColor});
  final String title;
  final Color? textColor;

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

class AppTextField extends StatelessWidget {

  const AppTextField({
    super.key,
    required this.labelText,
    required this.hintText,
    required this.controller,
    required this.prefixIcon,
    this.validator,
    this.obscureText = false,
    this.suffixIcon,
    this.autofillHints,
    this.textInputAction,
    this.keyboardType,
    this.onFieldSubmitted,
    this.enableSuggestions = true,
    this.autocorrect = true,
    this.enabled = true,
  });
  final String labelText;
  final String hintText;
  final TextEditingController controller;
  final IconData prefixIcon;
  final String? Function(String?)? validator;
  final bool obscureText;
  final Widget? suffixIcon;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onFieldSubmitted;
  final bool enableSuggestions;
  final bool autocorrect;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      obscureText: obscureText,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      keyboardType: keyboardType,
      onFieldSubmitted: onFieldSubmitted,
      enableSuggestions: enableSuggestions,
      autocorrect: autocorrect,
      enabled: enabled,
      style: _buildAuthFieldTextStyle(context),
      cursorColor: _cursorColor(context),
      decoration: _buildAuthInputDecoration(
        context: context,
        labelText: labelText,
        hintText: hintText,
        prefixIcon: Icon(prefixIcon),
        suffixIcon: suffixIcon,
      ),
    );
  }
}

class PasswordTextField extends StatefulWidget {

  const PasswordTextField({
    super.key,
    required this.labelText,
    required this.hintText,
    this.validator,
    required this.controller,
    this.autofillHints,
    this.textInputAction,
    this.onFieldSubmitted,
    this.enabled = true,
  });
  final String labelText;
  final String hintText;
  final String? Function(String?)? validator;
  final TextEditingController controller;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final bool enabled;

  @override
  State<PasswordTextField> createState() => _PasswordTextFieldState();
}

class _PasswordTextFieldState extends State<PasswordTextField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      labelText: widget.labelText,
      hintText: widget.hintText,
      controller: widget.controller,
      prefixIcon: Icons.lock_outline_rounded,
      validator: widget.validator ?? const EntropyValidator().validate,
      obscureText: !_visible,
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onFieldSubmitted,
      enableSuggestions: false,
      autocorrect: false,
      enabled: widget.enabled,
      suffixIcon: IconButton(
        icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
        onPressed: () => setState(() => _visible = !_visible),
      ),
    );
  }
}

Color _cursorColor(BuildContext context) {
  if (!_useFramedAuthMode(context)) return Colors.white;
  return _authTokens(context).accent;
}

class CustomButton extends StatelessWidget {

  const CustomButton({
    super.key,
    required this.buttonText,
    required this.onPressed,
    this.buttonColor,
    this.trailingIcon,
    this.isLoading = false,
  });
  final String buttonText;
  final VoidCallback onPressed;
  final Color? buttonColor;
  final Widget? trailingIcon;
  final bool isLoading;

  static const _submitDuration = Duration(milliseconds: 110);

  Widget _buttonChild(Color spinnerColor) {
    return AnimatedSwitcher(
      duration: _submitDuration,
      child: isLoading
          ? SizedBox(
              key: const ValueKey('auth-submit-loading'),
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(spinnerColor),
              ),
            )
          : Row(
              key: const ValueKey('auth-submit-label'),
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(buttonText),
                if (trailingIcon != null) ...[
                  const SizedBox(width: 8),
                  trailingIcon!,
                ],
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFramed = _useFramedAuthMode(context);
    final isPrimary = buttonColor == null;

    if (isFramed) {
      final tokens = _authTokens(context);
      final text$ = _authTextTheme(context);
      final spinnerColor = isPrimary ? tokens.btnInk : tokens.accent;

      return AnimatedOpacity(
        opacity: isLoading ? 0.65 : 1.0,
        duration: _submitDuration,
        child: IgnorePointer(
          ignoring: isLoading,
          child: SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: onPressed,
              style: _framedAuthButtonStyle(
                isPrimary: isPrimary,
                tokens: tokens,
                text$: text$,
              ),
              child: _buttonChild(spinnerColor),
            ),
          ),
        ),
      );
    }

    final backgroundColor = buttonColor ?? AuthPalette.primaryButtonBase;
    final foregroundColor = isPrimary
        ? AuthPalette.buttonForeground
        : AuthPalette.secondaryButtonForeground;
    final radius = BorderRadius.circular(AuthPalette.glassRadius);

    return AnimatedOpacity(
      opacity: isLoading ? 0.65 : 1.0,
      duration: _submitDuration,
      child: IgnorePointer(
        ignoring: isLoading,
        child: SizedBox(
          width: double.infinity,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: const [
                BoxShadow(
                  color: AuthPalette.buttonShadow,
                  blurRadius: 16,
                  offset: Offset(0, 10),
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
                        child: Center(child: _buttonChild(foregroundColor)),
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

ButtonStyle _framedAuthButtonStyle({
  required bool isPrimary,
  required NotifTokens tokens,
  required NotifTextTheme text$,
}) {
  final labelStyle = text$.eyebrow.copyWith(
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
  );

  return ButtonStyle(
    animationDuration: const Duration(milliseconds: 110),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(vertical: 12, horizontal: 14),
    ),
    minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),
    textStyle: WidgetStatePropertyAll(labelStyle),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (isPrimary) return tokens.btnInk;
      if (states.contains(WidgetState.pressed)) return tokens.btnInk;
      return tokens.accent;
    }),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (isPrimary) {
        if (states.contains(WidgetState.pressed)) {
          return Color.lerp(tokens.btnBg, Colors.black, 0.12);
        }
        if (states.contains(WidgetState.hovered)) {
          return Color.lerp(tokens.btnBg, tokens.ink, 0.08);
        }
        return tokens.btnBg;
      }
      if (states.contains(WidgetState.pressed)) {
        return tokens.accent.withValues(alpha: 0.20);
      }
      if (states.contains(WidgetState.hovered)) {
        return tokens.accent.withValues(alpha: 0.10);
      }
      return Colors.transparent;
    }),
    side: WidgetStateProperty.resolveWith((states) {
      if (isPrimary) {
        if (states.contains(WidgetState.focused)) {
          return BorderSide(color: tokens.accent, width: 2);
        }
        return BorderSide.none;
      }
      if (states.contains(WidgetState.focused)) {
        return BorderSide(color: tokens.accent, width: 2);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.pressed)) {
        return BorderSide(
          color: tokens.accent.withValues(alpha: 0.4),
          width: 1,
        );
      }
      return BorderSide(color: tokens.rule, width: 1);
    }),
    overlayColor: WidgetStatePropertyAll(tokens.accent.withValues(alpha: 0.06)),
  );
}
