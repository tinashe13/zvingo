import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/auth/phone_number.dart';

/// A [ZvTextField] specialised for a Zimbabwean mobile number.
///
/// The `+263` sits in the field as a fixed, non-editable prefix and the digits
/// group themselves as they are typed (`77 123 4567`), so nobody has to
/// remember whether to drop the leading zero. Pasting `+263 77 123 4567`,
/// `0771234567` or `263771234567` all land on the same value.
class ZvPhoneField extends StatelessWidget {
  const ZvPhoneField({
    super.key,
    required this.controller,
    this.label = 'Mobile number',
    this.helper,
    this.dialCode = ZvPhone.defaultDialCode,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.autofillHints,
    this.enabled = true,
    this.autofocus = false,
    this.errorText,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final String dialCode;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final bool autofocus;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return ZvTextField(
      label: label,
      hint: '77 123 4567',
      helper: helper,
      errorText: errorText,
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: TextInputType.phone,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      validator: validator,
      inputFormatters: [ZvPhoneInputFormatter(dialCode: dialCode)],
      prefixIcon: Icons.smartphone_rounded,
      suffix: _DialCodeChip(dialCode: dialCode, enabled: enabled),
    );
  }
}

class _DialCodeChip extends StatelessWidget {
  const _DialCodeChip({required this.dialCode, required this.enabled});

  final String dialCode;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Country code $dialCode, Zimbabwe',
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.only(right: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: AppRadius.smAll,
        ),
        child: Text(
          dialCode,
          style: AppTextStyles.tabular(AppTextStyles.bodyStrong).copyWith(
            color: enabled ? AppColors.textPrimary : AppColors.textTertiary,
          ),
        ),
      ),
    );
  }
}

/// A six-box one-time-code entry.
///
/// Auto-advances as digits arrive, back-spaces into the previous box when one
/// is emptied, accepts a full code pasted into any box (and from the SMS
/// autofill suggestion), and calls [onCompleted] the instant all six are set so
/// the user rarely has to press a button at all.
class ZvOtpField extends StatefulWidget {
  const ZvOtpField({
    super.key,
    required this.length,
    required this.onCompleted,
    this.onChanged,
    this.enabled = true,
    this.hasError = false,
    this.autofocus = true,
  });

  final int length;
  final ValueChanged<String> onCompleted;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool hasError;
  final bool autofocus;

  @override
  State<ZvOtpField> createState() => ZvOtpFieldState();
}

class ZvOtpFieldState extends State<ZvOtpField> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _nodes;

  @override
  void initState() {
    super.initState();
    _controllers =
        List.generate(widget.length, (_) => TextEditingController());
    _nodes = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  String get value => _controllers.map((c) => c.text).join();

  /// Clears every box and returns focus to the first — used after a rejected
  /// code so the user is not left deleting six digits by hand.
  void reset() {
    for (final c in _controllers) {
      c.clear();
    }
    widget.onChanged?.call('');
    if (mounted) _nodes.first.requestFocus();
  }

  /// Fills the boxes from a pasted or autofilled string of digits.
  void fill(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return;
    for (var i = 0; i < widget.length; i++) {
      _controllers[i].text = i < digits.length ? digits[i] : '';
    }
    final filled = digits.length.clamp(0, widget.length);
    FocusScope.of(context)
        .requestFocus(_nodes[(filled - 1).clamp(0, widget.length - 1)]);
    _emit();
  }

  void _emit() {
    final code = value;
    if (mounted) setState(() {});
    widget.onChanged?.call(code);
    if (code.length == widget.length) {
      FocusManager.instance.primaryFocus?.unfocus();
      widget.onCompleted(code);
    }
  }

  void _onBoxChanged(int index, String text) {
    if (text.length >= 2) {
      if (text.length >= widget.length) {
        // A paste (or SMS autofill) landed in one box — spread it across the row.
        fill(text);
        return;
      }
      // Typing over a box that already had a digit: keep the newest one.
      final last = text.substring(text.length - 1);
      _controllers[index].value = TextEditingValue(
        text: last,
        selection: const TextSelection.collapsed(offset: 1),
      );
      if (index < widget.length - 1) _nodes[index + 1].requestFocus();
      _emit();
      return;
    }
    if (text.isNotEmpty && index < widget.length - 1) {
      _nodes[index + 1].requestFocus();
    }
    _emit();
  }

  KeyEventResult _onKey(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _controllers[index - 1].clear();
      _nodes[index - 1].requestFocus();
      _emit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${widget.length}-digit code',
      textField: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(widget.length, (index) {
          final filled = _controllers[index].text.isNotEmpty;
          return Flexible(
            child: Padding(
              padding: EdgeInsets.only(
                right: index == widget.length - 1 ? 0 : AppSpacing.xs,
              ),
              child: Focus(
                onKeyEvent: (_, event) => _onKey(index, event),
                child: AnimatedContainer(
                  duration: context.motion(AppMotion.fast),
                  height: 56,
                  decoration: BoxDecoration(
                    color: filled ? AppColors.surface : AppColors.surfaceMuted,
                    borderRadius: AppRadius.mdAll,
                    border: Border.all(
                      color: widget.hasError
                          ? AppColors.error
                          : filled
                              ? AppColors.actionDefault
                              : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: TextField(
                    controller: _controllers[index],
                    focusNode: _nodes[index],
                    enabled: widget.enabled,
                    autofocus: widget.autofocus && index == 0,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    style: AppTextStyles.tabular(AppTextStyles.h2),
                    // One character per box, but a paste of the whole code is
                    // allowed through so `fill` can spread it.
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    autofillHints: index == 0
                        ? const [AutofillHints.oneTimeCode]
                        : null,
                    decoration: const InputDecoration(
                      counterText: '',
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (text) => _onBoxChanged(index, text),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
