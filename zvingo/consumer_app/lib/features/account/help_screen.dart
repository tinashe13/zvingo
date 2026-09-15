import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/auth/auth_provider.dart';
import 'package:consumer_app/features/order/orders_screen.dart'
    show consumerOrdersProvider;

/// How Zvingo support can be reached.
///
/// These are the addresses already published in the app's own FAQ copy. They
/// are constants rather than a remote config because a support channel that
/// only works when the API is up is useless precisely when it is needed.
class SupportContact {
  const SupportContact._();

  static const String email = 'support@zvingo.com';
  static const String whatsapp = '+263 78 000 0000';
  static const String hours = 'Every day, 08:00 – 22:00 CAT';
}

class _Faq {
  const _Faq(this.question, this.answer, this.keywords);

  final String question;
  final String answer;
  final List<String> keywords;
}

const List<_Faq> _faqs = [
  _Faq(
    'Where is my order?',
    'Open the Orders tab and tap the order that is in progress. You will see '
        'the live status, the driver on the map once they collect, and an '
        'estimated arrival time that updates as they ride.',
    ['track', 'late', 'driver', 'eta', 'delivery'],
  ),
  _Faq(
    'My order is late. What now?',
    'Kitchens get busy and traffic happens, so the ETA moves. If it has been '
        'more than 15 minutes past the latest estimate, contact support with '
        'your order number — the Get help with an order button below attaches '
        'it for you.',
    ['late', 'delay', 'slow', 'waiting'],
  ),
  _Faq(
    'How do I pay?',
    'Zvingo charges mobile money through Paynow — EcoCash, OneMoney or '
        'InnBucks. When you place an order, a prompt arrives on your phone and '
        'you approve it there with your own PIN. Zvingo never sees or stores '
        'your PIN, and there is no card payment.',
    ['pay', 'payment', 'ecocash', 'onemoney', 'innbucks', 'card', 'money'],
  ),
  _Faq(
    'Something was missing or wrong in my order',
    'Report it from the order itself, while the details are still attached. '
        'Open the order, then use Get help with an order below. Refunds are '
        'assessed against the order and paid back to the wallet that was '
        'charged.',
    ['missing', 'wrong', 'refund', 'cold', 'item'],
  ),
  _Faq(
    'How do refunds work?',
    'Approved refunds go back to the mobile-money wallet that paid. Paynow '
        'usually settles within three working days; your bank or network may '
        'take a little longer to show it.',
    ['refund', 'money back', 'cancel', 'charged'],
  ),
  _Faq(
    'How do I change my delivery address?',
    'Tap the address at the top of the home screen, or go to Account → Saved '
        'addresses. Adding delivery instructions and a pin on the map is the '
        'single best way to stop a driver phoning you.',
    ['address', 'location', 'move', 'pin', 'directions'],
  ),
  _Faq(
    'How do I change my password?',
    'Account → Manage account → Change password. We text a reset code to your '
        'mobile number. Changing your password signs out every other device, '
        'which is what you want if you think someone else had access.',
    ['password', 'login', 'security', 'reset', 'hacked'],
  ),
  _Faq(
    'How do I delete my account?',
    'Account → Manage account → Delete account. We will tell you exactly what '
        'is removed and what has to be kept for tax and payment records before '
        'anything happens.',
    ['delete', 'close', 'remove', 'account', 'privacy', 'gdpr'],
  ),
];

/// The help centre: searchable answers, order-specific help, and a real way to
/// reach a person.
class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key});

  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_Faq> get _matches {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _faqs;
    return _faqs
        .where((faq) =>
            faq.question.toLowerCase().contains(query) ||
            faq.answer.toLowerCase().contains(query) ||
            faq.keywords.any((k) => k.contains(query)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;

    return ZvScreen(
      title: 'Help and support',
      fallbackRoute: '/account',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xxl,
        ),
        children: [
          ZvSearchField(
            controller: _searchController,
            hint: 'Search help — refund, late, password…',
            onChanged: (value) => setState(() => _query = value),
            onClear: () => setState(() => _query = ''),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_query.trim().isEmpty) ...[
            ZvCard(
              onTap: () => _openOrderHelp(context),
              color: AppColors.actionDefault,
              borderColor: AppColors.actionDefault,
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: AppColors.brandLime,
                      borderRadius: AppRadius.mdAll,
                    ),
                    child: const Icon(Icons.receipt_long_rounded,
                        color: AppColors.neutral900),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Get help with an order',
                          style: AppTextStyles.h3
                              .copyWith(color: AppColors.textOnDark),
                        ),
                        const SizedBox(height: AppSpacing.xxxs),
                        Text(
                          'Missing item, late delivery, wrong charge',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.neutral300),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textOnDark),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const ZvSectionHeader(
              title: 'Common questions',
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          if (matches.isEmpty)
            ZvEmptyState(
              icon: Icons.search_off_rounded,
              title: 'No answer for "${_query.trim()}"',
              message: 'Try a different word, or talk to our team — they can '
                  'look at your specific order.',
              actionLabel: 'Contact support',
              onAction: () => _openContactSheet(context),
            )
          else
            ZvStaggeredList(
              gap: AppSpacing.xs,
              children: matches.map((faq) => _FaqTile(faq: faq)).toList(),
            ),
          const SizedBox(height: AppSpacing.xl),
          ZvCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Still stuck?', style: AppTextStyles.h3),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Our team answers ${SupportContact.hours}.',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.md),
                ZvButton.primary(
                  label: 'Contact support',
                  icon: Icons.support_agent_rounded,
                  onPressed: () => _openContactSheet(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Pick a recent order, then jump straight into it: the order screen is
  /// where the status, the receipt and the driver actually live.
  Future<void> _openOrderHelp(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final orders = ref.watch(consumerOrdersProvider);
          return ZvSheet(
            title: 'Which order?',
            subtitle: 'We will open it so the details go with your question.',
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.5,
              ),
              child: orders.when(
                loading: () => const ZvSkeletonList.tiles(count: 3),
                error: (error, _) => ZvErrorState(
                  error: error,
                  onRetry: () => ref.invalidate(consumerOrdersProvider),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return ZvEmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No orders yet',
                      message: 'Once you have ordered, order-specific help '
                          'appears here.',
                      actionLabel: 'Contact support anyway',
                      onAction: () {
                        Navigator.pop(sheetContext);
                        _openContactSheet(context);
                      },
                    );
                  }
                  final recent = list.take(8).toList();
                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    itemCount: recent.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.xs),
                    itemBuilder: (context, index) {
                      final order = recent[index];
                      final id = (order['id'] ?? order['_id'] ?? '').toString();
                      final state = (order['state'] ?? '').toString();
                      final restaurant =
                          (order['restaurant_name'] ?? 'Your order').toString();
                      return ZvCard(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          context.push('/order/$id');
                        },
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    restaurant,
                                    style: AppTextStyles.bodyStrong,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: AppSpacing.xxxs),
                                  Text(
                                    'Order ${_shortId(id)}',
                                    style: AppTextStyles.tabular(
                                            AppTextStyles.caption)
                                        .copyWith(
                                            color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            if (state.isNotEmpty)
                              ZvStatusChip.orderState(state, compact: true),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  static String _shortId(String id) =>
      id.length <= 8 ? id : '…${id.substring(id.length - 8)}';

  Future<void> _openContactSheet(BuildContext context) async {
    final profile = ref.read(userProfileProvider).valueOrNull;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => ZvSheet(
        title: 'Contact support',
        subtitle: SupportContact.hours,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _ContactRow(
                icon: Icons.mail_outline_rounded,
                title: 'Email us',
                value: SupportContact.email,
                copyLabel: 'Email address copied',
              ),
              const SizedBox(height: AppSpacing.xs),
              const _ContactRow(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'WhatsApp',
                value: SupportContact.whatsapp,
                copyLabel: 'WhatsApp number copied',
              ),
              const SizedBox(height: AppSpacing.md),
              if (profile != null)
                ZvButton.secondary(
                  label: 'Copy my account reference',
                  icon: Icons.badge_outlined,
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(
                        text: 'Zvingo account: ${profile.fullName} '
                            '(${profile.displayPhone})',
                      ),
                    );
                    if (!sheetContext.mounted) return;
                    Navigator.pop(sheetContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Account reference copied — paste it into your '
                          'message so support can find you.',
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}

/// A support channel with a working Copy action.
///
/// Copying rather than launching: the app has no `url_launcher` dependency, and
/// a button that silently fails to open a mail client is worse than one that
/// reliably puts the address on the clipboard. See the C4 report.
class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.copyLabel,
  });

  final IconData icon;
  final String title;
  final String value;
  final String copyLabel;

  @override
  Widget build(BuildContext context) {
    return ZvCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(copyLabel)));
      },
      semanticLabel: 'Copy $title, $value',
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: AppRadius.smAll,
            ),
            child: Icon(icon, size: 20, color: AppColors.textSecondary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.bodyStrong),
                const SizedBox(height: AppSpacing.xxxs),
                Text(
                  value,
                  style: AppTextStyles.tabular(AppTextStyles.caption)
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const Icon(Icons.copy_rounded, size: 18, color: AppColors.neutral400),
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.faq});

  final _Faq faq;

  @override
  Widget build(BuildContext context) {
    return ZvCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          title: Text(faq.question, style: AppTextStyles.h3),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              faq.answer,
              style:
                  AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
