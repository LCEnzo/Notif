import 'package:flutter/material.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';

enum NotifInputVariant { boxed, underline }

InputDecoration notifInputDecoration({
  required BuildContext context,
  String? label,
  String? hint,
  String? errorText,
  NotifInputVariant variant = NotifInputVariant.boxed,
  Color? fillColor,
  Color? enabledBorderColor,
  bool codeText = true,
}) {
  final tokens = NotifTokens.of(context);
  final text$ = NotifTextTheme.of(context);
  final hintBase = codeText ? text$.code : text$.body;
  final enabledColor = enabledBorderColor ?? tokens.ruleStrong;

  InputBorder border(Color color, double width) {
    switch (variant) {
      case NotifInputVariant.boxed:
        return OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: color, width: width),
        );
      case NotifInputVariant.underline:
        return UnderlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: color, width: width),
        );
    }
  }

  return InputDecoration(
    labelText: label,
    hintText: hint,
    errorText: errorText,
    labelStyle: text$.body.copyWith(color: tokens.inkDim),
    hintStyle: hintBase.copyWith(color: tokens.inkMute),
    errorStyle: text$.micro.copyWith(color: NotifFeedback.error),
    contentPadding: variant == NotifInputVariant.boxed
        ? const EdgeInsets.symmetric(vertical: 10, horizontal: 12)
        : const EdgeInsets.symmetric(vertical: 10),
    filled: variant == NotifInputVariant.boxed,
    fillColor: fillColor ?? tokens.bg0,
    enabledBorder: border(enabledColor, 1),
    focusedBorder: border(tokens.accent, 2),
    errorBorder: border(NotifFeedback.error, 1),
    focusedErrorBorder: border(NotifFeedback.error, 2),
  );
}

class NotifTextField extends StatelessWidget {

  const NotifTextField({
    required this.controller,
    this.label,
    this.hint,
    this.errorText,
    this.onChanged,
    this.obscureText = false,
    this.keyboardType,
    this.variant = NotifInputVariant.boxed,
    super.key,
  });
  final TextEditingController controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final TextInputType? keyboardType;
  final NotifInputVariant variant;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: text$.code.copyWith(color: tokens.ink),
      cursorColor: tokens.accent,
      decoration: notifInputDecoration(
        context: context,
        label: label,
        hint: hint,
        errorText: errorText,
        variant: variant,
      ),
      onChanged: onChanged,
    );
  }
}
