import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';

import '../../core/app_colors.dart';
import '../../core/app_spacing.dart';
import '../../core/app_text_styles.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/widgets.dart';
import 'app_info.dart';
import 'legal_document_screen.dart' show CopyableRow;

/// Driver safety.
///
/// Gig drivers work alone, at night, carrying cash, at addresses they have
/// never been to. This screen is built around the one moment that matters:
/// something has gone wrong and the driver has seconds and one hand.
///
/// What is real here, and what is not:
///
/// * **Emergency contact** — stored on the device. The backend `User` document
///   has no emergency-contact field (see the report for the exact schema
///   request), so it does not sync between devices and Zvingo support cannot
///   read it. The screen says so rather than implying someone is watching.
/// * **Emergency actions** — the app has no `url_launcher`/`share_plus`
///   dependency, so it cannot open the dialer or a share sheet. Every action
///   here is therefore a real one: copy a number, or copy a pre-written
///   message containing the driver's live coordinates, ready to paste into
///   WhatsApp or SMS. Nothing pretends to place a call it cannot place.
/// * **Share my trip** — builds that message from the device's actual GPS fix.
class SafetyScreen extends ConsumerStatefulWidget {
  const SafetyScreen({super.key});

  @override
  ConsumerState<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends ConsumerState<SafetyScreen> {
  static const String _nameKey = 'emergency_contact_name';
  static const String _phoneKey = 'emergency_contact_phone';

  String _contactName = '';
  String _contactPhone = '';
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _restoreContact();
  }

  void _restoreContact() {
    try {
      final box = Hive.box('settings');
      _contactName = box.get(_nameKey) as String? ?? '';
      _contactPhone = box.get(_phoneKey) as String? ?? '';
    } catch (_) {
      // Storage unavailable — the screen still works, just without a contact.
    }
  }

  bool get _hasContact => _contactPhone.isNotEmpty;

  Future<void> _editContact() async {
    final result = await showModalBottomSheet<({String name, String phone})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(borderRadius: AppSpacing.brSheetTop),
      builder: (context) => _EmergencyContactSheet(
        initialName: _contactName,
        initialPhone: _contactPhone,
      ),
    );
    if (result == null) return;

    setState(() {
      _contactName = result.name;
      _contactPhone = result.phone;
    });
    try {
      final box = Hive.box('settings');
      await box.put(_nameKey, result.name);
      await box.put(_phoneKey, result.phone);
      if (mounted) {
        DriverSnack.show(
          context,
          result.phone.isEmpty
              ? 'Emergency contact removed'
              : 'Emergency contact saved',
          icon: Icons.check_rounded,
        );
      }
    } catch (e) {
      if (mounted) {
        DriverSnack.error(context, 'Could not save your emergency contact.');
      }
    }
  }

  /// Reads the device's current fix. Returns null when it cannot.
  Future<Position?> _currentPosition() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12),
      );
    } catch (_) {
      return null;
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Builds the message a driver pastes into WhatsApp or SMS.
  String _message({required bool emergency, Position? position}) {
    final auth = ref.read(authProvider);
    final buffer = StringBuffer();
    if (emergency) {
      buffer.writeln('EMERGENCY — I need help.');
    } else {
      buffer.writeln('Sharing my Zvingo trip with you.');
    }
    buffer.writeln('Driver: ${auth.displayName}');
    if (auth.phone.isNotEmpty) buffer.writeln('Phone: ${auth.phone}');
    if (position != null) {
      final lat = position.latitude.toStringAsFixed(6);
      final lng = position.longitude.toStringAsFixed(6);
      buffer.writeln('My location: $lat, $lng');
      // A plain maps query works in every maps app and in a browser, so the
      // person receiving this does not need Zvingo installed.
      buffer.writeln('Map: https://www.google.com/maps/search/?api=1&query=$lat,$lng');
      buffer.writeln('Accurate to about ${position.accuracy.round()} m');
    } else {
      buffer.writeln('My location could not be read on my phone just now.');
    }
    buffer.writeln('Sent ${TimeOfDay.now().format(context)} from Zvingo Driver.');
    return buffer.toString().trim();
  }

  Future<void> _copyMessage({required bool emergency}) async {
    final position = await _currentPosition();
    if (!mounted) return;
    final text = _message(emergency: emergency, position: position);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    DriverSnack.show(
      context,
      position == null
          ? 'Message copied — without your location'
          : 'Message copied with your location. Paste it to send.',
      icon: Icons.content_copy_rounded,
    );
  }

  Future<void> _openEmergencySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(borderRadius: AppSpacing.brSheetTop),
      builder: (sheetContext) => _EmergencySheet(
        contactName: _contactName,
        contactPhone: _contactPhone,
        onCopyMessage: () {
          Navigator.of(sheetContext).pop();
          unawaited(_copyMessage(emergency: true));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = AppSpacing.screenPaddingOf(context);

    return Scaffold(
      appBar: const DriverAppBar(
        title: 'Safety',
        subtitle: 'For when something goes wrong',
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
              child: _EmergencyCta(onTap: _openEmergencySheet),
            ),
            Gap.section,
            const StaggeredEntrance(index: 1, child: _Title('Your emergency contact')),
            Gap.md,
            StaggeredEntrance(
              index: 2,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: AppSpacing.cardDecoration(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_hasContact) ...[
                      Row(
                        children: [
                          const Icon(Icons.contact_emergency_outlined,
                              size: 20, color: AppColors.textSecondary),
                          Gap.hSm,
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _contactName.isEmpty
                                      ? 'Emergency contact'
                                      : _contactName,
                                  style: AppTextStyles.bodyStrong.copyWith(
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  _contactPhone,
                                  style: AppTextStyles.money.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Gap.lg,
                      Row(
                        children: [
                          Expanded(
                            child: DriverSecondaryButton(
                              label: 'Change',
                              icon: Icons.edit_outlined,
                              onPressed: _editContact,
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Text(
                        'Nobody set yet',
                        style:
                            AppTextStyles.onSurface(context, AppTextStyles.h3),
                      ),
                      Gap.sm,
                      Text(
                        'Add the person you would want contacted if something '
                        'happened while you were working. Their number will be '
                        'right here, one tap from any screen.',
                        style: AppTextStyles.body
                            .copyWith(color: AppColors.textSecondary),
                      ),
                      Gap.lg,
                      DriverPrimaryButton(
                        label: 'Add an emergency contact',
                        icon: Icons.person_add_alt_1_outlined,
                        onPressed: _editContact,
                      ),
                    ],
                    Gap.md,
                    Text(
                      'This is stored on this phone only. Zvingo support '
                      'cannot see it, and it will not move to a new phone.',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
            ),
            Gap.section,
            const StaggeredEntrance(index: 3, child: _Title('Share where you are')),
            Gap.md,
            StaggeredEntrance(
              index: 4,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: AppSpacing.cardDecoration(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Prepares a message with your name and your exact '
                      'location, ready to paste into WhatsApp or a text. The '
                      'person you send it to does not need Zvingo installed.',
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.textSecondary),
                    ),
                    Gap.lg,
                    DriverSecondaryButton(
                      label: 'Copy my location message',
                      icon: Icons.my_location_rounded,
                      isLoading: _locating,
                      onPressed: () => _copyMessage(emergency: false),
                    ),
                  ],
                ),
              ),
            ),
            Gap.section,
            const StaggeredEntrance(index: 5, child: _Title('Staying safe on shift')),
            Gap.md,
            const StaggeredEntrance(index: 6, child: _SafetyTips()),
          ],
        ),
      ),
    );
  }
}

// ── Emergency ───────────────────────────────────────────────────────────────

class _EmergencyCta extends StatelessWidget {
  final VoidCallback onTap;

  const _EmergencyCta({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      semanticLabel: 'Open emergency help',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.errorSurfaceOf(context),
          borderRadius: AppSpacing.brLg,
          border: Border.all(
            color: AppColors.errorOf(context).withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.errorOf(context),
                borderRadius: AppSpacing.brFull,
              ),
              child: const Icon(Icons.sos_rounded,
                  size: 28, color: AppColors.textOnDark),
            ),
            Gap.hMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'I need help now',
                    style: AppTextStyles.h3
                        .copyWith(color: AppColors.errorOf(context)),
                  ),
                  Gap.xxs,
                  Text(
                    'Emergency numbers and a ready-to-send message with your '
                    'location.',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.errorOf(context)),
          ],
        ),
      ),
    );
  }
}

class _EmergencySheet extends StatelessWidget {
  final String contactName;
  final String contactPhone;
  final VoidCallback onCopyMessage;

  const _EmergencySheet({
    required this.contactName,
    required this.contactPhone,
    required this.onCopyMessage,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Emergency',
              style: AppTextStyles.onSurface(context, AppTextStyles.h1),
            ),
            Gap.sm,
            Text(
              'If you are in immediate danger, call the emergency services '
              'first. Tap a number to copy it into your dialler.',
              style: AppTextStyles.body
                  .copyWith(color: AppColors.textSecondary),
            ),
            Gap.xl,
            const CopyableRow(
              icon: Icons.local_police_outlined,
              label: 'Emergency services (Zimbabwe)',
              value: SupportContact.emergencyServices,
            ),
            if (contactPhone.isNotEmpty) ...[
              Gap.sm,
              CopyableRow(
                icon: Icons.contact_emergency_outlined,
                label: contactName.isEmpty
                    ? 'Your emergency contact'
                    : contactName,
                value: contactPhone,
              ),
            ],
            if (SupportContact.phone.isNotEmpty) ...[
              Gap.sm,
              const CopyableRow(
                icon: Icons.support_agent_outlined,
                label: 'Zvingo driver support',
                value: SupportContact.phone,
              ),
            ],
            Gap.xl,
            DriverDestructiveButton(
              label: 'Copy an emergency message',
              icon: Icons.share_location_rounded,
              onPressed: onCopyMessage,
            ),
            Gap.sm,
            Text(
              'Copies your name, your phone number and your exact location. '
              'Paste it straight into WhatsApp or a text message.',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textTertiary),
            ),
            Gap.lg,
            DriverTextButton(
              label: 'Close',
              expanded: true,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Contact editor ──────────────────────────────────────────────────────────

class _EmergencyContactSheet extends StatefulWidget {
  final String initialName;
  final String initialPhone;

  const _EmergencyContactSheet({
    required this.initialName,
    required this.initialPhone,
  });

  @override
  State<_EmergencyContactSheet> createState() => _EmergencyContactSheetState();
}

class _EmergencyContactSheetState extends State<_EmergencyContactSheet> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.initialName);
  late final TextEditingController _phoneController =
      TextEditingController(text: widget.initialPhone);
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop((
      name: _nameController.text.trim(),
      phone: AuthNotifier.normalisePhone(_phoneController.text),
    ));
  }

  void _remove() {
    Navigator.of(context).pop((name: '', phone: ''));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Emergency contact',
                  style: AppTextStyles.onSurface(context, AppTextStyles.h2),
                ),
                Gap.sm,
                Text(
                  'Someone who would come and find you.',
                  style: AppTextStyles.body
                      .copyWith(color: AppColors.textSecondary),
                ),
                Gap.xl,
                Text(
                  'Name',
                  style: AppTextStyles.bodyStrong
                      .copyWith(color: AppColors.textPrimary),
                ),
                Gap.sm,
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Rudo (sister)',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                Gap.lg,
                Text(
                  'Phone number',
                  style: AppTextStyles.bodyStrong
                      .copyWith(color: AppColors.textPrimary),
                ),
                Gap.sm,
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _save(),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-()]')),
                    LengthLimitingTextInputFormatter(20),
                  ],
                  decoration: const InputDecoration(
                    hintText: '077 123 4567',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: (value) =>
                      AuthNotifier.validatePhone(value ?? ''),
                ),
                Gap.xl,
                DriverPrimaryButton(label: 'Save contact', onPressed: _save),
                if (widget.initialPhone.isNotEmpty) ...[
                  Gap.sm,
                  DriverTextButton(
                    label: 'Remove this contact',
                    expanded: true,
                    onPressed: _remove,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Tips ────────────────────────────────────────────────────────────────────

class _SafetyTips extends StatelessWidget {
  const _SafetyTips();

  static const List<({IconData icon, String title, String body})> _tips = [
    (
      icon: Icons.payments_outlined,
      title: 'Do not carry more cash than you need',
      body:
          'Settle your cash float with Zvingo when it gets high. Your earnings '
          'screen shows what you are holding.',
    ),
    (
      icon: Icons.nightlight_outlined,
      title: 'At night, meet customers in the light',
      body:
          'Ask the customer to come to a lit entrance or gate rather than '
          'walking into an unlit yard or corridor.',
    ),
    (
      icon: Icons.two_wheeler_outlined,
      title: 'Never leave the app to argue',
      body:
          'If a handover turns hostile, leave. Mark the delivery as a problem '
          'and let Zvingo support handle it — no order is worth your '
          'safety.',
    ),
    (
      icon: Icons.battery_charging_full_outlined,
      title: 'Keep your phone charged',
      body:
          'Your phone is your navigation, your income and your way of calling '
          'for help. Carry a power bank.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppSpacing.cardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < _tips.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: AppSpacing.huge,
                color: AppColors.borderOf(context),
              ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_tips[i].icon,
                      size: 20, color: AppColors.textSecondary),
                  Gap.hMd,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tips[i].title,
                          style: AppTextStyles.bodyStrong
                              .copyWith(color: AppColors.textPrimary),
                        ),
                        Gap.xxs,
                        Text(
                          _tips[i].body,
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  final String text;

  const _Title(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.onSurface(context, AppTextStyles.h2),
    );
  }
}
