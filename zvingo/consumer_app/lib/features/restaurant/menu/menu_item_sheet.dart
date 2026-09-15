/// Item customisation — options, add-ons, quantity and notes.
///
/// Two rules drive the whole sheet:
///
/// * **The price is always the truth.** Every option carries a price delta and
///   the running total re-counts (never hard-swaps) through [ZvAnimatedCount],
///   so the number on the button is the number that lands in the cart.
/// * **An invalid configuration cannot be added, and the reason is always on
///   screen.** The primary button carries its own `disabledReason`, and the
///   first unsatisfied group is flagged inline — there is no disabled button
///   here without a sentence next to it saying what to do.
library;

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/cart/cart_provider.dart';
import 'package:consumer_app/features/cart/money.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';
import 'package:flutter/material.dart';

/// Open the customisation sheet. Returns the configured line, or null if the
/// customer backed out.
Future<CartItem?> showMenuItemSheet(
  BuildContext context, {
  required MenuItem item,
  required Restaurant restaurant,
  CartItem? editing,
}) {
  return showModalBottomSheet<CartItem>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    builder: (_) => MenuItemSheet(
      item: item,
      restaurant: restaurant,
      editing: editing,
    ),
  );
}

class MenuItemSheet extends StatefulWidget {
  const MenuItemSheet({
    super.key,
    required this.item,
    required this.restaurant,
    this.editing,
  });

  final MenuItem item;
  final Restaurant restaurant;

  /// When set, the sheet edits an existing cart line instead of adding one.
  final CartItem? editing;

  @override
  State<MenuItemSheet> createState() => _MenuItemSheetState();
}

class _MenuItemSheetState extends State<MenuItemSheet> {
  late int _quantity;
  late final TextEditingController _notes;
  final _pageController = PageController();
  int _imageIndex = 0;
  bool _showValidation = false;

  /// groupId -> selected option ids.
  final Map<String, Set<String>> _selected = <String, Set<String>>{};

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    _quantity = editing?.quantity ?? 1;
    _notes = TextEditingController(text: editing?.specialInstructions ?? '');

    for (final group in widget.item.optionGroups) {
      final chosen = <String>{};
      if (editing != null) {
        for (final choice in editing.choices) {
          if (choice.groupId == group.id) chosen.add(choice.id);
        }
      } else {
        for (final option in group.options) {
          if (option.isDefault && option.isAvailable) {
            chosen.add(option.id);
            if (group.isSingleChoice) break;
          }
        }
      }
      _selected[group.id] = chosen;
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // ── Derived state ──────────────────────────────────────────────

  List<CartOptionChoice> get _choices {
    final result = <CartOptionChoice>[];
    for (final group in widget.item.optionGroups) {
      for (final option in group.options) {
        if (_selected[group.id]?.contains(option.id) ?? false) {
          result.add(CartOptionChoice(
            groupId: group.id,
            groupLabel: group.name,
            id: option.id,
            label: option.name,
            priceDelta: option.priceDelta,
          ));
        }
      }
    }
    return result;
  }

  Money get _unitPrice =>
      widget.item.basePrice +
      _choices.map((c) => c.priceDelta).sum(currency: kDefaultCurrency);

  Money get _lineTotal => _unitPrice * _quantity;

  /// The first group that is not yet satisfied, if any.
  MenuOptionGroup? get _firstUnsatisfiedGroup {
    for (final group in widget.item.optionGroups) {
      final count = _selected[group.id]?.length ?? 0;
      if (count < group.minSelections) return group;
    }
    return null;
  }

  String? get _blockingReason {
    if (!widget.restaurant.isOpen) {
      return '${widget.restaurant.name} is ${widget.restaurant.availability.label.toLowerCase()}, '
          'so nothing can be added right now.';
    }
    if (!widget.item.isAvailable) {
      return '${widget.item.name} is sold out. It will come back when the '
          'kitchen restocks it.';
    }
    final group = _firstUnsatisfiedGroup;
    if (group != null) {
      final needed = group.minSelections - (_selected[group.id]?.length ?? 0);
      return needed == 1
          ? 'Choose an option under "${group.name}" to continue.'
          : 'Choose $needed more under "${group.name}" to continue.';
    }
    return null;
  }

  bool get _canAdd => _blockingReason == null;

  // ── Interaction ────────────────────────────────────────────────

  void _toggle(MenuOptionGroup group, MenuOption option) {
    if (!option.isAvailable) return;
    setState(() {
      final chosen = _selected.putIfAbsent(group.id, () => <String>{});
      if (group.isSingleChoice) {
        chosen
          ..clear()
          ..add(option.id);
      } else if (chosen.contains(option.id)) {
        chosen.remove(option.id);
      } else if (chosen.length < group.maxSelections) {
        chosen.add(option.id);
      } else {
        // At the cap — say so rather than ignoring the tap.
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              'You can choose up to ${group.maxSelections} under '
              '"${group.name}". Remove one to swap.',
            ),
          ));
      }
    });
  }

  void _submit() {
    if (!_canAdd) {
      setState(() => _showValidation = true);
      final group = _firstUnsatisfiedGroup;
      if (group != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(_blockingReason!),
          ));
      }
      return;
    }
    final notes = _notes.text.trim();
    Navigator.of(context).pop(
      CartItem(
        itemId: widget.item.id,
        name: widget.item.name,
        unitBasePrice: widget.item.basePrice,
        quantity: _quantity,
        choices: _choices,
        specialInstructions: notes.isEmpty ? null : notes,
        restaurantId: widget.restaurant.id,
        restaurantName: widget.restaurant.name,
        imageUrl: widget.item.imageUrl,
        restaurantImage: widget.restaurant.imageUrl,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isEditing = widget.editing != null;
    final blocked = _blockingReason;

    return ZvSheet(
      title: item.name,
      subtitle: widget.restaurant.name,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ZvStepper(
                value: _quantity,
                min: 1,
                max: 50,
                semanticLabel: 'Quantity of ${item.name}',
                onChanged: (value) => setState(() => _quantity = value),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ZvAnimatedCount.money(
                    value: _lineTotal.major,
                    currency: _lineTotal.symbol,
                    style: AppTextStyles.moneyLarge,
                    semanticLabel: 'Total for this item',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ZvButton.primary(
            label: isEditing ? 'Update item' : 'Add to cart',
            icon: isEditing
                ? Icons.check_rounded
                : Icons.add_shopping_cart_rounded,
            onPressed: _canAdd ? _submit : null,
            disabledReason: blocked,
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.images.isNotEmpty) _gallery(item),
            if (!item.isAvailable) ...[
              const SizedBox(height: AppSpacing.md),
              const _Notice(
                tone: ZvTone.warning,
                icon: Icons.remove_shopping_cart_outlined,
                title: 'Sold out',
                message:
                    'The kitchen has run out of this one today. Everything else '
                    'on the menu is still available.',
              ),
            ] else if (!widget.restaurant.isOpen) ...[
              const SizedBox(height: AppSpacing.md),
              _Notice(
                tone: ZvTone.warning,
                icon: Icons.schedule_rounded,
                title: widget.restaurant.availability.label,
                message:
                    'You can look through the menu, but nothing can be added '
                    'until the restaurant reopens.',
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(item.name, style: AppTextStyles.h2),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(item.basePrice.format(), style: AppTextStyles.moneyLarge),
              ],
            ),
            if (item.description.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                item.description,
                style: AppTextStyles.body
                    .copyWith(color: AppColors.textSecondary, height: 1.5),
              ),
            ],
            if (item.approvalPercent != null) ...[
              const SizedBox(height: AppSpacing.sm),
              ZvMetaRow(items: [
                ZvMetaItem(
                  icon: Icons.thumb_up_alt_outlined,
                  label: '${item.approvalPercent}% liked this',
                ),
                if (item.approvalCount != null)
                  ZvMetaItem(
                    icon: Icons.reviews_outlined,
                    label: '${item.approvalCount} ratings',
                  ),
              ]),
            ],
            for (final group in item.optionGroups) ...[
              const SizedBox(height: AppSpacing.xl),
              _OptionGroupBlock(
                group: group,
                selected: _selected[group.id] ?? const <String>{},
                showError: _showValidation &&
                    (_selected[group.id]?.length ?? 0) < group.minSelections,
                onToggle: (option) => _toggle(group, option),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            ZvTextField(
              label: 'Special instructions',
              optionalLabel: true,
              hint: 'e.g. no onions, extra napkins',
              controller: _notes,
              maxLines: 3,
              minLines: 2,
              maxLength: 200,
              helper: 'The kitchen sees this with your order. '
                  'Substitutions are not guaranteed.',
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  Widget _gallery(MenuItem item) {
    final images = item.images;
    return Column(
      children: [
        ClipRRect(
          borderRadius: AppRadius.lgAll,
          child: AspectRatio(
            aspectRatio: 1,
            child: images.length == 1
                ? ZvNetworkImage(
                    url: images.first,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.zero,
                    fallbackLabel: item.name,
                    fallbackIcon: Icons.restaurant_menu_rounded,
                  )
                : PageView.builder(
                    controller: _pageController,
                    itemCount: images.length,
                    onPageChanged: (i) => setState(() => _imageIndex = i),
                    itemBuilder: (_, i) => ZvNetworkImage(
                      url: images[i],
                      fit: BoxFit.cover,
                      borderRadius: BorderRadius.zero,
                      fallbackLabel: item.name,
                      fallbackIcon: Icons.restaurant_menu_rounded,
                    ),
                  ),
          ),
        ),
        if (images.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < images.length; i++)
                AnimatedContainer(
                  duration: context.motion(AppMotion.fast),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _imageIndex ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _imageIndex
                        ? AppColors.actionDefault
                        : AppColors.neutral300,
                    borderRadius: AppRadius.fullAll,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _OptionGroupBlock extends StatelessWidget {
  const _OptionGroupBlock({
    required this.group,
    required this.selected,
    required this.showError,
    required this.onToggle,
  });

  final MenuOptionGroup group;
  final Set<String> selected;
  final bool showError;
  final ValueChanged<MenuOption> onToggle;

  @override
  Widget build(BuildContext context) {
    final satisfied = selected.length >= group.minSelections;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(group.name, style: AppTextStyles.h3)),
            const SizedBox(width: AppSpacing.xs),
            ZvStatusChip(
              label: group.ruleLabel,
              compact: true,
              uppercase: false,
              tone: group.isRequired
                  ? (satisfied ? ZvTone.success : ZvTone.warning)
                  : ZvTone.neutral,
              icon: group.isRequired
                  ? (satisfied
                      ? Icons.check_rounded
                      : Icons.priority_high_rounded)
                  : null,
            ),
          ],
        ),
        if (showError) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 16, color: AppColors.error),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Text(
                  group.minSelections == 1
                      ? 'Pick one to continue.'
                      : 'Pick ${group.minSelections} to continue.',
                  style: AppTextStyles.caption.copyWith(color: AppColors.error),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        ZvCard(
          padding: EdgeInsets.zero,
          borderColor: showError ? AppColors.error : AppColors.border,
          child: Column(
            children: [
              for (var i = 0; i < group.options.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _OptionRow(
                  option: group.options[i],
                  isSelected: selected.contains(group.options[i].id),
                  isSingleChoice: group.isSingleChoice,
                  onTap: () => onToggle(group.options[i]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.isSelected,
    required this.isSingleChoice,
    required this.onTap,
  });

  final MenuOption option;
  final bool isSelected;
  final bool isSingleChoice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final delta = option.priceDelta;
    final enabled = option.isAvailable;
    return ZvTapScale(
      onTap: enabled ? onTap : null,
      semanticLabel: option.name,
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Icon(
              isSingleChoice
                  ? (isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked)
                  : (isSelected
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded),
              size: 22,
              color: !enabled
                  ? AppColors.actionDisabledFg
                  : (isSelected
                      ? AppColors.actionDefault
                      : AppColors.neutral400),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                option.name,
                style:
                    (isSelected ? AppTextStyles.bodyStrong : AppTextStyles.body)
                        .copyWith(
                  color: enabled
                      ? AppColors.textPrimary
                      : AppColors.actionDisabledFg,
                  decoration: enabled ? null : TextDecoration.lineThrough,
                ),
              ),
            ),
            if (!enabled)
              Text('Sold out',
                  style:
                      AppTextStyles.caption.copyWith(color: AppColors.warning))
            else if (delta.isPositive)
              Text('+${delta.format()}', style: AppTextStyles.money)
            else if (delta.isNegative)
              Text(delta.format(),
                  style:
                      AppTextStyles.money.copyWith(color: AppColors.success)),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.tone,
    required this.icon,
    required this.title,
    required this.message,
  });

  final ZvTone tone;
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: tone.surface,
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: tone.foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTextStyles.bodyStrong
                        .copyWith(color: tone.foreground)),
                const SizedBox(height: AppSpacing.xxs),
                Text(message,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
