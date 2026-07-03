import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/features/auth/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    setState(() => _errorMessage = null);
    
    if (_nameController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter your full name');
      return;
    }
    if (_phoneController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter your phone number');
      return;
    }
    if (_passwordController.text.length < 4) {
      setState(() => _errorMessage = 'Password must be at least 4 characters');
      return;
    }

    final success = await ref.read(authProvider.notifier).register(
          _nameController.text.trim(),
          _emailController.text.trim(),
          _phoneController.text.trim(),
          _passwordController.text,
        );
    if (success && mounted) {
      context.go('/home');
    } else if (mounted) {
      final authState = ref.read(authProvider);
      if (authState.hasError) {
        setState(() => _errorMessage = 'Registration failed. Phone or email may already be in use.');
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
            // ── Hero Top Section ────────────────────────
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.25,
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
                        Positioned(top: 50, left: 30, child: _foodCircle(Icons.fastfood, 55)),
                        Positioned(top: 40, right: 50, child: _foodCircle(Icons.local_pizza, 45)),
                        Positioned(
                          bottom: 40,
                          left: MediaQuery.of(context).size.width * 0.4,
                          child: _foodCircle(Icons.restaurant_menu, 60),
                        ),
                        Positioned(bottom: 30, right: 30, child: _foodCircle(Icons.cake, 40)),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 0, left: 0, right: 0, height: 40,
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
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 8,
                    child: IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),

            // ── Form ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Create Account', style: AppTextStyles.headlineLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Sign up to get started with Zvingo',
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 20),

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
                          Expanded(
                            child: Text(_errorMessage!,
                                style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Full Name
                  _fieldLabel('FULL NAME'),
                  TextField(
                    controller: _nameController,
                    style: AppTextStyles.bodyLarge,
                    decoration: const InputDecoration(
                      hintText: 'John Doe',
                      prefixIcon: Icon(Icons.person_outline, color: AppColors.textHint, size: 20),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Email
                  _fieldLabel('EMAIL ADDRESS'),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: AppTextStyles.bodyLarge,
                    decoration: const InputDecoration(
                      hintText: 'your@email.com (optional)',
                      prefixIcon: Icon(Icons.email_outlined, color: AppColors.textHint, size: 20),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Phone
                  _fieldLabel('PHONE NUMBER'),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    style: AppTextStyles.bodyLarge,
                    decoration: const InputDecoration(
                      hintText: '+263 77 000 0000',
                      prefixIcon: Icon(Icons.phone_outlined, color: AppColors.textHint, size: 20),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Password
                  _fieldLabel('PASSWORD'),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: AppTextStyles.bodyLarge,
                    decoration: InputDecoration(
                      hintText: '••••••',
                      prefixIcon: const Icon(Icons.lock_outline, color: AppColors.textHint, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: AppColors.textSecondary, size: 20,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    onSubmitted: (_) => _handleRegister(),
                  ),
                  const SizedBox(height: 32),

                  // Register Button
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: authState.isLoading ? null : _handleRegister,
                      child: authState.isLoading
                          ? const SizedBox(
                              width: 24, height: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                            )
                          : Text('Create Account', style: AppTextStyles.button),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Already have account?
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Already have an account? ',
                          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
                      GestureDetector(
                        onTap: () => context.pop(),
                        child: Text('Sign in',
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

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text,
          style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.5, color: AppColors.textSecondary)),
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
