import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/features/address/address_provider.dart';
import 'package:consumer_app/features/address/address_search_sheet.dart';
import 'package:consumer_app/features/address/saved_address.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AddAddressScreen extends ConsumerStatefulWidget {
  final SavedAddress? existing;

  const AddAddressScreen({super.key, this.existing});

  @override
  ConsumerState<AddAddressScreen> createState() => _AddAddressScreenState();
}

class _AddAddressScreenState extends ConsumerState<AddAddressScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _labelController;
  late TextEditingController _addressController;
  bool _isDefault = false;
  bool _isSaving = false;
  bool _isLocating = false;
  double? _lat;
  double? _lng;
  String _selectedLabel = 'Home';
  final _labels = ['Home', 'Work', 'Other'];

  bool get isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _labelController = TextEditingController(text: e?.label ?? '');
    _addressController = TextEditingController(text: e?.address ?? '');
    _isDefault = e?.isDefault ?? false;
    _lat = e?.lat;
    _lng = e?.lng;
    if (e != null) {
      _selectedLabel = _labels.contains(e.label) ? e.label : 'Other';
      if (_selectedLabel == 'Other') {
        _labelController.text = e.label;
      }
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      final currentAddr = await ref.read(currentLocationAddressProvider.future);
      if (mounted) {
        setState(() {
          _addressController.text = currentAddr.address;
          _lat = currentAddr.lat;
          _lng = currentAddr.lng;
          _isLocating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLocating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not get location: $e')),
        );
      }
    }
  }

  /// Opens the address search sheet and populates fields from the result.
  Future<void> _openAddressSearch() async {
    final result = await AddressSearchSheet.show(context);
    if (result != null && mounted) {
      setState(() {
        _addressController.text = result.displayName;
        _lat = result.lat;
        _lng = result.lng;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_lat == null || _lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please search and select an address, or use current location.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final label = _selectedLabel == 'Other'
        ? _labelController.text.trim()
        : _selectedLabel;

    final address = SavedAddress(
      id: widget.existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      label: label,
      address: _addressController.text.trim(),
      lat: _lat!,
      lng: _lng!,
      isDefault: _isDefault,
    );

    final notifier = ref.read(savedAddressesProvider.notifier);
    if (isEditing) {
      await notifier.updateAddress(address);
    } else {
      await notifier.addAddress(address);
    }

    // Also set as the active delivery location
    notifier.selectAddress(address);

    if (mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          isEditing ? 'Edit Address' : 'Add Address',
          style: AppTextStyles.titleLarge,
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Use current location button
              OutlinedButton.icon(
                onPressed: _isLocating ? null : _useCurrentLocation,
                icon: _isLocating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location, size: 20),
                label: Text(_isLocating ? 'Getting location...' : 'Use Current Location'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.info,
                  side: const BorderSide(color: AppColors.info),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Label selection
              Text('Label', style: AppTextStyles.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _labels.map((label) {
                  final selected = _selectedLabel == label;
                  return ChoiceChip(
                    label: Text(label),
                    selected: selected,
                    selectedColor: AppColors.primarySurface,
                    labelStyle: AppTextStyles.bodyMedium.copyWith(
                      color: selected ? AppColors.primary : AppColors.textSecondary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    side: BorderSide(
                      color: selected ? AppColors.primary : AppColors.border,
                    ),
                    onSelected: (_) => setState(() => _selectedLabel = label),
                  );
                }).toList(),
              ),

              // Custom label field (visible when "Other" is selected)
              if (_selectedLabel == 'Other') ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _labelController,
                  decoration: _inputDecoration('Custom label (e.g. Gym, School)'),
                  validator: (v) {
                    if (_selectedLabel == 'Other' && (v == null || v.trim().isEmpty)) {
                      return 'Enter a label';
                    }
                    return null;
                  },
                ),
              ],

              const SizedBox(height: 20),

              // Address field — tappable, opens the search sheet
              Text('Address', style: AppTextStyles.titleSmall),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _openAddressSearch,
                child: AbsorbPointer(
                  child: TextFormField(
                    controller: _addressController,
                    decoration: _inputDecoration('Tap to search for an address').copyWith(
                      suffixIcon: const Icon(Icons.search, color: AppColors.primary, size: 22),
                    ),
                    maxLines: 2,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Select an address';
                      return null;
                    },
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Coordinates status
              if (_lat != null && _lng != null)
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: AppColors.success, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Location pinpointed',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.success),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.textHint, size: 16),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Search for an address or use current location',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 20),

              // Default toggle
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Set as default address', style: AppTextStyles.bodyMedium),
                subtitle: Text(
                  'This address will be selected automatically',
                  style: AppTextStyles.bodySmall,
                ),
                value: _isDefault,
                activeColor: AppColors.primary,
                onChanged: (v) => setState(() => _isDefault = v),
              ),

              const SizedBox(height: 32),

              // Save button
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 2,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          isEditing ? 'Update Address' : 'Save Address',
                          style: AppTextStyles.button,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}
