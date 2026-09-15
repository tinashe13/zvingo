import 'package:flutter/material.dart';

import 'zv_buttons.dart';

/// Legacy alias kept so existing screens keep compiling.
///
/// **New code should use `ZvButton.primary` / `ZvButton.secondary` /
/// `ZvButton.tertiary` / `ZvButton.destructive`** — they carry the full §5.1
/// contract (variants, disabled reason, width-locked loading state).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isFullWidth = true,
    this.backgroundColor,
  });

  /// Button label.
  final String text;

  /// Tap handler; null disables the button.
  final VoidCallback? onPressed;

  /// Width-locked loading state.
  final bool isLoading;

  /// Stretch to the available width.
  final bool isFullWidth;

  /// Legacy override. A non-null value that is not the error colour is
  /// ignored — the design system allows exactly one filled action colour.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final destructive = backgroundColor != null &&
        backgroundColor == Theme.of(context).colorScheme.error;
    return ZvButton(
      label: text,
      onPressed: onPressed,
      loading: isLoading,
      fullWidth: isFullWidth,
      variant:
          destructive ? ZvButtonVariant.destructive : ZvButtonVariant.primary,
    );
  }
}
