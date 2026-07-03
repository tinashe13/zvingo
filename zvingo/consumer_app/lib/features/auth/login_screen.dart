import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/features/auth/auth_provider.dart';
import 'package:consumer_app/common/widgets/primary_button.dart';
import 'package:consumer_app/common/widgets/custom_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
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
    setState(() => _errorMessage = null);
    final success = await ref.read(authProvider.notifier).loginWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
        );
    if (success && mounted) {
      context.go('/home');
    } else if (mounted) {
      final authState = ref.read(authProvider);
      if (authState.hasError) {
        setState(() => _errorMessage = 'Invalid email or password');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Hero Food Image ─────────────────────────
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.38,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.primary.withOpacity(0.15),
                          AppColors.primaryLight.withOpacity(0.10),
                          Colors.orange.shade50,
                        ],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(top: 60, left: 30, child: _foodCircle(Icons.restaurant, 60)),
                        Positioned(top: 40, right: 40, child: _foodCircle(Icons.local_pizza, 50)),
                        Positioned(bottom: 60, left: 60, child: _foodCircle(Icons.local_cafe, 45)),
                        Positioned(
                          top: 100,
                          left: MediaQuery.of(context).size.width * 0.35,
                          child: _foodCircle(Icons.lunch_dining, 70),
                        ),
                        Positioned(bottom: 40, right: 30, child: _foodCircle(Icons.icecream, 55)),
                        Positioned(bottom: 90, right: 100, child: _foodCircle(Icons.local_dining, 40)),
                        Positioned(top: 70, right: 120, child: _foodCircle(Icons.cake, 35)),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 0, left: 0, right: 0, height: 60,
                    child: Container(
                      decoration: const BoxDecoration(
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

            // ── Login Form ──────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Login', style: AppTextStyles.headlineLarge),
                  const SizedBox(height: 32),

                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                          const SizedBox(width: 8),
                          Text(_errorMessage!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Email field
                  CustomTextField(
                    label: 'EMAIL ADDRESS',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    hint: 'your@email.com',
                    suffixIcon: _emailController.text.isNotEmpty
                        ? const Icon(Icons.check_circle, color: AppColors.primary, size: 20)
                        : null,
                  ),
                  const SizedBox(height: 24),

                  // Password field
                  CustomTextField(
                    label: 'PASSWORD',
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    hint: '••••••',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {},
                      child: Text(
                        'Forgot Password?',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Sign In Button
                  PrimaryButton(
                    text: 'Sign In',
                    onPressed: _handleLogin,
                    isLoading: authState.isLoading,
                    isFullWidth: true,
                  ),
                  const SizedBox(height: 24),

                  // Create Account link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Don't have account? ",
                          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
                      GestureDetector(
                        onTap: () => context.push('/register'),
                        child: Text('Create new account.',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.primary, fontWeight: FontWeight.w600,
                            )),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _foodCircle(IconData icon, double size) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: AppColors.white.withOpacity(0.85),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Icon(icon, size: size * 0.45, color: AppColors.primary),
    );
  }
}
