import 'package:flutter/material.dart';

import 'package:consumer_app/common/zvingo_ui.dart';

/// One rule a password must satisfy, with the copy shown to the user.
class ZvPasswordRule {
  const ZvPasswordRule({
    required this.label,
    required this.test,
    this.required = true,
  });

  /// Shown in the live checklist. Phrased as the requirement, not the failure.
  final String label;

  /// Whether [label] is satisfied.
  final bool Function(String) test;

  /// `false` for rules that only strengthen the password rather than gate it.
  final bool required;
}

/// Strength bands. Deliberately four, so the meter is a hint and not a score.
enum ZvPasswordStrength { tooShort, weak, fair, strong }

extension ZvPasswordStrengthCopy on ZvPasswordStrength {
  String get label => switch (this) {
        ZvPasswordStrength.tooShort => 'Too short',
        ZvPasswordStrength.weak => 'Weak',
        ZvPasswordStrength.fair => 'Fair',
        ZvPasswordStrength.strong => 'Strong',
      };

  Color get color => switch (this) {
        ZvPasswordStrength.tooShort => AppColors.neutral400,
        ZvPasswordStrength.weak => AppColors.error,
        ZvPasswordStrength.fair => AppColors.warning,
        ZvPasswordStrength.strong => AppColors.success,
      };

  double get fraction => switch (this) {
        ZvPasswordStrength.tooShort => 0.12,
        ZvPasswordStrength.weak => 0.34,
        ZvPasswordStrength.fair => 0.67,
        ZvPasswordStrength.strong => 1.0,
      };
}

/// The app's password policy.
///
/// The minimum length mirrors `MIN_PASSWORD_LENGTH` in
/// `backend/app/auth/schemas.py`. The rules are shown **before** submission, so
/// the server never has to reject a password the user was not warned about.
class ZvPasswordPolicy {
  const ZvPasswordPolicy._();

  static const int minLength = 8;

  static final List<ZvPasswordRule> rules = <ZvPasswordRule>[
    ZvPasswordRule(
      label: 'At least $minLength characters',
      test: (value) => value.length >= minLength,
    ),
    ZvPasswordRule(
      label: 'A letter and a number',
      test: (value) =>
          RegExp(r'[A-Za-z]').hasMatch(value) &&
          RegExp(r'[0-9]').hasMatch(value),
    ),
    ZvPasswordRule(
      label: 'Not your phone number or "password"',
      test: _isNotObvious,
    ),
    ZvPasswordRule(
      label: 'Stronger with a capital letter or symbol',
      required: false,
      test: (value) =>
          RegExp(r'[A-Z]').hasMatch(value) ||
          RegExp(r'[^A-Za-z0-9]').hasMatch(value),
    ),
  ];

  static const List<String> _banned = <String>[
    'password',
    'passw0rd',
    '12345678',
    '87654321',
    'qwertyui',
    'zvingo',
    'iloveyou',
    'letmein',
  ];

  static bool _isNotObvious(String value) {
    final lower = value.toLowerCase();
    if (lower.isEmpty) return false;
    if (_banned.any(lower.contains)) return false;
    // A run of 7+ digits is almost always a phone number.
    if (RegExp(r'^[0-9]{7,}$').hasMatch(lower)) return false;
    return true;
  }

  /// `null` when the password may be submitted, else the first failure.
  static String? validate(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Choose a password';
    for (final rule in rules.where((r) => r.required)) {
      if (!rule.test(password)) return rule.label;
    }
    return null;
  }

  static ZvPasswordStrength strengthOf(String value) {
    if (value.length < minLength) return ZvPasswordStrength.tooShort;
    var score = 0;
    if (RegExp(r'[a-z]').hasMatch(value)) score++;
    if (RegExp(r'[A-Z]').hasMatch(value)) score++;
    if (RegExp(r'[0-9]').hasMatch(value)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(value)) score++;
    if (value.length >= 12) score++;
    if (!_isNotObvious(value)) return ZvPasswordStrength.weak;
    if (score >= 4) return ZvPasswordStrength.strong;
    if (score >= 3) return ZvPasswordStrength.fair;
    return ZvPasswordStrength.weak;
  }
}

/// Live strength meter + rule checklist, shown under the password field.
///
/// The rules are visible from the first keystroke — a user should never
/// discover a requirement by having their submission rejected.
class ZvPasswordChecklist extends StatelessWidget {
  const ZvPasswordChecklist({
    super.key,
    required this.password,
    this.showMeter = true,
  });

  final String password;
  final bool showMeter;

  @override
  Widget build(BuildContext context) {
    final strength = ZvPasswordPolicy.strengthOf(password);
    final started = password.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showMeter) ...[
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: AppRadius.fullAll,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      end: started ? strength.fraction : 0,
                    ),
                    duration: context.motion(AppMotion.base),
                    curve: context.motionCurve(AppMotion.standard),
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 6,
                      backgroundColor: AppColors.surfaceMuted,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        started ? strength.color : AppColors.neutral300,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              ZvAnimatedSwap(
                valueKey: started ? strength : 'idle',
                child: Text(
                  started ? strength.label : 'Password strength',
                  style: AppTextStyles.caption.copyWith(
                    color: started ? strength.color : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        ...ZvPasswordPolicy.rules.map((rule) {
          final met = rule.test(password);
          final color = !started
              ? AppColors.textSecondary
              : met
                  ? AppColors.success
                  : rule.required
                      ? AppColors.textSecondary
                      : AppColors.textSecondary;
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  met
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 16,
                  color: met ? AppColors.success : AppColors.neutral300,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    rule.label,
                    style: AppTextStyles.caption.copyWith(color: color),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
