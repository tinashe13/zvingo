import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/account/account_deletion_provider.dart';
import 'package:consumer_app/features/account/help_screen.dart'
    show SupportContact;
import 'package:consumer_app/features/auth/auth_provider.dart';

/// Delete your Zvingo account.
///
/// Required by Google Play's user-data policy: an app that lets people create
/// an account must let them delete it from inside the app (finding X4).
///
/// The screen is deliberately unhurried. It names what goes, what legally has
/// to stay, and refuses to proceed while an order is still moving. The
/// irreversible step goes through [showZvConfirmSheet] with the consequence
/// spelled out, per §5.4.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(builder: (_) => const DeleteAccountScreen()),
    );
  }

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _reasonController = TextEditingController();

  bool _understood = false;
  bool _working = false;
  AccountDeletionOutcome? _outcome;
  String? _failureMessage;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _confirmAndDelete(int inFlight) async {
    final confirmed = await showZvConfirmSheet(
      context,
      title: 'Delete your Zvingo account?',
      consequence:
          'Your profile, saved addresses, delivery notes and saved stores are '
          'removed and you are signed out everywhere. Past receipts and '
          'payment records are kept for the period Zimbabwean tax law '
          'requires. This cannot be undone — a new account starts from '
          'scratch.',
      confirmLabel: 'Delete my account',
      cancelLabel: 'Keep my account',
      icon: Icons.delete_forever_rounded,
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _working = true;
      _outcome = null;
      _failureMessage = null;
    });

    final result = await ref.read(accountDeletionProvider.notifier).submit(
          reason: _reasonController.text.trim(),
        );

    if (!mounted) return;
    setState(() {
      _working = false;
      _outcome = result.outcome;
      _failureMessage = result.message;
    });

    if (result.succeeded) {
      // The account is gone; clear the device and land on sign-in.
      await ref.read(authProvider.notifier).signOut();
      if (!mounted) return;
      context.go('/login');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your Zvingo account has been deleted.')),
      );
    }
  }

  Future<void> _copyManualRequest() async {
    final profile = ref.read(userProfileProvider).valueOrNull;
    final reason = _reasonController.text.trim();
    final body = StringBuffer()
      ..writeln('Account deletion request')
      ..writeln('Name: ${profile?.fullName ?? '(not loaded)'}')
      ..writeln('Mobile: ${profile?.displayPhone ?? '(not loaded)'}')
      ..writeln('Email: ${profile?.email ?? '(none on account)'}');
    if (reason.isNotEmpty) body.writeln('Reason: $reason');
    body.writeln(
      'I am asking for my Zvingo account and personal data to be deleted.',
    );

    await Clipboard.setData(ClipboardData(text: body.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Request copied. Send it to ${SupportContact.email} from any mail app.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inFlight = ref.watch(inFlightOrderCountProvider);
    final blocked = (inFlight.valueOrNull ?? 0) > 0;
    final canDelete = _understood && !blocked && !_working;

    return ZvScreen(
      title: 'Delete account',
      fallbackRoute: '/account',
      footer: ZvStickyFooter(
        child: ZvButton.destructive(
          label: 'Delete my account',
          icon: Icons.delete_forever_rounded,
          loading: _working,
          onPressed:
              canDelete ? () => _confirmAndDelete(inFlight.valueOrNull ?? 0) : null,
          disabledReason: blocked
              ? 'You have an order on the way. We cannot delete an account '
                  'while food or money is still moving.'
              : !_understood
                  ? 'Tick the box above to confirm you understand.'
                  : null,
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xxl,
        ),
        children: [
          if (blocked)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _Notice(
                tone: ZvTone.warning,
                icon: Icons.delivery_dining_rounded,
                title: 'You have an order on the way',
                body: 'Wait until it is delivered (or cancelled) before '
                    'deleting your account, so the driver and your refund are '
                    'not left in limbo.',
                actionLabel: 'See my orders',
                onAction: () => context.go('/orders'),
              ),
            ),
          if (_outcome == AccountDeletionOutcome.endpointMissing)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _Notice(
                tone: ZvTone.error,
                icon: Icons.cloud_off_rounded,
                title: 'We could not complete this automatically',
                body: 'Zvingo\'s servers cannot action an in-app deletion yet. '
                    'Copy the request below and send it to '
                    '${SupportContact.email} — we act on emailed deletion '
                    'requests within 30 days and will confirm when it is done.',
                actionLabel: 'Copy my deletion request',
                onAction: _copyManualRequest,
              ),
            ),
          if (_outcome == AccountDeletionOutcome.needsReauth)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _Notice(
                tone: ZvTone.warning,
                icon: Icons.lock_clock_rounded,
                title: 'Please sign in again',
                body: 'For an action this final we need a fresh sign-in. Sign '
                    'out, sign back in, and come straight back here.',
                actionLabel: 'Sign out now',
                onAction: () async {
                  await ref.read(authProvider.notifier).signOut();
                  if (!context.mounted) return;
                  context.go('/login');
                },
              ),
            ),
          if (_outcome == AccountDeletionOutcome.failed)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _Notice(
                tone: ZvTone.error,
                icon: Icons.error_outline_rounded,
                title: 'That did not go through',
                body: _failureMessage ??
                    'Something went wrong on our side. Check your connection '
                        'and try again — nothing has been deleted.',
              ),
            ),
          const _WhatHappensCard(),
          const SizedBox(height: AppSpacing.md),
          ZvCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Before you go', style: AppTextStyles.h3),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'If something went wrong, our team would rather fix it than '
                  'lose you.',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.md),
                ZvButton.secondary(
                  label: 'Talk to support first',
                  icon: Icons.support_agent_rounded,
                  onPressed: () => context.push('/help'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ZvTextField(
            label: 'Why are you leaving?',
            hint: 'This helps us fix what is broken.',
            controller: _reasonController,
            optionalLabel: true,
            maxLines: 3,
            minLines: 2,
            maxLength: 300,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: AppSpacing.sm),
          ZvCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xxs,
            ),
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _understood,
              onChanged: (value) =>
                  setState(() => _understood = value ?? false),
              title: Text(
                'I understand this permanently deletes my Zvingo account and '
                'cannot be undone.',
                style: AppTextStyles.body,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WhatHappensCard extends StatelessWidget {
  const _WhatHappensCard();

  @override
  Widget build(BuildContext context) {
    return ZvCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What happens when you delete', style: AppTextStyles.h3),
          const SizedBox(height: AppSpacing.md),
          const _Line(
            icon: Icons.delete_outline_rounded,
            tone: ZvTone.error,
            title: 'Removed',
            body: 'Your name, email, phone, saved addresses and delivery '
                'notes, saved stores and notification settings.',
          ),
          const SizedBox(height: AppSpacing.sm),
          const _Line(
            icon: Icons.receipt_long_outlined,
            tone: ZvTone.warning,
            title: 'Kept',
            body: 'Order and payment records, as Zimbabwean tax and '
                'anti-fraud rules require. They are no longer linked to a '
                'usable account.',
          ),
          const SizedBox(height: AppSpacing.sm),
          const _Line(
            icon: Icons.lock_outline_rounded,
            tone: ZvTone.neutral,
            title: 'Signed out everywhere',
            body: 'Every device is signed out immediately. Your phone number '
                'can be used to create a brand-new account later.',
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final ZvTone tone;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: tone.surface,
            borderRadius: AppRadius.smAll,
          ),
          child: Icon(icon, size: 18, color: tone.foreground),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.bodyStrong),
              const SizedBox(height: AppSpacing.xxxs),
              Text(
                body,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.tone,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final ZvTone tone;
  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tone.surface,
        borderRadius: AppRadius.lgAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: tone.foreground, size: 22),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.h3.copyWith(color: tone.foreground),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            body,
            style: AppTextStyles.caption.copyWith(color: tone.foreground),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ZvButton.secondary(label: actionLabel!, onPressed: onAction),
          ],
        ],
      ),
    );
  }
}
