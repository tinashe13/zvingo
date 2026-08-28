import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/app_colors.dart';

/// VehicleDetailsScreen — loads and edits the driver's vehicle details.
class VehicleDetailsScreen extends ConsumerStatefulWidget {
  const VehicleDetailsScreen({super.key});

  @override
  ConsumerState<VehicleDetailsScreen> createState() =>
      _VehicleDetailsScreenState();
}

class _VehicleDetailsScreenState extends ConsumerState<VehicleDetailsScreen> {
  final _makeController = TextEditingController();
  final _modelController = TextEditingController();
  final _colorController = TextEditingController();
  final _plateController = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  // Original values loaded from the backend, used to detect edits.
  String? _originalMake;
  String? _originalModel;
  String? _originalColor;
  String? _originalPlate;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _makeController.dispose();
    _modelController.dispose();
    _colorController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final response = await ref.read(apiClientProvider).get('/driver/vehicle');
      final data = response.data;
      final vehicle = (data is Map) ? data['vehicle'] : null;
      final map = vehicle is Map ? vehicle : <String, dynamic>{};

      _originalMake = map['make'] as String?;
      _originalModel = map['model'] as String?;
      _originalColor = map['color'] as String?;
      _originalPlate = map['plate'] as String?;

      _makeController.text = _originalMake ?? '';
      _modelController.text = _originalModel ?? '';
      _colorController.text = _originalColor ?? '';
      _plateController.text = _originalPlate ?? '';
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load vehicle details')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    // Persist only fields the user actually edited.
    final payload = <String, dynamic>{};
    void putIfChanged(String key, String current, String? original) {
      if (current != (original ?? '')) {
        payload[key] = current;
      }
    }

    putIfChanged('make', _makeController.text, _originalMake);
    putIfChanged('model', _modelController.text, _originalModel);
    putIfChanged('color', _colorController.text, _originalColor);
    putIfChanged('plate', _plateController.text, _originalPlate);

    try {
      await ref.read(apiClientProvider).put('/driver/vehicle', data: payload);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vehicle details saved')),
        );
      }
      // Update originals so subsequent saves only send new edits.
      _originalMake = _makeController.text;
      _originalModel = _modelController.text;
      _originalColor = _colorController.text;
      _originalPlate = _plateController.text;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save vehicle details')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle Details')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _makeController,
                  decoration: const InputDecoration(labelText: 'Make'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _modelController,
                  decoration: const InputDecoration(labelText: 'Model'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _colorController,
                  decoration: const InputDecoration(labelText: 'Color'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _plateController,
                  decoration: const InputDecoration(labelText: 'Plate'),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.white,
                            ),
                          )
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
    );
  }
}
