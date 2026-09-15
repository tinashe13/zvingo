/// Post-delivery ratings — the consumer half of `POST /rating/orders/{id}/review`.
///
/// Contract (`backend/app/rating/router.py`):
/// * `restaurant_rating` — required, 1–5
/// * `driver_rating` — optional, 1–5, **rejected with 400 when the order had
///   no courier**, so the driver section only renders when one was assigned
/// * `comment` — optional, ≤ 2000 characters
/// * `tags` — optional, ≤ 10 strings
///
/// One review per order is enforced by a unique index on `order_id`; the sheet
/// is never offered for an order that already has one (see
/// [orderReviewProvider]), and a racing double-submit surfaces the server's
/// own "already been reviewed" message rather than a crash.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/order/order_models.dart';
import 'package:consumer_app/features/order/order_providers.dart';

/// Structured feedback offered alongside the stars. Kept short and concrete —
/// a tag a person can recognise in half a second beats a free-text box nobody
/// fills in.
const List<String> _positiveRestaurantTags = [
  'Delicious',
  'Hot on arrival',
  'Great packaging',
  'Order was correct',
];
const List<String> _negativeRestaurantTags = [
  'Food was cold',
  'Items missing',
  'Wrong order',
  'Took too long',
];
const List<String> _positiveDriverTags = [
  'Friendly',
  'Fast',
  'Careful with the food',
  'Easy to find',
];
const List<String> _negativeDriverTags = [
  'Hard to reach',
  'Slow',
  'Food was shaken up',
  'Rude',
];

/// Opens the rating sheet. Resolves true when a review was submitted.
Future<bool> showOrderRatingSheet(
  BuildContext context, {
  required TrackedOrder order,
  String? restaurantName,
}) async {
  final submitted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    builder: (_) => OrderRatingSheet(
      order: order,
      restaurantName: restaurantName,
    ),
  );
  return submitted ?? false;
}

/// The rating form. Prefer [showOrderRatingSheet].
class OrderRatingSheet extends ConsumerStatefulWidget {
  const OrderRatingSheet({
    super.key,
    required this.order,
    this.restaurantName,
  });

  final TrackedOrder order;
  final String? restaurantName;

  @override
  ConsumerState<OrderRatingSheet> createState() => _OrderRatingSheetState();
}

class _OrderRatingSheetState extends ConsumerState<OrderRatingSheet> {
  final TextEditingController _comment = TextEditingController();
  final Set<String> _tags = <String>{};

  int _restaurantRating = 0;
  int _driverRating = 0;
  bool _submitting = false;
  bool _done = false;
  String? _error;

  bool get _hasDriver => widget.order.driver != null;

  String get _restaurantLabel => widget.restaurantName ?? 'the restaurant';

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  List<String> _tagsFor({required bool driver}) {
    final rating = driver ? _driverRating : _restaurantRating;
    if (rating == 0) return const [];
    final positive = rating >= 4;
    if (driver) {
      return positive ? _positiveDriverTags : _negativeDriverTags;
    }
    return positive ? _positiveRestaurantTags : _negativeRestaurantTags;
  }

  Future<void> _submit() async {
    if (_restaurantRating == 0 || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(orderActionsProvider).submitReview(
            widget.order.id,
            restaurantRating: _restaurantRating,
            driverRating: _hasDriver && _driverRating > 0 ? _driverRating : null,
            comment: _comment.text,
            tags: _tags.toList(),
          );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _done = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = orderErrorMessage(
          error,
          fallback: "We couldn't save your rating. Please try again.",
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.92;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets),
        child: _done ? _buildThanks(context) : _buildForm(context),
      ),
    );
  }

  Widget _buildThanks(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // §4.3: one deliberate celebration, once, never looping.
          SizedBox(
            height: 120,
            child: Lottie.asset(
              'assets/animations/success.json',
              repeat: false,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.check_circle_rounded,
                size: 72,
                color: AppColors.brandGreen,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Thank you',
            style: AppTextStyles.h1,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _restaurantRating >= 4
                ? 'We passed your $_restaurantRating-star rating straight to '
                    '$_restaurantLabel${_hasDriver && _driverRating > 0 ? ' and ${widget.order.driver!.firstName}' : ''}.'
                : 'Sorry that fell short. Your feedback goes to $_restaurantLabel '
                    'and our team reviews every rating below four stars.',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          ZvButton.primary(
            label: 'Done',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final canSubmit = _restaurantRating > 0 && !_submitting;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: 36,
          height: 4,
          decoration: const BoxDecoration(
            color: AppColors.neutral300,
            borderRadius: AppRadius.fullAll,
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            children: [
              const Text('How was it?', style: AppTextStyles.h1),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Order ${widget.order.shortReference} from $_restaurantLabel.',
                style:
                    AppTextStyles.body.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xl),

              _RatingBlock(
                title: 'The food',
                subtitle: 'How was the order from $_restaurantLabel?',
                icon: Icons.restaurant_rounded,
                rating: _restaurantRating,
                semanticPrefix: 'Rate the food',
                onChanged: (value) => setState(() {
                  _restaurantRating = value;
                  _tags.removeWhere(
                    (t) =>
                        _positiveRestaurantTags.contains(t) ||
                        _negativeRestaurantTags.contains(t),
                  );
                }),
              ),
              if (_tagsFor(driver: false).isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _TagWrap(
                  options: _tagsFor(driver: false),
                  selected: _tags,
                  onToggle: (tag) => setState(() {
                    if (!_tags.remove(tag) && _tags.length < 10) _tags.add(tag);
                  }),
                ),
              ],

              if (_hasDriver) ...[
                const SizedBox(height: AppSpacing.xxl),
                _RatingBlock(
                  title: 'Your courier',
                  subtitle:
                      'How did ${widget.order.driver!.firstName} do? Optional.',
                  icon: Icons.delivery_dining_rounded,
                  rating: _driverRating,
                  semanticPrefix: 'Rate your courier',
                  onChanged: (value) => setState(() {
                    _driverRating = value;
                    _tags.removeWhere(
                      (t) =>
                          _positiveDriverTags.contains(t) ||
                          _negativeDriverTags.contains(t),
                    );
                  }),
                ),
                if (_tagsFor(driver: true).isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _TagWrap(
                    options: _tagsFor(driver: true),
                    selected: _tags,
                    onToggle: (tag) => setState(() {
                      if (!_tags.remove(tag) && _tags.length < 10) {
                        _tags.add(tag);
                      }
                    }),
                  ),
                ],
              ],

              const SizedBox(height: AppSpacing.xxl),
              ZvTextField(
                label: 'Anything else?',
                hint: 'Tell us what stood out',
                controller: _comment,
                optionalLabel: true,
                maxLines: 4,
                minLines: 3,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
              ),

              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                _InlineError(message: _error!),
              ],
            ],
          ),
        ),
        ZvStickyFooter(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ZvButton.primary(
                label: 'Submit rating',
                loading: _submitting,
                onPressed: canSubmit ? _submit : null,
                disabledReason: _restaurantRating == 0
                    ? 'Tap a star for the food to submit.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.xxs),
              ZvButton.tertiary(
                label: 'Not now',
                fullWidth: true,
                onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A titled star row.
class _RatingBlock extends StatelessWidget {
  const _RatingBlock({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.rating,
    required this.onChanged,
    required this.semanticPrefix,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final int rating;
  final ValueChanged<int> onChanged;
  final String semanticPrefix;

  static const List<String> _words = [
    '',
    'Poor',
    'Not great',
    'Fine',
    'Good',
    'Excellent',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.xs),
            Text(title, style: AppTextStyles.h3),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          subtitle,
          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        ZvStarInput(
          value: rating,
          onChanged: onChanged,
          semanticPrefix: semanticPrefix,
        ),
        if (rating > 0) ...[
          const SizedBox(height: AppSpacing.xs),
          ZvAnimatedSwap(
            valueKey: rating,
            child: Text(
              _words[rating],
              style: AppTextStyles.bodyStrong
                  .copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ],
    );
  }
}

/// Five tappable stars with 48×48 targets and a real accessible name.
class ZvStarInput extends StatelessWidget {
  const ZvStarInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticPrefix = 'Rate',
    this.size = 34,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final String semanticPrefix;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(5, (index) {
        final star = index + 1;
        final filled = star <= value;
        return Semantics(
          button: true,
          selected: filled,
          label: '$semanticPrefix $star out of 5',
          excludeSemantics: true,
          child: InkResponse(
            onTap: () => onChanged(star),
            radius: AppSpacing.minTapTarget / 2,
            child: SizedBox(
              width: AppSpacing.minTapTarget,
              height: AppSpacing.minTapTarget,
              child: AnimatedScale(
                scale: filled ? 1 : 0.88,
                duration: context.motion(AppMotion.fast),
                curve: context.motionCurve(AppMotion.spring),
                child: Icon(
                  filled ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: size,
                  color: filled ? AppColors.rating : AppColors.neutral300,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Selectable feedback tags.
class _TagWrap extends StatelessWidget {
  const _TagWrap({
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: options.map((tag) {
        final isOn = selected.contains(tag);
        return ZvTapScale(
          onTap: () => onToggle(tag),
          semanticLabel: isOn ? '$tag, selected' : tag,
          child: AnimatedContainer(
            duration: context.motion(AppMotion.fast),
            curve: context.motionCurve(AppMotion.standard),
            constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: isOn ? AppColors.actionDefault : AppColors.surfaceMuted,
              borderRadius: AppRadius.fullAll,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isOn) ...[
                  const Icon(Icons.check_rounded,
                      size: 15, color: AppColors.textOnDark),
                  const SizedBox(width: AppSpacing.xxs),
                ],
                Text(
                  tag,
                  style: AppTextStyles.caption.copyWith(
                    color:
                        isOn ? AppColors.textOnDark : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Plain-language inline error, never a raw exception (§5.5).
class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: const BoxDecoration(
        color: AppColors.errorSurface,
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 18, color: AppColors.error),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.caption.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
