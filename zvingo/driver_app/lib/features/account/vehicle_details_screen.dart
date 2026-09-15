import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/app_colors.dart';
import '../../core/app_spacing.dart';
import '../../core/app_text_styles.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/widgets.dart';

/// The driver's registered vehicle.
///
/// Contract (`backend/app/driver/router.py`):
///
/// * `GET /driver/vehicle` → `{"vehicle": {...} | null, "vehicle_types": [...]}`
/// * `PUT /driver/vehicle` → partial update of `make`, `model`, `color`,
///   `plate`, `vehicle_type`; returns the stored vehicle.
///
/// Two server behaviours the form has to respect:
///
/// * **`vehicle_type` is validated against a fixed list** and the list comes
///   back on every read, so the picker is built from the server's list rather
///   than a hard-coded one that can drift. The previous form had no vehicle
///   type field at all, so a driver could never set the one field that
///   actually changes how they are dispatched.
/// * **Plates are normalised server-side** (`"abc 123"` → `"ABC123"`), so the
///   field shows the driver what will actually be stored and does not treat
///   the round-trip as an unexpected edit.
class VehicleDetailsScreen extends ConsumerStatefulWidget {
  const VehicleDetailsScreen({super.key});

  @override
  ConsumerState<VehicleDetailsScreen> createState() =>
      _VehicleDetailsScreenState();
}

class _VehicleDetailsScreenState extends ConsumerState<VehicleDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _makeController = TextEditingController();
  final _modelController = TextEditingController();
  final _colorController = TextEditingController();
  final _plateController = TextEditingController();

  String? _vehicleType;

  /// Server-supplied list; the fallback only covers the first frame.
  List<String> _vehicleTypes = const [
    'bicycle',
    'motorbike',
    'car',
    'van',
    'scooter',
    'on_foot',
  ];

  bool _loading = true;
  bool _saving = false;
  Object? _loadError;

  Map<String, String> _saved = const {};

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _makeController,
      _modelController,
      _colorController,
      _plateController,
    ]) {
      controller.addListener(_onEdited);
    }
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

  void _onEdited() {
    if (mounted) setState(() {});
  }

  Map<String, String> get _current => {
        'make': _makeController.text.trim(),
        'model': _modelController.text.trim(),
        'color': _colorController.text.trim(),
        'plate': _normalisePlate(_plateController.text),
        if (_vehicleType != null) 'vehicle_type': _vehicleType!,
      };

  /// Matches `_tidy_plate` on the server: no spaces, upper case.
  static String _normalisePlate(String value) =>
      value.split(RegExp(r'\s+')).join().toUpperCase();

  bool get _isDirty {
    final current = _current;
    for (final key in {...current.keys, ..._saved.keys}) {
      if ((current[key] ?? '') != (_saved[key] ?? '')) return true;
    }
    return false;
  }

  bool get _hasVehicle => _saved.values.any((v) => v.isNotEmpty);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final response = await ref
          .read(authSessionProvider)
          .send(() => ref.read(apiClientProvider).get('/driver/vehicle'));
      final data = response.data;
      final vehicle = (data is Map && data['vehicle'] is Map)
          ? Map<String, dynamic>.from(data['vehicle'] as Map)
          : <String, dynamic>{};
      final types = (data is Map && data['vehicle_types'] is List)
          ? (data['vehicle_types'] as List).whereType<String>().toList()
          : <String>[];

      if (!mounted) return;
      setState(() {
        if (types.isNotEmpty) _vehicleTypes = types;
        _saved = {
          for (final key in ['make', 'model', 'color', 'plate', 'vehicle_type'])
            if (vehicle[key] is String && (vehicle[key] as String).isNotEmpty)
              key: vehicle[key] as String,
        };
        _makeController.text = _saved['make'] ?? '';
        _modelController.text = _saved['model'] ?? '';
        _colorController.text = _saved['color'] ?? '';
        _plateController.text = _saved['plate'] ?? '';
        _vehicleType = _vehicleTypes.contains(_saved['vehicle_type'])
            ? _saved['vehicle_type']
            : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      HapticFeedback.heavyImpact();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    // Only send what actually changed — the endpoint is a partial update, and
    // resending untouched fields would overwrite a change made elsewhere.
    final current = _current;
    final payload = <String, dynamic>{
      for (final entry in current.entries)
        if (entry.value != (_saved[entry.key] ?? '')) entry.key: entry.value,
    };

    if (payload.isEmpty) {
      setState(() => _saving = false);
      return;
    }

    try {
      final response = await ref.read(authSessionProvider).send(
            () => ref
                .read(apiClientProvider)
                .put('/driver/vehicle', data: payload),
          );
      final data = response.data;
      final vehicle = (data is Map && data['vehicle'] is Map)
          ? Map<String, dynamic>.from(data['vehicle'] as Map)
          : <String, dynamic>{};

      if (!mounted) return;
      setState(() {
        // Adopt what the server stored, not what we sent — that is what makes
        // the plate normalisation visible instead of surprising.
        _saved = {
          for (final key in ['make', 'model', 'color', 'plate', 'vehicle_type'])
            if (vehicle[key] is String && (vehicle[key] as String).isNotEmpty)
              key: vehicle[key] as String,
        };
        _makeController.text = _saved['make'] ?? _makeController.text;
        _modelController.text = _saved['model'] ?? _modelController.text;
        _colorController.text = _saved['color'] ?? _colorController.text;
        _plateController.text = _saved['plate'] ?? _plateController.text;
        _vehicleType = _saved['vehicle_type'] ?? _vehicleType;
        _saving = false;
      });
      DriverSnack.show(
        context,
        'Vehicle saved',
        icon: Icons.check_circle_outline_rounded,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      DriverSnack.error(context, _errorMessage(e), onRetry: _save);
    }
  }

  String _errorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['detail'] is String) {
        return data['detail'] as String;
      }
      if (data is Map && data['detail'] is List) {
        final first = (data['detail'] as List).firstOrNull;
        if (first is Map && first['msg'] != null) return first['msg'].toString();
      }
      if (error.type == DioExceptionType.connectionError) {
        return 'No connection. Your vehicle details were not saved.';
      }
    }
    return 'Could not save your vehicle details.';
  }

  /// Guards against leaving unsaved edits behind.
  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    return ConfirmSheet.show(
      context,
      title: 'Leave without saving?',
      consequence:
          'Your changes to your vehicle will be lost, and customers will keep '
          'seeing the old details.',
      confirmLabel: 'Discard changes',
      cancelLabel: 'Keep editing',
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = AppSpacing.screenPaddingOf(context);

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard() && mounted) {
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: DriverAppBar(
          title: 'Vehicle details',
          subtitle: _hasVehicle
              ? 'What customers see when you arrive'
              : 'Add the vehicle you deliver with',
          fallbackRoute: '/account',
        ),
        body: SafeArea(
          top: false,
          child: _loading
              ? _skeleton(padding)
              : _loadError != null
                  ? ListView(
                      padding: EdgeInsets.symmetric(
                        horizontal: padding,
                        vertical: AppSpacing.xxl,
                      ),
                      children: [
                        DriverErrorState(
                          title: 'Could not load your vehicle',
                          message:
                              'We could not reach your vehicle details. Check '
                              'your connection and try again.',
                          onRetry: _load,
                        ),
                      ],
                    )
                  : _form(context, padding),
        ),
        bottomNavigationBar: _loading || _loadError != null
            ? null
            : DriverActionFooter(
                supporting: _isDirty
                    ? null
                    : Text(
                        _hasVehicle
                            ? 'Saved. Customers see this when you arrive.'
                            : 'Add at least your vehicle type and plate.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textSecondary),
                      ),
                child: DriverPrimaryButton(
                  label: 'Save vehicle',
                  isLoading: _saving,
                  onPressed: _isDirty && !_saving ? _save : null,
                  disabledReason:
                      _isDirty || _saving ? null : 'Nothing has changed',
                ),
              ),
      ),
    );
  }

  Widget _form(BuildContext context, double padding) {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
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
            child: _VehiclePreview(
              type: _vehicleType,
              make: _makeController.text,
              model: _modelController.text,
              color: _colorController.text,
              plate: _normalisePlate(_plateController.text),
            ),
          ),
          Gap.section,
          const StaggeredEntrance(
            index: 1,
            child: _Label(
              'Vehicle type',
              helper: 'This decides which deliveries you are offered.',
            ),
          ),
          Gap.sm,
          StaggeredEntrance(
            index: 2,
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final type in _vehicleTypes)
                  _TypeChip(
                    type: type,
                    selected: _vehicleType == type,
                    onTap: () => setState(
                      () => _vehicleType = _vehicleType == type ? null : type,
                    ),
                  ),
              ],
            ),
          ),
          Gap.xl,
          const StaggeredEntrance(
            index: 3,
            child: _Label(
              'Number plate',
              helper: 'Spaces are removed and letters capitalised when saved.',
            ),
          ),
          Gap.sm,
          StaggeredEntrance(
            index: 4,
            child: TextFormField(
              controller: _plateController,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              inputFormatters: [LengthLimitingTextInputFormatter(16)],
              decoration: const InputDecoration(
                hintText: 'e.g. AEF 1234',
                prefixIcon: Icon(Icons.confirmation_number_outlined),
              ),
              validator: (value) {
                final plate = _normalisePlate(value ?? '');
                if (plate.isEmpty && _vehicleType == 'on_foot') return null;
                if (plate.isEmpty) return 'Enter your number plate';
                if (plate.length < 4) return 'That plate looks too short';
                return null;
              },
            ),
          ),
          Gap.xl,
          const StaggeredEntrance(index: 5, child: _Label('Make')),
          Gap.sm,
          StaggeredEntrance(
            index: 6,
            child: TextFormField(
              controller: _makeController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              inputFormatters: [LengthLimitingTextInputFormatter(40)],
              decoration: const InputDecoration(
                hintText: 'e.g. Toyota, Honda',
                prefixIcon: Icon(Icons.precision_manufacturing_outlined),
              ),
            ),
          ),
          Gap.xl,
          const StaggeredEntrance(index: 7, child: _Label('Model')),
          Gap.sm,
          StaggeredEntrance(
            index: 8,
            child: TextFormField(
              controller: _modelController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              inputFormatters: [LengthLimitingTextInputFormatter(40)],
              decoration: const InputDecoration(
                hintText: 'e.g. Vitz, CG125',
                prefixIcon: Icon(Icons.directions_car_outlined),
              ),
            ),
          ),
          Gap.xl,
          const StaggeredEntrance(
            index: 9,
            child: _Label(
              'Colour',
              helper: 'Customers look for the colour before the plate.',
            ),
          ),
          Gap.sm,
          StaggeredEntrance(
            index: 10,
            child: TextFormField(
              controller: _colorController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              inputFormatters: [LengthLimitingTextInputFormatter(24)],
              onFieldSubmitted: (_) => _isDirty ? _save() : null,
              decoration: const InputDecoration(
                hintText: 'e.g. White, Silver',
                prefixIcon: Icon(Icons.palette_outlined),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _skeleton(double padding) {
    return ListView(
      padding: EdgeInsets.fromLTRB(padding, AppSpacing.lg, padding, padding),
      children: const [
        SkeletonBox(height: 120),
        Gap.section,
        SkeletonBox.line(widthFactor: 0.3, height: 14),
        Gap.sm,
        SkeletonBox(height: 52),
        Gap.xl,
        SkeletonBox.line(widthFactor: 0.3, height: 14),
        Gap.sm,
        SkeletonBox(height: 52),
        Gap.xl,
        SkeletonBox.line(widthFactor: 0.3, height: 14),
        Gap.sm,
        SkeletonBox(height: 52),
      ],
    );
  }
}

// ── Pieces ──────────────────────────────────────────────────────────────────

/// What the waiting customer will be told to look for.
class _VehiclePreview extends StatelessWidget {
  final String? type;
  final String make;
  final String model;
  final String color;
  final String plate;

  const _VehiclePreview({
    required this.type,
    required this.make,
    required this.model,
    required this.color,
    required this.plate,
  });

  @override
  Widget build(BuildContext context) {
    final descriptor = [
      if (color.trim().isNotEmpty) color.trim(),
      if (make.trim().isNotEmpty) make.trim(),
      if (model.trim().isNotEmpty) model.trim(),
    ].join(' ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceMutedOf(context),
        borderRadius: AppSpacing.brLg,
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceOf(context),
              borderRadius: AppSpacing.brMd,
            ),
            child: Icon(
              _VehicleType.iconFor(type),
              size: 26,
              color: AppColors.textSecondary,
            ),
          ),
          Gap.hMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Look for',
                  style: AppTextStyles.overline
                      .copyWith(color: AppColors.textTertiary),
                ),
                Gap.xxs,
                Text(
                  descriptor.isEmpty
                      ? _VehicleType.labelFor(type)
                      : descriptor,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyStrong
                      .copyWith(color: AppColors.textPrimary),
                ),
                if (plate.isNotEmpty) ...[
                  Gap.xs,
                  Text(
                    plate,
                    style: AppTextStyles.money.copyWith(
                      color: AppColors.textPrimary,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleType {
  _VehicleType._();

  static String labelFor(String? type) => switch (type) {
        'bicycle' => 'Bicycle',
        'motorbike' => 'Motorbike',
        'car' => 'Car',
        'van' => 'Van',
        'scooter' => 'Scooter',
        'on_foot' => 'On foot',
        null => 'No vehicle set yet',
        _ => type
            .split('_')
            .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
            .join(' '),
      };

  static IconData iconFor(String? type) => switch (type) {
        'bicycle' => Icons.pedal_bike_rounded,
        'motorbike' => Icons.two_wheeler_rounded,
        'car' => Icons.directions_car_rounded,
        'van' => Icons.local_shipping_rounded,
        'scooter' => Icons.electric_scooter_rounded,
        'on_foot' => Icons.directions_walk_rounded,
        _ => Icons.help_outline_rounded,
      };
}

class _TypeChip extends StatelessWidget {
  final String type;
  final bool selected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg =
        selected ? AppColors.onActionOf(context) : AppColors.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      child: TapScale(
        onTap: onTap,
        enforceMinTarget: false,
        child: Container(
          constraints:
              const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.actionOf(context)
                : AppColors.surfaceMutedOf(context),
            borderRadius: AppSpacing.brFull,
            border: Border.all(
              color: selected
                  ? AppColors.actionOf(context)
                  : AppColors.borderOf(context),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_VehicleType.iconFor(type), size: 18, color: fg),
              Gap.hSm,
              Text(
                _VehicleType.labelFor(type),
                style: AppTextStyles.bodyStrong.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final String? helper;

  const _Label(this.text, {this.helper});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style:
              AppTextStyles.bodyStrong.copyWith(color: AppColors.textPrimary),
        ),
        if (helper != null) ...[
          Gap.xxs,
          Text(
            helper!,
            style:
                AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ],
    );
  }
}
