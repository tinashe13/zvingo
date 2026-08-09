import 'dart:async';

import 'package:consumer_app/core/api_client.dart';
import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Result returned when the user picks an address from the search sheet.
class GeocodedAddress {
  final String displayName;
  final double lat;
  final double lng;

  const GeocodedAddress({
    required this.displayName,
    required this.lat,
    required this.lng,
  });
}

/// A modal bottom sheet that lets the user search for an address using the
/// backend's Nominatim geocoding endpoint (`GET /location/geocode`).
///
/// Usage:
/// ```dart
/// final result = await AddressSearchSheet.show(context);
/// if (result != null) { /* use result.displayName, result.lat, result.lng */ }
/// ```
class AddressSearchSheet extends ConsumerStatefulWidget {
  const AddressSearchSheet({super.key});

  static Future<GeocodedAddress?> show(BuildContext context) {
    return showModalBottomSheet<GeocodedAddress>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddressSearchSheet(),
    );
  }

  @override
  ConsumerState<AddressSearchSheet> createState() => _AddressSearchSheetState();
}

class _AddressSearchSheetState extends ConsumerState<AddressSearchSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;

  List<GeocodedAddress> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _results = [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    _debounce =
        Timer(const Duration(milliseconds: 350), () => _search(value.trim()));
  }

  Future<void> _search(String query) async {
    try {
      final dio = ref.read(apiClientProvider);
      final response = await dio.get(
        '/location/geocode',
        queryParameters: {'q': query},
      );
      final data = response.data as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _results = data
            .map((e) => GeocodedAddress(
                  displayName: e['display_name'] as String,
                  lat: (e['lat'] as num).toDouble(),
                  lng: (e['lng'] as num).toDouble(),
                ))
            .toList();
        _loading = false;
        _error = _results.isEmpty
            ? 'No addresses found. Try a different search.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not search. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Text('Search Address', style: AppTextStyles.titleLarge),
          ),

          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'e.g. 123 Samora Machel Ave, Harare',
                hintStyle: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textHint),
                prefixIcon: const Icon(Icons.search,
                    color: AppColors.textHint, size: 22),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear,
                            size: 20, color: AppColors.textHint),
                        onPressed: () {
                          _controller.clear();
                          setState(() {
                            _results = [];
                            _error = null;
                            _loading = false;
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 1.5),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Results / states
          Flexible(
            child: _buildBody(),
          ),

          SizedBox(height: bottomInset + 16),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            _error!,
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            'Type to search for an address',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final r = _results[index];
        return ListTile(
          leading: const Icon(Icons.location_on_outlined,
              color: AppColors.primary, size: 22),
          title: Text(
            r.displayName,
            style: AppTextStyles.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => Navigator.of(context).pop(r),
        );
      },
    );
  }
}
