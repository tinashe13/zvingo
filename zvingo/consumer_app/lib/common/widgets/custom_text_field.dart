import 'package:flutter/material.dart';

import 'zv_inputs.dart';

/// Legacy alias kept so existing screens keep compiling.
///
/// **New code should use `ZvTextField`** — it carries the full §5.3 contract
/// (focus fill swap, error message below the field, optional-label marker,
/// helper copy, password visibility toggle).
class CustomTextField extends StatelessWidget {
  const CustomTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.validator,
    this.prefixIcon,
    this.suffixIcon,
    this.textInputAction,
    this.autofillHints,
    this.onFieldSubmitted,
    this.textCapitalization = TextCapitalization.none,
  });

  /// Label rendered above the field.
  final String label;

  /// Placeholder inside the field.
  final String? hint;

  /// External controller.
  final TextEditingController? controller;

  /// Masks input and adds a visibility toggle.
  final bool obscureText;

  /// Keyboard type.
  final TextInputType keyboardType;

  /// Form validation callback.
  final String? Function(String?)? validator;

  /// Leading widget inside the field.
  final Widget? prefixIcon;

  /// Trailing widget inside the field.
  final Widget? suffixIcon;

  /// Keyboard action button.
  final TextInputAction? textInputAction;

  /// Platform autofill hints.
  final Iterable<String>? autofillHints;

  /// Fires on keyboard submit.
  final ValueChanged<String>? onFieldSubmitted;

  /// Auto-capitalisation behaviour.
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return ZvTextField(
      label: label,
      hint: hint,
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      onSubmitted: onFieldSubmitted,
      textCapitalization: textCapitalization,
      prefixIcon: prefixIcon is Icon ? (prefixIcon as Icon).icon : null,
      suffix: obscureText ? null : suffixIcon,
    );
  }
}
