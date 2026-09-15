/// In-app messaging for an order — consumer ↔ courier (and the restaurant,
/// which is the third participant on the same thread server-side).
///
/// Contract (`backend/app/chat/router.py`, mounted at root as `/chat`):
/// * `GET  /chat/orders/{id}/messages?offset=&limit=` → oldest-first list of
///   `{id, order_id, sender_id, sender_role, text, read_by[], created_at}`
/// * `POST /chat/orders/{id}/messages` `{"text": "…"}` → the created message.
///   **409** once the order is `DELIVERED`/`CANCELLED`: the thread becomes
///   read-only rather than disappearing.
/// * `GET  /chat/orders/{id}/stream` → SSE (`connected`, `message`, `ping`)
/// * `GET  /chat/orders/{id}/messages/unread` → `{unread_count}`
/// * `POST /chat/orders/{id}/messages/read` → marks the thread read
///
/// Only the order's three participants can read or post, so there is no
/// client-side access check to get wrong.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/order/order_models.dart';
import 'package:consumer_app/features/order/order_providers.dart';

/// Opens the chat thread for [orderId] as a near-full-height sheet.
Future<void> showOrderChatSheet(
  BuildContext context, {
  required String orderId,
  required String title,
  String? subtitle,
  bool readOnly = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    builder: (_) => OrderChatSheet(
      orderId: orderId,
      title: title,
      subtitle: subtitle,
      readOnly: readOnly,
    ),
  );
}

/// The chat thread. Prefer [showOrderChatSheet].
class OrderChatSheet extends ConsumerStatefulWidget {
  const OrderChatSheet({
    super.key,
    required this.orderId,
    required this.title,
    this.subtitle,
    this.readOnly = false,
  });

  final String orderId;
  final String title;
  final String? subtitle;

  /// True once the order is finished — the thread stays readable but the
  /// composer is replaced with an explanation.
  final bool readOnly;

  @override
  ConsumerState<OrderChatSheet> createState() => _OrderChatSheetState();
}

class _OrderChatSheetState extends ConsumerState<OrderChatSheet> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();

  bool _sending = false;
  String? _sendError;

  @override
  void initState() {
    super.initState();
    // Opening the thread is what marks it read.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(orderChatProvider(widget.orderId).notifier).markRead();
      }
    });
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: context.motion(AppMotion.base),
        curve: context.motionCurve(AppMotion.standard),
      );
    });
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await ref.read(orderChatProvider(widget.orderId).notifier).send(text);
      if (!mounted) return;
      _composer.clear();
      setState(() => _sending = false);
      _scrollToLatest();
      _focus.requestFocus();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sendError = orderErrorMessage(
          error,
          fallback: "That message didn't send. Try again.",
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(orderChatProvider(widget.orderId));
    final myId = ref.watch(currentUserIdProvider).valueOrNull;
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;

    ref.listen<OrderChatState>(orderChatProvider(widget.orderId), (prev, next) {
      if ((prev?.messages.length ?? 0) != next.messages.length) {
        _scrollToLatest();
      }
    });

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.86,
        child: Column(
          children: [
            _Header(
              title: widget.title,
              subtitle: widget.subtitle,
              live: chat.live,
            ),
            Expanded(child: _buildBody(chat, myId)),
            if (_sendError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        size: 16, color: AppColors.error),
                    const SizedBox(width: AppSpacing.xxs),
                    Expanded(
                      child: Text(
                        _sendError!,
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.error),
                      ),
                    ),
                  ],
                ),
              ),
            widget.readOnly ? const _ReadOnlyNotice() : _buildComposer(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(OrderChatState chat, String? myId) {
    if (chat.loading && chat.messages.isEmpty) {
      return const ZvSkeletonList.tiles(
        count: 5,
        padding: EdgeInsets.all(AppSpacing.md),
      );
    }
    if (chat.error != null && chat.messages.isEmpty) {
      return ZvErrorState(
        error: chat.error,
        onRetry: () =>
            ref.read(orderChatProvider(widget.orderId).notifier).retry(),
      );
    }
    if (chat.messages.isEmpty) {
      return ZvEmptyState(
        icon: Icons.forum_rounded,
        title: 'No messages yet',
        message: widget.readOnly
            ? 'Nothing was sent about this order.'
            : 'Send a note about your order — where to meet, gate codes, or '
                'anything the courier should know.',
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      itemCount: chat.messages.length,
      itemBuilder: (context, index) {
        final message = chat.messages[index];
        final previous = index == 0 ? null : chat.messages[index - 1];
        return _MessageBubble(
          message: message,
          mine: message.isMine(myId),
          showSender: previous?.senderId != message.senderId,
        );
      },
    );
  }

  Widget _buildComposer() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: ZvTextField(
                  label: 'Message',
                  hint: 'Type a message',
                  controller: _composer,
                  focusNode: _focus,
                  maxLines: 4,
                  minLines: 1,
                  maxLength: 1000,
                  textInputAction: TextInputAction.send,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: [LengthLimitingTextInputFormatter(1000)],
                  onSubmitted: (_) => _send(),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: ZvIconButton(
                  icon: Icons.send_rounded,
                  tooltip: 'Send message',
                  loading: _sending,
                  background: _composer.text.trim().isEmpty
                      ? AppColors.surfaceMuted
                      : AppColors.actionDefault,
                  foreground: _composer.text.trim().isEmpty
                      ? AppColors.actionDisabledFg
                      : AppColors.textOnDark,
                  onPressed: _composer.text.trim().isEmpty ? null : _send,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(
      {required this.title, required this.subtitle, required this.live});

  final String title;
  final String? subtitle;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: AppTextStyles.h2, maxLines: 1),
                const SizedBox(height: AppSpacing.xxxs),
                Text(
                  live
                      ? (subtitle ?? 'Connected')
                      : '${subtitle == null ? '' : '$subtitle · '}'
                          'Checking for new messages',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          ZvIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Close messages',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surfaceMuted,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const Icon(Icons.lock_outline_rounded,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'This order is finished, so the thread is read-only. '
                  'Need help? Open Help & support from your account.',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.showSender,
  });

  final OrderChatMessage message;
  final bool mine;
  final bool showSender;

  static final DateFormat _time = DateFormat.jm();

  @override
  Widget build(BuildContext context) {
    final stamp = message.createdAt;
    return Padding(
      padding:
          EdgeInsets.only(top: showSender ? AppSpacing.sm : AppSpacing.xxs),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showSender && !mine)
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xs,
                bottom: AppSpacing.xxxs,
              ),
              child: Text(
                message.senderLabel,
                style: AppTextStyles.overline
                    .copyWith(color: AppColors.textSecondary),
              ),
            ),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.75,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: mine ? AppColors.actionDefault : AppColors.surfaceMuted,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(AppRadius.lg),
                topRight: const Radius.circular(AppRadius.lg),
                bottomLeft: Radius.circular(mine ? AppRadius.lg : AppRadius.sm),
                bottomRight:
                    Radius.circular(mine ? AppRadius.sm : AppRadius.lg),
              ),
            ),
            child: Text(
              message.text,
              style: AppTextStyles.body.copyWith(
                color: mine ? AppColors.textOnDark : AppColors.textPrimary,
              ),
            ),
          ),
          if (stamp != null)
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.xxxs,
                left: AppSpacing.xs,
                right: AppSpacing.xs,
              ),
              child: Text(
                _time.format(stamp),
                style: AppTextStyles.tabular(
                  AppTextStyles.caption
                      .copyWith(color: AppColors.textTertiary, fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
