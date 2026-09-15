import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/auth/auth_provider.dart';
import 'package:consumer_app/features/auth/login_screen.dart'
    show AuthErrorBanner;
import 'package:consumer_app/features/auth/password_policy.dart';
import 'package:consumer_app/features/auth/phone_number.dart';
import 'package:consumer_app/features/auth/widgets/auth_scaffold.dart';
import 'package:consumer_app/features/auth/widgets/phone_field.dart';

/// Create a Zvingo account.
///
/// Four fields, one of them optional, and the password rules on screen from the
/// first keystroke — nothing is rejected after the fact for a reason the user
/// was never shown.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _errorMessage = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    try {
      await ref.read(authProvider.notifier).register(
            fullName: _nameController.text,
            phone: _phoneController.text,
            password: _passwordController.text,
            email: _emailController.text,
          );
      if (mounted) context.go('/home');
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _errorMessage = failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final busy = authState.isLoading;

    return AuthScaffold(
      showBack: true,
      eyebrow: 'CREATE ACCOUNT',
      title: 'Join Zvingo',
      subtitle: 'Save addresses, track deliveries and reorder in seconds.',
      footer: Text(
        'By creating an account you agree to Zvingo\'s Terms of Service and '
        'Privacy Policy.',
        textAlign: TextAlign.center,
        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
      ),
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: ZvStaggeredList(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            gap: AppSpacing.md,
            children: [
              if (_errorMessage != null)
                AuthErrorBanner(message: _errorMessage!),
              ZvTextField(
                label: 'Full name',
                hint: 'Tinashe Moyo',
                controller: _nameController,
                enabled: !busy,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                prefixIcon: Icons.person_outline_rounded,
                autofillHints: const [AutofillHints.name],
                validator: (value) {
                  final name = value?.trim() ?? '';
                  if (name.isEmpty) return 'Enter your full name';
                  if (name.length < 2) {
                    return 'That is a little short — enter your full name';
                  }
                  return null;
                },
              ),
              ZvPhoneField(
                controller: _phoneController,
                enabled: !busy,
                helper:
                    'We text your delivery updates and one-time codes here.',
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.telephoneNumber],
                validator: ZvPhone.validate,
              ),
              ZvTextField(
                label: 'Email address',
                hint: 'you@example.com',
                controller: _emailController,
                enabled: !busy,
                optionalLabel: true,
                helper: 'For receipts. You can add it later.',
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                prefixIcon: Icons.mail_outline_rounded,
                autofillHints: const [AutofillHints.email],
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (email.isEmpty) return null;
                  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                    return 'That email address is missing an @ or a domain';
                  }
                  return null;
                },
              ),
              ZvTextField(
                label: 'Password',
                hint: 'At least ${ZvPasswordPolicy.minLength} characters',
                controller: _passwordController,
                enabled: !busy,
                obscureText: true,
                textInputAction: TextInputAction.done,
                prefixIcon: Icons.lock_outline_rounded,
                autofillHints: const [AutofillHints.newPassword],
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _register(),
                validator: ZvPasswordPolicy.validate,
              ),
              ZvPasswordChecklist(password: _passwordController.text),
              ZvButton.primary(
                label: 'Create account',
                loading: busy,
                onPressed: busy ? null : _register,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      'Already have an account?',
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                  ZvButton.tertiary(
                    label: 'Sign in',
                    onPressed: busy
                        ? null
                        : () {
                            if (context.canPop()) {
                              context.pop();
                            } else {
                              context.go('/login');
                            }
                          },
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
