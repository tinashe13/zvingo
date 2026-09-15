import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/auth/auth_provider.dart';
import 'package:consumer_app/features/auth/login_screen.dart'
    show AuthErrorBanner, pasteFromClipboard;
import 'package:consumer_app/features/auth/password_policy.dart';
import 'package:consumer_app/features/auth/phone_number.dart';
import 'package:consumer_app/features/auth/widgets/auth_scaffold.dart';
import 'package:consumer_app/features/auth/widgets/phone_field.dart';

enum _ResetStep { requestCode, setPassword, done }

/// Forgot-password, in two steps and one screen.
///
/// **The reset code never appears in an API response.** Agent F4 closed that
/// hole (`backend/app/auth/router.py::request_password_reset`): the token is
/// `secrets.token_urlsafe(32)`, it is stored only as a SHA-256 digest, it is
/// single-use, it lives 15 minutes, and it reaches the user **only by SMS**.
/// So this screen asks the user to paste the long code out of their messages —
/// it is not a 6-digit PIN, and this client never reads, displays or logs the
/// value beyond the field it is typed into.
///
/// The request step answers identically for a registered and an unregistered
/// number (no enumeration oracle), so the confirmation copy says "if that
/// number has a Zvingo account".
class PasswordResetScreen extends ConsumerStatefulWidget {
  const PasswordResetScreen({super.key, this.phone});

  /// Pre-fills the number the user already typed on the sign-in screen.
  final String? phone;

  static const Duration codeLifetime = Duration(minutes: 15);
  static const Duration resendCooldown = Duration(seconds: 60);

  static Future<bool?> push(BuildContext context, {String? phone}) {
    return Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PasswordResetScreen(phone: phone),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  ConsumerState<PasswordResetScreen> createState() =>
      _PasswordResetScreenState();
}

class _PasswordResetScreenState extends ConsumerState<PasswordResetScreen> {
  final _requestKey = GlobalKey<FormState>();
  final _confirmKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();

  _ResetStep _step = _ResetStep.requestCode;
  String? _errorMessage;
  bool _busy = false;
  int _secondsLeft = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    if (widget.phone != null) {
      _phoneController.text = ZvPhone.formatNational(widget.phone!);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _ticker?.cancel();
    setState(() => _secondsLeft = PasswordResetScreen.resendCooldown.inSeconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _requestCode({bool resend = false}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_requestKey.currentState?.validate() ?? false) && !resend) return;
    if (_busy) return;

    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(authProvider.notifier)
          .requestPasswordReset(_phoneController.text);
      if (!mounted) return;
      setState(() => _step = _ResetStep.setPassword);
      _startCooldown();
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _errorMessage = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_confirmKey.currentState?.validate() ?? false) || _busy) return;

    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authProvider.notifier).confirmPasswordReset(
            code: _codeController.text,
            newPassword: _passwordController.text,
          );
      if (mounted) setState(() => _step = _ResetStep.done);
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _errorMessage = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_step) {
      _ResetStep.requestCode => _buildRequest(),
      _ResetStep.setPassword => _buildConfirm(),
      _ResetStep.done => _buildDone(),
    };
  }

  Widget _buildRequest() {
    return AuthScaffold(
      showBack: true,
      eyebrow: 'FORGOT PASSWORD',
      title: 'Reset your password',
      subtitle: 'Tell us the mobile number on your account and we will text '
          'you a reset code.',
      child: Form(
        key: _requestKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorMessage != null) ...[
              AuthErrorBanner(message: _errorMessage!),
              const SizedBox(height: AppSpacing.md),
            ],
            ZvPhoneField(
              controller: _phoneController,
              autofocus: widget.phone == null,
              enabled: !_busy,
              textInputAction: TextInputAction.done,
              validator: ZvPhone.validate,
              onSubmitted: (_) => _requestCode(),
            ),
            const SizedBox(height: AppSpacing.xl),
            ZvButton.primary(
              label: 'Send reset code',
              icon: Icons.sms_outlined,
              loading: _busy,
              onPressed: _busy ? null : () => _requestCode(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirm() {
    final password = _passwordController.text;

    return AuthScaffold(
      showBack: true,
      eyebrow: 'STEP 2 OF 2',
      title: 'Choose a new password',
      subtitle: 'If ${ZvPhone.mask(_phoneController.text)} has a Zvingo '
          'account, a reset code is on its way by SMS. It is a long code — '
          'copy it from your messages and paste it below. It expires in '
          '${PasswordResetScreen.codeLifetime.inMinutes} minutes.',
      child: Form(
        key: _confirmKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorMessage != null) ...[
              AuthErrorBanner(message: _errorMessage!),
              const SizedBox(height: AppSpacing.md),
            ],
            ZvTextField(
              label: 'Reset code from SMS',
              hint: 'Paste the code from your messages',
              controller: _codeController,
              enabled: !_busy,
              maxLines: 2,
              minLines: 1,
              prefixIcon: Icons.key_outlined,
              textInputAction: TextInputAction.next,
              validator: (value) {
                final code = value?.trim() ?? '';
                if (code.isEmpty) return 'Paste the code from your SMS';
                if (code.length < 8) {
                  return 'That code looks incomplete — copy the whole thing '
                      'from the message';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: ZvButton.tertiary(
                label: 'Paste from clipboard',
                icon: Icons.content_paste_rounded,
                onPressed: _busy
                    ? null
                    : () => pasteFromClipboard(
                          (text) => setState(() => _codeController.text = text),
                        ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ZvTextField(
              label: 'New password',
              hint: 'At least ${ZvPasswordPolicy.minLength} characters',
              controller: _passwordController,
              enabled: !_busy,
              obscureText: true,
              prefixIcon: Icons.lock_outline_rounded,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _confirm(),
              validator: ZvPasswordPolicy.validate,
            ),
            const SizedBox(height: AppSpacing.sm),
            ZvPasswordChecklist(password: password),
            const SizedBox(height: AppSpacing.md),
            ZvButton.primary(
              label: 'Change password',
              loading: _busy,
              onPressed: _busy ? null : _confirm,
            ),
            const SizedBox(height: AppSpacing.xs),
            Center(
              child: _secondsLeft > 0
                  ? Text(
                      'No SMS yet? You can ask again in ${_secondsLeft}s',
                      style: AppTextStyles.tabular(AppTextStyles.caption)
                          .copyWith(color: AppColors.textSecondary),
                    )
                  : ZvButton.tertiary(
                      label: 'Send another code',
                      icon: Icons.refresh_rounded,
                      onPressed:
                          _busy ? null : () => _requestCode(resend: true),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDone() {
    return AuthScaffold(
      title: 'Password changed',
      subtitle: 'For your safety we signed out every device that was using '
          'the old password. Sign in again with the new one.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ZvEmptyState(
            icon: Icons.verified_user_rounded,
            title: 'You are all set',
            message: 'Your new password is active on your Zvingo account.',
          ),
          ZvButton.primary(
            label: 'Back to sign in',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }
}
