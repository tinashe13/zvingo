import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/auth/auth_provider.dart';
import 'package:consumer_app/features/auth/otp_screen.dart';
import 'package:consumer_app/features/auth/password_reset_screen.dart';
import 'package:consumer_app/features/auth/phone_number.dart';
import 'package:consumer_app/features/auth/widgets/auth_scaffold.dart';
import 'package:consumer_app/features/auth/widgets/phone_field.dart';

enum _SignInMethod { phone, email }

/// The first screen a new user sees, and the one that decides whether they ever
/// become a customer.
///
/// Phone-first, because in Zimbabwe a mobile number *is* the identity: it is
/// what Paynow charges, what the driver calls, and what the OTP goes to. Email
/// is offered as an alternative, not the default.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  _SignInMethod _method = _SignInMethod.phone;
  String? _errorMessage;
  bool _sendingCode = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your email address';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'That email address is missing an @ or a domain';
    }
    return null;
  }

  Future<void> _signIn() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _errorMessage = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = ref.read(authProvider.notifier);
    try {
      if (_method == _SignInMethod.phone) {
        await auth.signInWithPhone(
          phone: _phoneController.text,
          password: _passwordController.text,
        );
      } else {
        await auth.signInWithPassword(
          identifier: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
      if (mounted) context.go('/home');
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _errorMessage = failure.message);
    }
  }

  /// Passwordless route: send a six-digit code to the number in the field.
  Future<void> _sendCode() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final phoneError = ZvPhone.validate(_phoneController.text);
    if (phoneError != null) {
      setState(() => _errorMessage = phoneError);
      return;
    }

    setState(() {
      _errorMessage = null;
      _sendingCode = true;
    });

    try {
      await ref.read(authProvider.notifier).requestOtp(_phoneController.text);
      if (!mounted) return;
      final signedIn = await OtpScreen.push(
        context,
        phone: _phoneController.text,
      );
      if (signedIn == true && mounted) context.go('/home');
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _errorMessage = failure.message);
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  Future<void> _forgotPassword() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final done = await PasswordResetScreen.push(
      context,
      phone: _method == _SignInMethod.phone ? _phoneController.text : null,
    );
    if (done == true && mounted) {
      setState(() => _errorMessage = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password changed. Sign in with your new password.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final busy = authState.isLoading || _sendingCode;

    return AuthScaffold(
      eyebrow: 'DELIVERY, YOUR WAY',
      title: 'Good food is close',
      subtitle: 'Sign in to reorder favourites and track deliveries live.',
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: ZvStaggeredList(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            gap: AppSpacing.md,
            children: [
              SegmentedButton<_SignInMethod>(
                segments: const [
                  ButtonSegment(
                    value: _SignInMethod.phone,
                    label: Text('Phone'),
                    icon: Icon(Icons.smartphone_rounded, size: 18),
                  ),
                  ButtonSegment(
                    value: _SignInMethod.email,
                    label: Text('Email'),
                    icon: Icon(Icons.alternate_email_rounded, size: 18),
                  ),
                ],
                selected: {_method},
                showSelectedIcon: false,
                onSelectionChanged: (selection) => setState(() {
                  _method = selection.first;
                  _errorMessage = null;
                }),
              ),
              if (_errorMessage != null)
                AuthErrorBanner(message: _errorMessage!),
              if (_method == _SignInMethod.phone)
                ZvPhoneField(
                  controller: _phoneController,
                  label: 'Mobile number',
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  validator: ZvPhone.validate,
                )
              else
                ZvTextField(
                  label: 'Email address',
                  hint: 'you@example.com',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  prefixIcon: Icons.mail_outline_rounded,
                  autofillHints: const [AutofillHints.email],
                  validator: _validateEmail,
                ),
              ZvTextField(
                label: 'Password',
                hint: 'Your password',
                controller: _passwordController,
                obscureText: true,
                textInputAction: TextInputAction.done,
                prefixIcon: Icons.lock_outline_rounded,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _signIn(),
                validator: (value) => (value == null || value.isEmpty)
                    ? 'Enter your password'
                    : null,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: ZvButton.tertiary(
                  label: 'Forgot password?',
                  onPressed: busy ? null : _forgotPassword,
                ),
              ),
              ZvButton.primary(
                label: 'Sign in',
                loading: authState.isLoading,
                onPressed: busy ? null : _signIn,
              ),
              if (_method == _SignInMethod.phone)
                ZvButton.secondary(
                  label: 'Text me a code instead',
                  icon: Icons.sms_outlined,
                  loading: _sendingCode,
                  onPressed: busy ? null : _sendCode,
                ),
              const SizedBox(height: AppSpacing.xxs),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      'New to Zvingo?',
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                  ZvButton.tertiary(
                    label: 'Create an account',
                    onPressed: busy ? null : () => context.push('/register'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline, plain-language failure copy above the form (§5.5).
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({
    super.key,
    required this.message,
    this.tone = ZvTone.error,
  });

  final String message;
  final ZvTone tone;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: tone.surface,
          borderRadius: AppRadius.mdAll,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(tone.defaultIcon, color: tone.foreground, size: 20),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                message,
                style: AppTextStyles.caption.copyWith(color: tone.foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pastes the clipboard's contents into [onPaste] when it holds plain text.
Future<void> pasteFromClipboard(ValueChanged<String> onPaste) async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final text = data?.text?.trim();
  if (text != null && text.isNotEmpty) onPaste(text);
}
