import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_motion.dart';
import 'package:consumer_app/core/app_spacing.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/core/theme.dart';

/// The standard Zvingo text input (§5.3).
///
/// * Height 52, fill `neutral/100`, **no border at rest**, `radius/md`,
///   16 horizontal padding.
/// * Focus: 1.5px `action/default` border and the fill goes `neutral/0`.
/// * Error: 1.5px `error` border **plus the message below in `caption`** —
///   never a bare red border.
/// * The label sits **above** the field. Placeholders disappear; labels do not.
///
/// ```dart
/// ZvTextField(
///   label: 'Delivery instructions',
///   hint: 'Gate code, landmark, who to call',
///   controller: _notes,
///   helper: 'The driver sees this when they arrive.',
///   maxLines: 3,
/// )
/// ```
class ZvTextField extends StatefulWidget {
  const ZvTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.initialValue,
    this.helper,
    this.errorText,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.autofillHints,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.prefixIcon,
    this.suffix,
    this.focusNode,
    this.optionalLabel = false,
    this.onTap,
  });

  /// Label rendered above the field. Required — never rely on the hint alone.
  final String label;

  /// Placeholder shown inside the empty field.
  final String? hint;

  /// External controller. Mutually exclusive with [initialValue].
  final TextEditingController? controller;

  /// Initial text when no [controller] is supplied.
  final String? initialValue;

  /// Helper copy under the field, e.g. a format hint.
  final String? helper;

  /// Externally supplied error. Overrides [validator] output for display.
  final String? errorText;

  /// Form validation callback.
  final String? Function(String?)? validator;

  /// Fires on every keystroke.
  final ValueChanged<String>? onChanged;

  /// Fires when the user submits from the keyboard.
  final ValueChanged<String>? onSubmitted;

  /// Keyboard type.
  final TextInputType? keyboardType;

  /// Keyboard action button.
  final TextInputAction? textInputAction;

  /// Auto-capitalisation behaviour.
  final TextCapitalization textCapitalization;

  /// Input formatters, e.g. a phone mask.
  final List<TextInputFormatter>? inputFormatters;

  /// Masks input. A visibility toggle is added automatically.
  final bool obscureText;

  /// Set false to grey the field out.
  final bool enabled;

  /// Renders the value but blocks editing — use with [onTap] for pickers.
  final bool readOnly;

  /// Focus this field on first build.
  final bool autofocus;

  /// Platform autofill hints.
  final Iterable<String>? autofillHints;

  /// Maximum lines; >1 makes it a multi-line box.
  final int maxLines;

  /// Minimum lines for a multi-line box.
  final int? minLines;

  /// Character cap. The counter is hidden; enforce meaning in [helper].
  final int? maxLength;

  /// Leading glyph inside the field.
  final IconData? prefixIcon;

  /// Trailing widget inside the field, e.g. a unit label or a clear button.
  final Widget? suffix;

  /// External focus node.
  final FocusNode? focusNode;

  /// Appends "Optional" to the label so required fields need no asterisk.
  final bool optionalLabel;

  /// Tap handler, for read-only picker fields.
  final VoidCallback? onTap;

  @override
  State<ZvTextField> createState() => _ZvTextFieldState();
}

class _ZvTextFieldState extends State<ZvTextField> {
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();
  bool _ownsFocusNode = false;
  bool _focused = false;
  bool _obscured = true;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  String? get _error => widget.errorText ?? _validationError;

  @override
  Widget build(BuildContext context) {
    final hasError = _error != null && _error!.isNotEmpty;
    final multiline = widget.maxLines > 1;

    final borderColor = hasError
        ? AppColors.error
        : _focused
            ? AppColors.actionDefault
            : Colors.transparent;
    final fill = !widget.enabled
        ? AppColors.neutral100
        : (_focused && !hasError)
            ? AppColors.surface
            : AppColors.surfaceMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              widget.label,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (widget.optionalLabel) ...[
              const SizedBox(width: AppSpacing.xxs + 2),
              Text(
                'Optional',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textTertiary),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        AnimatedContainer(
          duration: context.motion(AppMotion.fast),
          curve: context.motionCurve(AppMotion.standard),
          constraints: BoxConstraints(
            minHeight: multiline ? AppTheme.inputHeight : 0,
          ),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: AppRadius.mdAll,
            border: Border.all(
              color: borderColor,
              width: borderColor == Colors.transparent ? 0 : 1.5,
            ),
          ),
          child: TextFormField(
            controller: widget.controller,
            initialValue:
                widget.controller == null ? widget.initialValue : null,
            focusNode: _focusNode,
            enabled: widget.enabled,
            readOnly: widget.readOnly,
            autofocus: widget.autofocus,
            autofillHints: widget.autofillHints,
            obscureText: widget.obscureText && _obscured,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            textCapitalization: widget.textCapitalization,
            inputFormatters: widget.inputFormatters,
            maxLines: widget.obscureText ? 1 : widget.maxLines,
            minLines: widget.minLines,
            maxLength: widget.maxLength,
            onChanged: widget.onChanged,
            onFieldSubmitted: widget.onSubmitted,
            onTap: widget.onTap,
            validator: widget.validator == null
                ? null
                : (value) {
                    final result = widget.validator!(value);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && result != _validationError) {
                        setState(() => _validationError = result);
                      }
                    });
                    return result;
                  },
            cursorColor: AppColors.actionDefault,
            style: AppTextStyles.body.copyWith(
              color: widget.enabled
                  ? AppColors.textPrimary
                  : AppColors.textTertiary,
            ),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle:
                  AppTextStyles.body.copyWith(color: AppColors.textTertiary),
              filled: false,
              counterText: '',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: multiline ? AppSpacing.sm : 15,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              // The message renders below the box instead, so it can wrap.
              errorStyle: const TextStyle(height: 0, fontSize: 0),
              prefixIcon: widget.prefixIcon == null
                  ? null
                  : Icon(
                      widget.prefixIcon,
                      size: 20,
                      color:
                          hasError ? AppColors.error : AppColors.textSecondary,
                    ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 44,
                minHeight: 44,
              ),
              suffixIcon: widget.obscureText
                  ? IconButton(
                      onPressed: () => setState(() => _obscured = !_obscured),
                      tooltip: _obscured ? 'Show password' : 'Hide password',
                      icon: Icon(
                        _obscured
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                      ),
                    )
                  : widget.suffix,
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: AppSpacing.xxs + 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 15,
                color: AppColors.error,
              ),
              const SizedBox(width: AppSpacing.xxs + 2),
              Expanded(
                child: Text(
                  _error!,
                  style: AppTextStyles.caption.copyWith(color: AppColors.error),
                ),
              ),
            ],
          ),
        ] else if (widget.helper != null) ...[
          const SizedBox(height: AppSpacing.xxs + 2),
          Text(widget.helper!, style: AppTextStyles.caption),
        ],
      ],
    );
  }
}

/// The search field used on home, store and menu search (§5.3).
///
/// Pill-shaped, `neutral/100` fill, leading magnifier, a clear button once
/// there is text. It never hides its purpose behind an icon-only affordance.
///
/// ```dart
/// ZvSearchField(
///   hint: 'Search restaurants or dishes',
///   controller: _query,
///   onChanged: ref.read(searchProvider.notifier).setQuery,
///   onSubmitted: (_) => _runSearch(),
/// )
/// ```
class ZvSearchField extends StatefulWidget {
  const ZvSearchField({
    super.key,
    this.controller,
    this.hint = 'Search',
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.onTap,
    this.readOnly = false,
    this.autofocus = false,
    this.focusNode,
    this.trailing,
  });

  /// External controller — required if you want the clear button to work with
  /// externally-set text.
  final TextEditingController? controller;

  /// Placeholder. Say what is searchable.
  final String hint;

  /// Fires on every keystroke.
  final ValueChanged<String>? onChanged;

  /// Fires on keyboard submit.
  final ValueChanged<String>? onSubmitted;

  /// Extra callback after the clear button empties the field.
  final VoidCallback? onClear;

  /// Tap handler, for a read-only field that opens a full search screen.
  final VoidCallback? onTap;

  /// Blocks editing — pair with [onTap].
  final bool readOnly;

  /// Focus on first build.
  final bool autofocus;

  /// External focus node.
  final FocusNode? focusNode;

  /// Widget at the far right, e.g. a filter button.
  final Widget? trailing;

  @override
  State<ZvSearchField> createState() => _ZvSearchFieldState();
}

class _ZvSearchFieldState extends State<ZvSearchField> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: Container(
            height: AppTheme.inputHeight,
            decoration: const BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: AppRadius.fullAll,
            ),
            child: Row(
              children: [
                const SizedBox(width: AppSpacing.md),
                const Icon(
                  Icons.search_rounded,
                  size: 21,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: widget.focusNode,
                    autofocus: widget.autofocus,
                    readOnly: widget.readOnly,
                    onTap: widget.onTap,
                    onChanged: widget.onChanged,
                    onSubmitted: widget.onSubmitted,
                    textInputAction: TextInputAction.search,
                    cursorColor: AppColors.actionDefault,
                    style: AppTextStyles.body,
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      hintStyle: AppTextStyles.body
                          .copyWith(color: AppColors.textTertiary),
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
                if (hasText)
                  IconButton(
                    onPressed: _clear,
                    tooltip: 'Clear search',
                    iconSize: 19,
                    icon: const Icon(Icons.close_rounded),
                  )
                else
                  const SizedBox(width: AppSpacing.md),
              ],
            ),
          ),
        ),
        if (widget.trailing != null) ...[
          const SizedBox(width: AppSpacing.xs),
          widget.trailing!,
        ],
      ],
    );
  }
}

/// The quantity stepper used on menu items and in the cart (§5.3).
///
/// Both controls keep a 48×48 tap target. At [min] the decrement button turns
/// into a delete affordance when [deleteAtMin] is set, so the user is never
/// stuck at "1" with no way to remove the line.
///
/// ```dart
/// ZvStepper(
///   value: line.quantity,
///   min: 1,
///   max: 25,
///   deleteAtMin: true,
///   onChanged: (q) => ref.read(cartProvider.notifier).setQuantity(line.id, q),
///   onDelete: () => ref.read(cartProvider.notifier).remove(line.id),
/// )
/// ```
class ZvStepper extends StatelessWidget {
  const ZvStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 99,
    this.step = 1,
    this.deleteAtMin = false,
    this.onDelete,
    this.compact = false,
    this.semanticLabel = 'Quantity',
    this.busy = false,
  });

  /// Current quantity.
  final int value;

  /// Called with the new quantity.
  final ValueChanged<int> onChanged;

  /// Lowest allowed quantity.
  final int min;

  /// Highest allowed quantity.
  final int max;

  /// Increment size.
  final int step;

  /// At [min], show a bin icon instead of a disabled minus.
  final bool deleteAtMin;

  /// Called when the bin is tapped. Required when [deleteAtMin] is true.
  final VoidCallback? onDelete;

  /// Slightly smaller control for dense rows. Tap targets stay 48×48.
  final bool compact;

  /// Screen-reader label for the whole control.
  final String semanticLabel;

  /// Disables both controls while a mutation is in flight.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final atMin = value <= min;
    final atMax = value >= max;
    final showDelete = deleteAtMin && atMin && onDelete != null;
    final size = compact ? 32.0 : 36.0;

    return Semantics(
      label: semanticLabel,
      value: '$value',
      child: Container(
        height: compact ? 40 : 44,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        decoration: const BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: AppRadius.fullAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepperButton(
              icon: showDelete
                  ? Icons.delete_outline_rounded
                  : Icons.remove_rounded,
              tooltip: showDelete ? 'Remove item' : 'Decrease quantity',
              size: size,
              destructive: showDelete,
              onPressed: busy
                  ? null
                  : showDelete
                      ? onDelete
                      : atMin
                          ? null
                          : () => onChanged(value - step),
            ),
            SizedBox(
              width: compact ? 28 : 34,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyStrong.copyWith(
                  fontFeatures: AppTextStyles.tabularFigures,
                ),
              ),
            ),
            _StepperButton(
              icon: Icons.add_rounded,
              tooltip: 'Increase quantity',
              size: size,
              onPressed: busy || atMax ? null : () => onChanged(value + step),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.tooltip,
    required this.size,
    required this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String tooltip;
  final double size;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = !enabled
        ? AppColors.actionDisabledFg
        : destructive
            ? AppColors.error
            : AppColors.textPrimary;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: SizedBox(
          height: AppSpacing.minTapTarget,
          width: AppSpacing.minTapTarget,
          child: Center(
            child: Material(
              color: enabled ? AppColors.surface : Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPressed,
                child: SizedBox(
                  height: size,
                  width: size,
                  child: Icon(icon, size: 18, color: color),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
