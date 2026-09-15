import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/core/api_client.dart';
import 'package:consumer_app/features/account/delete_account_screen.dart';
import 'package:consumer_app/features/account/help_screen.dart'
    show SupportContact;
import 'package:consumer_app/features/auth/auth_provider.dart';
import 'package:consumer_app/features/auth/password_reset_screen.dart';

/// Edit the account: name, email, password, and the exits.
///
/// Two deliberate absences, both backend gaps rather than design choices (both
/// specified in the C4 report):
///
/// * **Phone number is read-only.** It is the account's identity — it is what
///   Paynow charges and what the driver rings — and there is no endpoint to
///   change it. `PATCH /auth/me` accepts `full_name` and `email` only, and
///   changing a phone safely needs an OTP round-trip on the *new* number.
///   Rather than a control that cannot work, the field explains how to change
///   it.
/// * **No profile photo.** `User` has no avatar field and the app has no image
///   picker dependency, so the avatar is drawn from initials. An upload button
///   here would be decoration attached to nothing.
class ManageAccountScreen extends ConsumerStatefulWidget {
  const ManageAccountScreen({super.key});

  @override
  ConsumerState<ManageAccountScreen> createState() =>
      _ManageAccountScreenState();
}

class _ManageAccountScreenState extends ConsumerState<ManageAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  bool _seeded = false;
  bool _saving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _seed(ZvUserProfile profile) {
    if (_seeded) return;
    _seeded = true;
    _nameController.text = profile.fullName;
    _emailController.text = profile.email ?? '';
  }

  bool _isDirty(ZvUserProfile profile) =>
      _nameController.text.trim() != profile.fullName ||
      _emailController.text.trim() != (profile.email ?? '');

  Future<void> _save(ZvUserProfile profile) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();
    try {
      await ref.read(apiClientProvider).patch<dynamic>('/auth/me', data: {
        'full_name': _nameController.text.trim(),
        if (email.isNotEmpty) 'email': email,
      });
      ref.invalidate(userProfileProvider);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your details are saved')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = AuthFailure.from(
          error,
          fallback: 'We could not save your details. Please try again.',
        ).message;
      });
    }
  }

  Future<void> _changePassword(ZvUserProfile profile) async {
    final done = await PasswordResetScreen.push(context, phone: profile.phone);
    if (done != true || !mounted) return;
    // Completing a reset revokes every token, this device's included.
    await ref.read(authProvider.notifier).signOut();
    if (!mounted) return;
    context.go('/login');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Password changed. Sign in with your new password.'),
      ),
    );
  }

  void _explainPhoneChange(ZvUserProfile profile) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => ZvSheet(
        title: 'Changing your mobile number',
        subtitle: 'Currently ${profile.displayPhone}',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Your mobile number is how you sign in, how your driver reaches '
                'you, and which wallet Paynow charges. Changing it has to be '
                'verified on the new number, so our support team does it with '
                'you rather than it happening from a single tap.',
                style:
                    AppTextStyles.body.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Email ${SupportContact.email} from the address on your '
                'account, or message us on WhatsApp — ${SupportContact.hours}.',
                style:
                    AppTextStyles.body.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              ZvButton.primary(
                label: 'Open help and support',
                icon: Icons.support_agent_rounded,
                onPressed: () {
                  Navigator.pop(sheetContext);
                  context.push('/help');
                },
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);

    return ZvScreen(
      title: 'Manage account',
      fallbackRoute: '/account',
      footer: profileAsync.hasValue
          ? ZvStickyFooter(
              child: ZvButton.primary(
                label: 'Save changes',
                loading: _saving,
                onPressed: _saving || !_isDirty(profileAsync.requireValue)
                    ? null
                    : () => _save(profileAsync.requireValue),
                disabledReason: _saving || _isDirty(profileAsync.requireValue)
                    ? null
                    : 'Nothing to save yet — edit a field above.',
              ),
            )
          : null,
      child: profileAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: ZvTextBlockSkeleton(lines: 8),
        ),
        error: (error, _) => ZvErrorState(
          error: error,
          title: 'We could not load your details',
          onRetry: () => ref.invalidate(userProfileProvider),
        ),
        data: (profile) {
          _seed(profile);

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xxl,
              ),
              children: [
                Center(child: _InitialsAvatar(profile: profile)),
                const SizedBox(height: AppSpacing.xl),
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: const BoxDecoration(
                      color: AppColors.errorSurface,
                      borderRadius: AppRadius.mdAll,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 20, color: AppColors.error),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: AppTextStyles.caption
                                .copyWith(color: AppColors.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                ZvTextField(
                  label: 'Full name',
                  hint: 'The name your driver will ask for',
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  prefixIcon: Icons.person_outline_rounded,
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    final name = value?.trim() ?? '';
                    if (name.isEmpty) return 'Enter your full name';
                    if (name.length < 2) {
                      return 'That is a little short — enter your full name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                ZvTextField(
                  label: 'Email address',
                  hint: 'you@example.com',
                  controller: _emailController,
                  optionalLabel: true,
                  helper: 'Where receipts go. Not used to sign in.',
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: Icons.mail_outline_rounded,
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (email.isEmpty) return null;
                    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                        .hasMatch(email)) {
                      return 'That email address is missing an @ or a domain';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                _ReadOnlyField(
                  label: 'Mobile number',
                  value: profile.displayPhone,
                  icon: Icons.smartphone_rounded,
                  badge: const ZvStatusChip(
                    label: 'Verified',
                    tone: ZvTone.success,
                    icon: Icons.verified_rounded,
                    compact: true,
                  ),
                  helper: 'Your sign-in and delivery number.',
                  actionLabel: 'How do I change this?',
                  onAction: () => _explainPhoneChange(profile),
                ),
                const SizedBox(height: AppSpacing.xxl),
                const ZvSectionHeader(
                  title: 'Security',
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: AppSpacing.sm),
                ZvCard(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: AppIconTile(
                    icon: Icons.lock_outline_rounded,
                    title: 'Change password',
                    subtitle: 'We text a code to ${profile.displayPhone}',
                    onTap: () => _changePassword(profile),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                const ZvSectionHeader(
                  title: 'Leaving Zvingo',
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: AppSpacing.sm),
                ZvCard(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: AppIconTile(
                    icon: Icons.delete_forever_outlined,
                    title: 'Delete account',
                    subtitle: 'Permanently remove your Zvingo account',
                    destructive: true,
                    onTap: () => DeleteAccountScreen.push(context),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Initials, not a photo: there is nowhere on the server to put a photo, and a
/// camera button attached to nothing is worse than no camera button.
class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.profile});

  final ZvUserProfile profile;

  @override
  Widget build(BuildContext context) {
    final initials = profile.initials;

    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: const BoxDecoration(
            color: AppColors.brandLime,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: initials.isEmpty
              ? const Icon(Icons.person_rounded,
                  size: 40, color: AppColors.neutral900)
              : Text(
                  initials,
                  style: AppTextStyles.display
                      .copyWith(color: AppColors.neutral900),
                ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(profile.fullName, style: AppTextStyles.h2),
        const SizedBox(height: AppSpacing.xxxs),
        Text(
          profile.displayPhone,
          style: AppTextStyles.tabular(AppTextStyles.caption)
              .copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// A field that shows a value the user cannot edit here, and says why plus
/// where they can (§5.1: a disabled control is never unexplained).
class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({
    required this.label,
    required this.value,
    required this.icon,
    required this.helper,
    this.badge,
    this.actionLabel,
    this.onAction,
  });

  final String label;
  final String value;
  final IconData icon;
  final String helper;
  final Widget? badge;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.caption),
        const SizedBox(height: AppSpacing.xs),
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: const BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: AppRadius.mdAll,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  value,
                  style: AppTextStyles.tabular(AppTextStyles.body),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badge != null) badge!,
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              child: Text(
                helper,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textSecondary),
              ),
            ),
            if (actionLabel != null && onAction != null)
              ZvButton.tertiary(label: actionLabel!, onPressed: onAction),
          ],
        ),
      ],
    );
  }
}
