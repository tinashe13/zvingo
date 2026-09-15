import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/app_motion.dart';
import '../../core/app_spacing.dart';
import '../../core/app_text_styles.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/widgets.dart';
import 'app_info.dart';
import 'legal_document_screen.dart' show CopyableRow;

/// Driver help.
///
/// Answers the questions drivers actually ask support, in the app, so the
/// answer is available at 11pm when nobody picks up. Every answer here
/// describes behaviour this app genuinely has — nothing describes a feature
/// that does not exist.
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  static const List<({String question, String answer})> _faqs = [
    (
      question: 'Why is my pay different from what I expected?',
      answer:
          'Open Earnings, tap any day, then tap a delivery. You get the exact '
          'split for that trip: the delivery fee the customer paid, Zvingo’s '
          'share of it, and your tip. Those lines are checked to add up to what '
          'you were paid — if they ever do not, the app says so and gives '
          'you the order reference to quote.',
    ),
    (
      question: 'Do I keep all of a tip?',
      answer:
          'Yes. Tips pass through to you in full. Zvingo takes a share of the '
          'delivery fee only, never of a tip.',
    ),
    (
      question: 'How is the delivery fee worked out?',
      answer:
          'By distance, in blocks. A longer trip crosses into another block and '
          'pays more. Your per-delivery breakdown shows the base fare and the '
          'distance portion separately whenever it can be split exactly.',
    ),
    (
      question: 'What is "cash you are holding"?',
      answer:
          'When a customer pays cash, you take the money and Zvingo owes you '
          'your share of it. The figure on your Earnings screen is what is owed '
          'back to Zvingo. Settle it at the end of your shift — and do not '
          'carry more than you have to.',
    ),
    (
      question: 'I set my schedule but I am not getting offers.',
      answer:
          'Your schedule tells Zvingo when you plan to work so we can plan '
          'cover. It does not put you online. You still have to go online on '
          'the home screen for offers to reach you.',
    ),
    (
      question: 'Why did my rating not change after a good delivery?',
      answer:
          'Ratings are an average of every customer who has rated you, so one '
          'delivery moves it less the more you have done. Not every customer '
          'rates, either — most do not.',
    ),
    (
      question: 'My acceptance rate says "—". Is that bad?',
      answer:
          'No. A dash means there is not enough to measure yet. Zvingo shows a '
          'dash rather than a 0% that would be misleading.',
    ),
    (
      question: 'Do I get a notification when an offer comes in?',
      answer:
          'In this version, offers arrive while the app is open. Keep Zvingo in '
          'the foreground while you are online. Phone push notifications are '
          'not switched on yet.',
    ),
    (
      question: 'The app logged me out mid-shift. Why?',
      answer:
          'It should not. Zvingo renews your session in the background. If you '
          'do get sent to the sign-in screen, any delivery you were on is still '
          'assigned to you — sign back in and it will be there.',
    ),
    (
      question: 'How do I change my vehicle?',
      answer:
          'Account → Vehicle details. Your plate and vehicle type are what '
          'the customer sees when they are waiting for you, so keep them right.',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final padding = AppSpacing.screenPaddingOf(context);
    final auth = ref.watch(authProvider);

    return Scaffold(
      appBar: const DriverAppBar(
        title: 'Help',
        subtitle: 'Answers, and how to reach a person',
        fallbackRoute: '/account',
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            padding,
            AppSpacing.lg,
            padding,
            AppSpacing.section,
          ),
          children: [
            StaggeredEntrance(
              index: 0,
              child: Text(
                'Common questions',
                style: AppTextStyles.onSurface(context, AppTextStyles.h2),
              ),
            ),
            Gap.md,
            for (var i = 0; i < _faqs.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: StaggeredEntrance(
                  index: i + 1,
                  child: _FaqTile(
                    question: _faqs[i].question,
                    answer: _faqs[i].answer,
                  ),
                ),
              ),
            Gap.section,
            Text(
              'Still stuck?',
              style: AppTextStyles.onSurface(context, AppTextStyles.h2),
            ),
            Gap.md,
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: AppSpacing.cardDecoration(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (SupportContact.hasAny) ...[
                    Text(
                      'Reach Zvingo driver support. Tap to copy.',
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.textSecondary),
                    ),
                    Gap.md,
                    if (SupportContact.phone.isNotEmpty) ...[
                      const CopyableRow(
                        icon: Icons.phone_outlined,
                        label: 'Driver support',
                        value: SupportContact.phone,
                      ),
                      Gap.sm,
                    ],
                    if (SupportContact.whatsApp.isNotEmpty) ...[
                      const CopyableRow(
                        icon: Icons.chat_outlined,
                        label: 'WhatsApp',
                        value: SupportContact.whatsApp,
                      ),
                      Gap.sm,
                    ],
                    if (SupportContact.email.isNotEmpty)
                      const CopyableRow(
                        icon: Icons.mail_outline_rounded,
                        label: 'Email',
                        value: SupportContact.email,
                      ),
                  ] else
                    Text(
                      'Zvingo driver support is reached through your driver '
                      'group or at the Zvingo office. No support line is '
                      'configured in this build of the app.',
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  Gap.lg,
                  Divider(height: 1, color: AppColors.borderOf(context)),
                  Gap.lg,
                  Text(
                    'When you contact support, give them this — it tells '
                    'them exactly which app and which account.',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  Gap.sm,
                  _SupportSummary(
                    text: [
                      AppInfo.supportReference,
                      if (auth.phone.isNotEmpty) 'phone ${auth.phone}',
                      if (auth.userId != null) 'id ${auth.userId}',
                    ].join(' · '),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FaqTile extends StatefulWidget {
  final String question;
  final String answer;

  const _FaqTile({required this.question, required this.answer});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      expanded: _open,
      label: widget.question,
      child: TapScale(
        onTap: () => setState(() => _open = !_open),
        child: AnimatedContainer(
          duration: AppMotion.durationOf(context, AppMotion.fast),
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: AppSpacing.cardDecoration(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      widget.question,
                      style: AppTextStyles.bodyStrong
                          .copyWith(color: AppColors.textPrimary),
                    ),
                  ),
                  Gap.hSm,
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: AppMotion.durationOf(context, AppMotion.fast),
                    child: const Icon(
                      Icons.expand_more_rounded,
                      size: 22,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox(width: double.infinity),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Text(
                    widget.answer,
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ),
                crossFadeState: _open
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: AppMotion.durationOf(context, AppMotion.base),
                sizeCurve: AppMotion.standard,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupportSummary extends StatelessWidget {
  final String text;

  const _SupportSummary({required this.text});

  @override
  Widget build(BuildContext context) {
    return TapScale(
      semanticLabel: 'Copy support details',
      onTap: () {
        Clipboard.setData(ClipboardData(text: text));
        DriverSnack.show(
          context,
          'Support details copied',
          icon: Icons.content_copy_rounded,
        );
      },
      child: Container(
        width: double.infinity,
        constraints:
            const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceMutedOf(context),
          borderRadius: AppSpacing.brMd,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textPrimary),
              ),
            ),
            Gap.hSm,
            const Icon(Icons.content_copy_rounded,
                size: 18, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
