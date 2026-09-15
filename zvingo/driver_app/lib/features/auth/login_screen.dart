import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/app_motion.dart';
import '../../core/app_spacing.dart';
import '../../core/app_text_styles.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/widgets.dart';

/// Sign in / create account.
///
/// **Phone-first.** Zimbabwean drivers have a phone number long before they
/// have an email address, and the backend already treats phone as the unique
/// identity (`User.phone` is the unique index; `UserCreate` rejects anything
/// that is not E.164). The field therefore shows a fixed `+263` prefix, takes
/// the number the way a driver writes it — `077 123 4567` — and normalises to
/// `+263771234567` on submit.
///
/// Email is offered only as an optional recovery address at registration, and
/// as an alternative sign-in identifier for accounts created with one.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _confirmController = TextEditingController();
  final _emailController = TextEditingController();

  final _phoneFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _isRegisterMode = false;
  bool _obscurePassword = true;
  bool _submitted = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _confirmController.dispose();
    _emailController.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (AuthNotifier.validatePhone(_phoneController.text) != null) return false;
    if (AuthNotifier.validatePassword(
          _passwordController.text,
          isRegister: _isRegisterMode,
        ) !=
        null) {
      return false;
    }
    if (!_isRegisterMode) return true;
    if (_nameController.text.trim().isEmpty) return false;
    if (_confirmController.text != _passwordController.text) return false;
    return true;
  }

  Future<void> _submit() async {
    setState(() => _submitted = true);
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      HapticFeedback.heavyImpact();
      return;
    }

    final notifier = ref.read(authProvider.notifier);
    if (_isRegisterMode) {
      await notifier.register(
        fullName: _nameController.text,
        phone: _phoneController.text,
        password: _passwordController.text,
        email: _emailController.text,
      );
    } else {
      await notifier.login(_phoneController.text, _passwordController.text);
    }
  }

  void _switchMode() {
    setState(() {
      _isRegisterMode = !_isRegisterMode;
      _submitted = false;
    });
    ref.read(authProvider.notifier).acknowledgeSignOut();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final padding = AppSpacing.screenPaddingOf(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              padding,
              AppSpacing.section,
              padding,
              AppSpacing.section,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                autovalidateMode: _submitted
                    ? AutovalidateMode.onUserInteraction
                    : AutovalidateMode.disabled,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Brand(),
                    Gap.xxl,
                    Text(
                      _isRegisterMode
                          ? 'Create your driver account'
                          : 'Sign in to drive',
                      textAlign: TextAlign.center,
                      style:
                          AppTextStyles.onSurface(context, AppTextStyles.h1),
                    ),
                    Gap.sm,
                    Text(
                      _isRegisterMode
                          ? 'You will need your phone number and a password. '
                              'Zvingo will verify your vehicle details later.'
                          : 'Use the phone number you registered with.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.textSecondary),
                    ),
                    if (auth.signOutReason == SignOutReason.sessionExpired) ...[
                      Gap.xl,
                      const _SessionExpiredNotice(),
                    ],
                    Gap.section,
                    if (_isRegisterMode) ...[
                      _Field(
                        label: 'Full name',
                        child: TextFormField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.name],
                          decoration: const InputDecoration(
                            hintText: 'As it appears on your licence',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                                  ? 'Enter your full name'
                                  : null,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      Gap.lg,
                    ],
                    _Field(
                      label: 'Phone number',
                      helper: 'Zvingo uses this to reach you about deliveries.',
                      child: TextFormField(
                        controller: _phoneController,
                        focusNode: _phoneFocus,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9+\s\-()]'),
                          ),
                          LengthLimitingTextInputFormatter(20),
                        ],
                        decoration: InputDecoration(
                          hintText: '077 123 4567',
                          prefixIcon: const Icon(Icons.phone_outlined),
                          prefix: Padding(
                            padding: const EdgeInsets.only(right: AppSpacing.sm),
                            child: Text(
                              AuthNotifier.zimbabweDialCode,
                              style: AppTextStyles.money.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                        validator: (value) =>
                            AuthNotifier.validatePhone(value ?? ''),
                        onChanged: (_) => setState(() {}),
                        onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                      ),
                    ),
                    Gap.lg,
                    _Field(
                      label: 'Password',
                      helper: _isRegisterMode ? 'At least 8 characters.' : null,
                      child: TextFormField(
                        controller: _passwordController,
                        focusNode: _passwordFocus,
                        obscureText: _obscurePassword,
                        textInputAction: _isRegisterMode
                            ? TextInputAction.next
                            : TextInputAction.done,
                        autofillHints: [
                          _isRegisterMode
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        decoration: InputDecoration(
                          hintText: _isRegisterMode
                              ? 'Choose a password'
                              : 'Your password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        validator: (value) => AuthNotifier.validatePassword(
                          value ?? '',
                          isRegister: _isRegisterMode,
                        ),
                        onChanged: (_) => setState(() {}),
                        onFieldSubmitted: (_) =>
                            _isRegisterMode ? null : _submit(),
                      ),
                    ),
                    if (_isRegisterMode) ...[
                      Gap.lg,
                      _Field(
                        label: 'Confirm password',
                        child: TextFormField(
                          controller: _confirmController,
                          obscureText: true,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'Type it again',
                            prefixIcon: Icon(Icons.lock_reset_rounded),
                          ),
                          validator: (value) =>
                              value != _passwordController.text
                                  ? 'The two passwords do not match'
                                  : null,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      Gap.lg,
                      _Field(
                        label: 'Email (optional)',
                        helper:
                            'Only used to help you recover your account. You '
                            'can add it later.',
                        child: TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            hintText: 'you@example.com',
                            prefixIcon: Icon(Icons.mail_outline_rounded),
                          ),
                          validator: (value) {
                            final text = (value ?? '').trim();
                            if (text.isEmpty) return null;
                            final valid = RegExp(
                              r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                            ).hasMatch(text);
                            return valid
                                ? null
                                : 'That does not look like an email address';
                          },
                          onFieldSubmitted: (_) => _submit(),
                        ),
                      ),
                    ],
                    if (auth.error != null) ...[
                      Gap.lg,
                      _ErrorBanner(message: auth.error!),
                    ],
                    Gap.xl,
                    DriverPrimaryButton(
                      label: _isRegisterMode ? 'Create account' : 'Sign in',
                      isLoading: auth.isLoading,
                      onPressed: _canSubmit && !auth.isLoading ? _submit : null,
                      disabledReason: auth.isLoading
                          ? null
                          : _disabledReason(),
                    ),
                    Gap.md,
                    DriverTextButton(
                      label: _isRegisterMode
                          ? 'I already have an account'
                          : 'I am new to Zvingo — create an account',
                      expanded: true,
                      onPressed: auth.isLoading ? null : _switchMode,
                    ),
                    Gap.xl,
                    Text(
                      'Forgot your password? Zvingo driver support can reset '
                      'it for you — ask in your driver group or at the '
                      'Zvingo office.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A disabled button with no reason is a dead end. This says what is missing.
  String? _disabledReason() {
    if (_canSubmit) return null;
    if (_isRegisterMode && _nameController.text.trim().isEmpty) {
      return 'Enter your full name to continue';
    }
    final phoneIssue = AuthNotifier.validatePhone(_phoneController.text);
    if (phoneIssue != null) return phoneIssue;
    final passwordIssue = AuthNotifier.validatePassword(
      _passwordController.text,
      isRegister: _isRegisterMode,
    );
    if (passwordIssue != null) return passwordIssue;
    if (_isRegisterMode && _confirmController.text != _passwordController.text) {
      return 'The two passwords do not match';
    }
    return null;
  }
}

// ── Pieces ──────────────────────────────────────────────────────────────────

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // The logo is a brand moment, so it is brand green — §1.2 made
            // `AppColors.primary` near-black, which is for buttons, not marks.
            color: AppColors.brandGreen,
            borderRadius: AppSpacing.brLg,
          ),
          child: Text(
            'Z',
            style: AppTextStyles.display.copyWith(
              color: AppColors.textOnDark,
              fontSize: 36,
            ),
          ),
        ),
        Gap.md,
        Text(
          'Zvingo Driver',
          style: AppTextStyles.onSurface(context, AppTextStyles.h2),
        ),
      ],
    );
  }
}

/// §5.3: labels sit above the field, never as a disappearing placeholder.
class _Field extends StatelessWidget {
  final String label;
  final String? helper;
  final Widget child;

  const _Field({required this.label, required this.child, this.helper});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style:
              AppTextStyles.bodyStrong.copyWith(color: AppColors.textPrimary),
        ),
        Gap.sm,
        child,
        if (helper != null) ...[
          Gap.xs,
          Text(
            helper!,
            style:
                AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.durationOf(context, AppMotion.fast),
      child: Container(
        key: ValueKey(message),
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.errorSurfaceOf(context),
          borderRadius: AppSpacing.brMd,
          border: Border.all(
            color: AppColors.errorOf(context).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 18, color: AppColors.errorOf(context)),
            Gap.hSm,
            Expanded(
              child: Text(
                message,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.errorOf(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when a refresh token was rejected while the driver was working.
/// Explaining it is the difference between "the app logged me out" and "the
/// app is broken".
class _SessionExpiredNotice extends StatelessWidget {
  const _SessionExpiredNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.infoSurfaceOf(context),
        borderRadius: AppSpacing.brMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_clock_rounded,
              size: 18, color: AppColors.infoOf(context)),
          Gap.hSm,
          Expanded(
            child: Text(
              'Your session ended for security. Sign in again — any '
              'delivery you were on is still assigned to you.',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.infoOf(context)),
            ),
          ),
        ],
      ),
    );
  }
}
