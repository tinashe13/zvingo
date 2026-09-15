import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/address/address_provider.dart';
import 'package:consumer_app/features/address/address_search_sheet.dart';
import 'package:consumer_app/features/address/map_pin_screen.dart';
import 'package:consumer_app/features/address/saved_address.dart';

/// Add or edit a delivery address.
///
/// The order of the screen is the order of the decisions: *where* (search, my
/// location, or a dropped pin), then *what to call it*, then *how to get in* —
/// which is the part that actually decides whether the food arrives.
class AddAddressScreen extends ConsumerStatefulWidget {
  const AddAddressScreen({super.key, this.existing});

  final SavedAddress? existing;

  @override
  ConsumerState<AddAddressScreen> createState() => _AddAddressScreenState();
}

class _AddAddressScreenState extends ConsumerState<AddAddressScreen> {
  static const List<String> _presetLabels = ['Home', 'Work', 'Other'];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelController;
  late final TextEditingController _addressController;
  late final TextEditingController _accessController;
  late final TextEditingController _instructionsController;

  String _selectedLabel = 'Home';
  double? _lat;
  double? _lng;
  bool _isDefault = false;
  bool _saving = false;
  bool _locating = false;
  bool _pinAdjusted = false;

  bool get isEditing => widget.existing != null;
  bool get hasPoint => _lat != null && _lng != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _labelController = TextEditingController();
    _addressController = TextEditingController(text: existing?.address ?? '');
    _accessController = TextEditingController(text: existing?.accessNote ?? '');
    _instructionsController =
        TextEditingController(text: existing?.instructions ?? '');
    _lat = existing?.lat;
    _lng = existing?.lng;
    _isDefault = existing?.isDefault ?? false;

    if (existing != null) {
      final matches = _presetLabels
          .where((l) => l.toLowerCase() == existing.label.toLowerCase());
      if (matches.isNotEmpty) {
        _selectedLabel = matches.first;
      } else {
        _selectedLabel = 'Other';
        _labelController.text = existing.label;
      }
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    _addressController.dispose();
    _accessController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final result = await AddressSearchSheet.show(
      context,
      initialQuery: _addressController.text.trim(),
    );
    if (result == null || !mounted) return;
    setState(() {
      _addressController.text = result.displayName;
      _lat = result.lat;
      _lng = result.lng;
      _pinAdjusted = false;
    });
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      final current = await ref.refresh(currentLocationAddressProvider.future);
      if (!mounted) return;
      setState(() {
        _addressController.text = current.address;
        _lat = current.lat;
        _lng = current.lng;
        _pinAdjusted = false;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'We could not get your location. Switch location on for Zvingo, '
            'or search for the address instead.',
          ),
          action: SnackBarAction(label: 'Search', onPressed: _search),
        ),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _adjustPin() async {
    // Default the map to the city centre of Harare when nothing is set yet, so
    // the user always has somewhere to start dragging from.
    final start = PinnedPoint(
      lat: _lat ?? -17.8252,
      lng: _lng ?? 31.0335,
    );
    final result = await MapPinScreen.push(
      context,
      initial: start,
      addressLine: _addressController.text.trim().isEmpty
          ? null
          : _addressController.text.trim(),
    );
    if (result == null || !mounted) return;
    setState(() {
      _lat = result.lat;
      _lng = result.lng;
      _pinAdjusted = true;
    });
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!hasPoint) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'We still need the spot on the map. Search for the address, use '
            'your current location, or drop a pin.',
          ),
          action: SnackBarAction(label: 'Drop a pin', onPressed: _adjustPin),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    final label = _selectedLabel == 'Other'
        ? _labelController.text.trim()
        : _selectedLabel;

    String? trimmedOrNull(TextEditingController c) {
      final value = c.text.trim();
      return value.isEmpty ? null : value;
    }

    final address = SavedAddress(
      id: widget.existing?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      label: label,
      address: _addressController.text.trim(),
      lat: _lat!,
      lng: _lng!,
      isDefault: _isDefault,
      accessNote: trimmedOrNull(_accessController),
      instructions: trimmedOrNull(_instructionsController),
    );

    final notifier = ref.read(savedAddressesProvider.notifier);
    if (isEditing) {
      await notifier.updateAddress(address);
    } else {
      await notifier.addAddress(address);
    }
    notifier.selectAddress(address);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isEditing ? '${address.label} updated' : '${address.label} saved',
        ),
      ),
    );
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/addresses');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ZvScreen(
      title: isEditing ? 'Edit address' : 'Add address',
      fallbackRoute: '/addresses',
      footer: ZvStickyFooter(
        child: ZvButton.primary(
          label: isEditing ? 'Save changes' : 'Save address',
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xxl,
          ),
          children: [
            const _SectionLabel(
              step: '1',
              title: 'Where are we delivering?',
            ),
            const SizedBox(height: AppSpacing.sm),
            ZvTextField(
              label: 'Address',
              hint: 'Tap to search for a street or suburb',
              controller: _addressController,
              readOnly: true,
              onTap: _search,
              maxLines: 2,
              minLines: 1,
              prefixIcon: Icons.search_rounded,
              suffix: const Icon(Icons.chevron_right_rounded,
                  color: AppColors.neutral400),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Search for your address to continue'
                  : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: ZvButton.secondary(
                    label: 'My location',
                    icon: Icons.my_location_rounded,
                    loading: _locating,
                    onPressed: _locating ? null : _useCurrentLocation,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: ZvButton.secondary(
                    label: hasPoint ? 'Adjust pin' : 'Drop a pin',
                    icon: Icons.push_pin_outlined,
                    onPressed: _adjustPin,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _PinStatus(
              hasPoint: hasPoint,
              adjusted: _pinAdjusted,
              lat: _lat,
              lng: _lng,
            ),
            const SizedBox(height: AppSpacing.xxl),
            const _SectionLabel(step: '2', title: 'What should we call it?'),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: _presetLabels.map((label) {
                final selected = _selectedLabel == label;
                return ChoiceChip(
                  label: Text(label),
                  avatar: Icon(
                    _iconForLabel(label),
                    size: 16,
                    color: selected
                        ? AppColors.textOnDark
                        : AppColors.textSecondary,
                  ),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedLabel = label),
                );
              }).toList(),
            ),
            if (_selectedLabel == 'Other') ...[
              const SizedBox(height: AppSpacing.sm),
              ZvTextField(
                label: 'Name this address',
                hint: 'Gym, Mum\'s house, the office…',
                controller: _labelController,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 24,
                validator: (value) {
                  if (_selectedLabel != 'Other') return null;
                  return (value == null || value.trim().isEmpty)
                      ? 'Give this address a name'
                      : null;
                },
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),
            const _SectionLabel(
              step: '3',
              title: 'How does the driver find you?',
              subtitle: 'Optional, but it is what turns a phone call into a '
                  'doorstep delivery.',
            ),
            const SizedBox(height: AppSpacing.sm),
            ZvTextField(
              label: 'Flat, floor or building',
              hint: 'Flat 4B, Gold Crest Block C',
              controller: _accessController,
              optionalLabel: true,
              maxLength: 60,
              prefixIcon: Icons.meeting_room_outlined,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: AppSpacing.sm),
            ZvTextField(
              label: 'Delivery instructions',
              hint: 'Black gate opposite the tuckshop. Ring twice, the dog is '
                  'friendly.',
              controller: _instructionsController,
              optionalLabel: true,
              maxLines: 3,
              minLines: 2,
              maxLength: 200,
              prefixIcon: Icons.notes_rounded,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: AppSpacing.lg),
            ZvCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isDefault,
                onChanged: (value) => setState(() => _isDefault = value),
                title: const Text('Make this my default',
                    style: AppTextStyles.bodyStrong),
                subtitle: Text(
                  'New orders start here unless you change them.',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconForLabel(String label) => switch (label.toLowerCase()) {
        'home' => Icons.home_outlined,
        'work' => Icons.work_outline_rounded,
        _ => Icons.place_outlined,
      };
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.step,
    required this.title,
    this.subtitle,
  });

  final String step;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: AppColors.actionDefault,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            step,
            style: AppTextStyles.caption.copyWith(color: AppColors.textOnDark),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.h3),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xxxs),
                Text(
                  subtitle!,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Says, in words and not just colour, whether we have a precise point yet.
class _PinStatus extends StatelessWidget {
  const _PinStatus({
    required this.hasPoint,
    required this.adjusted,
    required this.lat,
    required this.lng,
  });

  final bool hasPoint;
  final bool adjusted;
  final double? lat;
  final double? lng;

  @override
  Widget build(BuildContext context) {
    final tone = hasPoint ? ZvTone.success : ZvTone.warning;
    final title = !hasPoint
        ? 'No map point yet'
        : adjusted
            ? 'Pin placed by you'
            : 'Located from the address';
    final detail = !hasPoint
        ? 'Search, use your location, or drop a pin so the driver knows where '
            'to ride.'
        : '${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}'
            '${adjusted ? '' : ' — adjust the pin if your gate is elsewhere.'}';

    return ZvAnimatedSwap(
      valueKey: '$hasPoint$adjusted',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: tone.surface,
          borderRadius: AppRadius.mdAll,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              hasPoint ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              size: 20,
              color: tone.foreground,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.bodyStrong
                        .copyWith(color: tone.foreground),
                  ),
                  const SizedBox(height: AppSpacing.xxxs),
                  Text(
                    detail,
                    style: AppTextStyles.tabular(AppTextStyles.caption)
                        .copyWith(color: tone.foreground),
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
