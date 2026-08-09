import 'package:consumer_app/common/widgets/custom_text_field.dart';
import 'package:consumer_app/common/widgets/primary_button.dart';
import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/features/auth/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _errorMessage = null);
    final success = await ref.read(authProvider.notifier).loginWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
        );
    if (success && mounted) {
      context.go('/home');
    } else if (mounted && ref.read(authProvider).hasError) {
      setState(() => _errorMessage = 'Invalid email or password');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      body: Form(
        key: _formKey,
        child: AutofillGroup(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.34,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.primaryDark,
                              AppColors.primary,
                              Color(0xFF19A974),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                          top: 54,
                          left: 28,
                          child: _foodCircle(Icons.restaurant_rounded, 58)),
                      Positioned(
                          top: 38,
                          right: 34,
                          child: _foodCircle(Icons.local_pizza_rounded, 48)),
                      Positioned(
                          bottom: 62,
                          left: 62,
                          child: _foodCircle(Icons.local_cafe_rounded, 44)),
                      Positioned(
                        top: 102,
                        left: MediaQuery.sizeOf(context).width * 0.37,
                        child: _foodCircle(Icons.lunch_dining_rounded, 72),
                      ),
                      Positioned(
                          bottom: 42,
                          right: 28,
                          child: _foodCircle(Icons.icecream_rounded, 52)),
                      Positioned(
                        left: 28,
                        top: MediaQuery.paddingOf(context).top + 4,
                        child: Text(
                          'Zvingo',
                          style: AppTextStyles.headlineMedium
                              .copyWith(color: AppColors.white),
                        ),
                      ),
                      const Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 54,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, AppColors.white],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primarySurface,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'WELCOME BACK',
                          style: AppTextStyles.labelSmall
                              .copyWith(color: AppColors.primaryDark),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('Good food is close',
                          style: AppTextStyles.headlineLarge),
                      const SizedBox(height: 8),
                      Text(
                        'Sign in to reorder favourites and track deliveries.',
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 28),
                      if (_errorMessage != null) ...[
                        _ErrorBanner(message: _errorMessage!),
                        const SizedBox(height: 16),
                      ],
                      CustomTextField(
                        label: 'Email address',
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        hint: 'your@email.com',
                        prefixIcon: const Icon(Icons.mail_outline_rounded),
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          if (email.isEmpty) return 'Enter your email address';
                          if (!email.contains('@') || !email.contains('.')) {
                            return 'Enter a valid email address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      CustomTextField(
                        label: 'Password',
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        hint: 'Enter your password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        validator: (value) => (value?.isEmpty ?? true)
                            ? 'Enter your password'
                            : null,
                        onFieldSubmitted: (_) => _handleLogin(),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      const SizedBox(height: 24),
                      PrimaryButton(
                        text: 'Sign in',
                        onPressed: _handleLogin,
                        isLoading: authState.isLoading,
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'New to Zvingo? ',
                            style: AppTextStyles.bodyMedium
                                .copyWith(color: AppColors.textSecondary),
                          ),
                          TextButton(
                            onPressed: () => context.push('/register'),
                            child: const Text('Create an account'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _foodCircle(IconData icon, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.white.withOpacity(0.16),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.white.withOpacity(0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(icon, size: size * 0.45, color: AppColors.white),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
