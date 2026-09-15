import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/app_spacing.dart';
import '../../core/app_text_styles.dart';
import '../../widgets/widgets.dart';
import 'about_screen.dart';
import 'app_info.dart';
import 'help_screen.dart';
import 'legal_document_screen.dart';
import 'notification_settings_screen.dart';
import 'safety_screen.dart';

/// Which account sub-page a route wants.
enum InfoTopic {
  notifications,
  safety,
  help,
  about,
  terms,
  privacy,

  /// Anything else: render the supplied paragraphs as plain copy.
  generic;

  /// Best-effort mapping from the screen title.
  ///
  /// `lib/core/router.dart` is owned by another agent and currently constructs
  /// [InfoScreen] with a `title` and a list of hard-coded `paragraphs`. Rather
  /// than leave six routes rendering copy that a code generator invented — two
  /// of which were presented to drivers as Zvingo's legal terms — [InfoScreen]
  /// resolves the title to a topic and hands off to the real screen.
  ///
  /// Passing `topic:` explicitly is the supported way; this inference exists
  /// only so the existing routes work today. See the report for the one-line
  /// router change that makes it unnecessary.
  static InfoTopic fromTitle(String title) {
    final normalised = title.trim().toLowerCase();
    if (normalised.startsWith('notification')) return InfoTopic.notifications;
    if (normalised.startsWith('safety')) return InfoTopic.safety;
    if (normalised.startsWith('help')) return InfoTopic.help;
    if (normalised.startsWith('about')) return InfoTopic.about;
    if (normalised.contains('terms')) return InfoTopic.terms;
    if (normalised.contains('privacy')) return InfoTopic.privacy;
    return InfoTopic.generic;
  }
}

/// Entry point for the account menu's sub-pages.
///
/// This used to be a static card that printed whatever `paragraphs` it was
/// handed, which is how six menu entries came to look implemented while doing
/// nothing useful. It is now a dispatcher onto screens that are wired to real
/// data:
///
/// | Topic | Screen | Backed by |
/// |---|---|---|
/// | Notifications | [NotificationSettingsScreen] | `GET`/`PUT /notification/preferences` |
/// | Safety | [SafetyScreen] | device storage + GPS |
/// | Help | [HelpScreen] | in-app answers + support contact |
/// | About | [AboutScreen] | build-time version, not a literal |
/// | Terms / Privacy | [LegalDocumentScreen] | a hosted document, or an honest "not published" |
///
/// The [paragraphs] parameter is kept so existing callers compile, and is used
/// only for [InfoTopic.generic].
class InfoScreen extends StatelessWidget {
  final String title;
  final IconData? icon;

  /// Fallback body copy for [InfoTopic.generic] only.
  final List<String> paragraphs;

  /// Which real screen to show. Inferred from [title] when omitted.
  final InfoTopic? topic;

  const InfoScreen({
    super.key,
    required this.title,
    this.icon,
    this.paragraphs = const [],
    this.topic,
  });

  @override
  Widget build(BuildContext context) {
    switch (topic ?? InfoTopic.fromTitle(title)) {
      case InfoTopic.notifications:
        return const NotificationSettingsScreen();
      case InfoTopic.safety:
        return const SafetyScreen();
      case InfoTopic.help:
        return const HelpScreen();
      case InfoTopic.about:
        return const AboutScreen();
      case InfoTopic.terms:
        return const LegalDocumentScreen(document: LegalDocument.terms);
      case InfoTopic.privacy:
        return const LegalDocumentScreen(document: LegalDocument.privacy);
      case InfoTopic.generic:
        return _GenericInfoScreen(
          title: title,
          icon: icon,
          paragraphs: paragraphs,
        );
    }
  }
}

/// Plain informational page, for a topic with no dedicated screen.
class _GenericInfoScreen extends StatelessWidget {
  final String title;
  final IconData? icon;
  final List<String> paragraphs;

  const _GenericInfoScreen({
    required this.title,
    required this.paragraphs,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final padding = AppSpacing.screenPaddingOf(context);

    if (paragraphs.isEmpty) {
      // Never a blank screen (§0.6).
      return Scaffold(
        appBar: DriverAppBar(title: title, fallbackRoute: '/account'),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: padding,
              vertical: AppSpacing.xxl,
            ),
            child: DriverEmptyState(
              icon: icon ?? Icons.info_outline_rounded,
              title: 'Nothing here yet',
              message:
                  'There is no content for this page in this version of the '
                  'app.',
              actionLabel: 'Back to account',
              onAction: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: DriverAppBar(title: title, fallbackRoute: '/account'),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            padding,
            AppSpacing.xxl,
            padding,
            AppSpacing.section,
          ),
          children: [
            if (icon != null) ...[
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMutedOf(context),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 32, color: AppColors.textSecondary),
                ),
              ),
              Gap.xxl,
            ],
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: AppSpacing.cardDecoration(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < paragraphs.length; i++) ...[
                    if (i > 0) Gap.md,
                    Text(
                      paragraphs[i],
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.55,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Gap.lg,
            Center(
              child: Text(
                AppInfo.versionLabel,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
