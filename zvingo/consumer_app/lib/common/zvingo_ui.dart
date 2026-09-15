/// The Zvingo consumer design system, in one import.
///
/// ```dart
/// import 'package:consumer_app/common/zvingo_ui.dart';
/// ```
///
/// This exports the token layer (`AppColors`, `AppTextStyles`, `AppSpacing`,
/// `AppRadius`, `AppShadows`, `AppMotion`) and every shared widget. Anything
/// a feature screen needs to look like Zvingo is behind this one import — if
/// you find yourself writing a raw hex colour, a magic padding or a bespoke
/// button, the answer is in here instead.
///
/// The contract these implement is `docs/DESIGN_SYSTEM.md`; section numbers in
/// the widget docs refer to it.
library;

// ── Tokens ────────────────────────────────────────────────────────────────
export 'package:consumer_app/core/app_colors.dart';
export 'package:consumer_app/core/app_motion.dart';
export 'package:consumer_app/core/app_spacing.dart';
export 'package:consumer_app/core/app_text_styles.dart';

// ── Widgets ───────────────────────────────────────────────────────────────
export 'widgets/app_ui.dart';
export 'widgets/custom_text_field.dart';
export 'widgets/floating_app_dock.dart';
export 'widgets/primary_button.dart';
export 'widgets/shimmer_card.dart';
export 'widgets/zv_animated_count.dart';
export 'widgets/zv_buttons.dart';
export 'widgets/zv_card.dart';
export 'widgets/zv_chips.dart';
export 'widgets/zv_confirm_sheet.dart';
export 'widgets/zv_inputs.dart';
export 'widgets/zv_screen.dart';
export 'widgets/zv_section_header.dart';
export 'widgets/zv_skeletons.dart';
export 'widgets/zv_staggered_list.dart';
export 'widgets/zv_states.dart';
export 'widgets/zv_sticky_bars.dart';
export 'widgets/zv_tap_scale.dart';
