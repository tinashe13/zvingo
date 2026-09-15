import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/auth/auth_provider.dart';
import 'package:consumer_app/features/auth/login_screen.dart'
    show AuthErrorBanner, pasteFromClipboard;
import 'package:consumer_app/features/auth/phone_number.dart';
import 'package:consumer_app/features/auth/widgets/auth_scaffold.dart';
import 'package:consumer_app/features/auth/widgets/phone_field.dart';

/// Enter the six-digit code sent by SMS.
///
/// Pushed by [LoginScreen] once `/auth/otp/request` has been accepted. Pops
/// `true` when the code checked out and the session is live.
///
/// The code's life is set by `OTP_TTL_SECONDS` on the server (5 minutes), and
/// the server allows `OTP_MAX_ATTEMPTS` (5) guesses before the code is burned —
/// both are reflected in the copy so a failure is never a surprise.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.phone});

  final String phone;

  static const int codeLength = 6;
  static const Duration resendCooldown = Duration(seconds: 45);
  static const Duration codeLifetime = Duration(minutes: 5);

  static Future<bool?> push(BuildContext context, {required String phone}) {
    return Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => OtpScreen(phone: phone),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _otpKey = GlobalKey<ZvOtpFieldState>();

  String _code = '';
  String? _errorMessage;
  bool _verifying = false;
  bool _resending = false;
  int _secondsLeft = OtpScreen.resendCooldown.inSeconds;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _ticker?.cancel();
    setState(() => _secondsLeft = OtpScreen.resendCooldown.inSeconds);
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

  Future<void> _verify([String? code]) async {
    final candidate = code ?? _code;
    if (candidate.length != OtpScreen.codeLength || _verifying) return;

    setState(() {
      _verifying = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(authProvider.notifier)
          .verifyOtp(phone: widget.phone, code: candidate);
      if (mounted) Navigator.of(context).pop(true);
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _errorMessage = failure.message;
      });
      _otpKey.currentState?.reset();
      HapticFeedback.mediumImpact();
    }
  }

  Future<void> _resend() async {
    if (_secondsLeft > 0 || _resending) return;
    setState(() {
      _resending = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authProvider.notifier).requestOtp(widget.phone);
      if (!mounted) return;
      _otpKey.currentState?.reset();
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('New code sent to ${ZvPhone.mask(widget.phone)}')),
      );
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _errorMessage = failure.message);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _paste() async {
    await pasteFromClipboard((text) => _otpKey.currentState?.fill(text));
  }

  @override
  Widget build(BuildContext context) {
    final complete = _code.length == OtpScreen.codeLength;

    return AuthScaffold(
      showBack: true,
      eyebrow: 'CHECK YOUR MESSAGES',
      title: 'Enter your code',
      subtitle: 'We sent a ${OtpScreen.codeLength}-digit code to '
          '${ZvPhone.mask(widget.phone)}. It expires in '
          '${OtpScreen.codeLifetime.inMinutes} minutes.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errorMessage != null) ...[
            AuthErrorBanner(message: _errorMessage!),
            const SizedBox(height: AppSpacing.md),
          ],
          ZvOtpField(
            key: _otpKey,
            length: OtpScreen.codeLength,
            enabled: !_verifying,
            hasError: _errorMessage != null,
            onChanged: (code) => setState(() => _code = code),
            onCompleted: _verify,
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: ZvButton.tertiary(
              label: 'Paste code',
              icon: Icons.content_paste_rounded,
              onPressed: _verifying ? null : _paste,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ZvButton.primary(
            label: 'Verify and continue',
            loading: _verifying,
            onPressed: complete && !_verifying ? () => _verify() : null,
            disabledReason: complete
                ? null
                : 'Enter all ${OtpScreen.codeLength} digits to continue',
          ),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: _secondsLeft > 0
                ? Text(
                    'Didn\'t get it? You can ask for a new code in '
                    '${_secondsLeft}s',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.tabular(AppTextStyles.caption)
                        .copyWith(color: AppColors.textSecondary),
                  )
                : ZvButton.tertiary(
                    label: 'Send a new code',
                    icon: Icons.refresh_rounded,
                    loading: _resending,
                    onPressed: _resending ? null : _resend,
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: const BoxDecoration(
              color: AppColors.infoSurface,
              borderRadius: AppRadius.mdAll,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 20, color: AppColors.info),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Zvingo will never ask you for this code by phone or '
                    'WhatsApp. If someone does, it is not us.',
                    style:
                        AppTextStyles.caption.copyWith(color: AppColors.info),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
