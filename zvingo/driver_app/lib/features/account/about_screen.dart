import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_colors.dart';
import '../../core/app_config.dart';
import '../../core/app_spacing.dart';
import '../../core/app_text_styles.dart';
import '../../widgets/widgets.dart';
import 'app_info.dart';
import 'legal_document_screen.dart';

/// About this app.
///
/// The version comes from the build ([AppInfo]), not from a literal. The old
/// screen printed `Version 1.0.0` from a string constant in the router, which
/// would have said 1.0.0 forever.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final padding = AppSpacing.screenPaddingOf(context);

    return Scaffold(
      appBar: const DriverAppBar(
        title: 'About',
        fallbackRoute: '/account',
      ),
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
            StaggeredEntrance(
              index: 0,
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.brandGreen,
                      borderRadius: AppSpacing.brLg,
                    ),
                    child: Text(
                      'Z',
                      style: AppTextStyles.display.copyWith(
                        color: AppColors.textOnDark,
                        fontSize: 36,
                      ),
                    ),
                  ),
                  Gap.md,
                  Text(
                    AppInfo.appName,
                    style: AppTextStyles.onSurface(context, AppTextStyles.h1),
                  ),
                  Gap.xs,
                  Text(
                    AppInfo.versionLabel,
                    style: AppTextStyles.money
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  if (!AppInfo.hasVersion) ...[
                    Gap.xs,
                    Text(
                      'This build was not stamped with a version number.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                ],
              ),
            ),
            Gap.section,
            StaggeredEntrance(
              index: 1,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: AppSpacing.cardDecoration(context),
                child: Text(
                  'Zvingo connects drivers in Zimbabwe with restaurants and '
                  'customers. This app is the driver side: it offers you jobs, '
                  'navigates you through them, and keeps the record of what you '
                  'were paid for each one.',
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.55,
                  ),
                ),
              ),
            ),
            Gap.section,
            StaggeredEntrance(
              index: 2,
              child: Text(
                'Build details',
                style: AppTextStyles.overline
                    .copyWith(color: AppColors.textSecondary),
              ),
            ),
            Gap.md,
            StaggeredEntrance(
              index: 3,
              child: Container(
                decoration: AppSpacing.cardDecoration(context),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _DetailRow(
                      label: 'Version',
                      value: AppInfo.versionLabel,
                    ),
                    if (AppInfo.commit.isNotEmpty)
                      const _DetailRow(
                        label: 'Build',
                        value: AppInfo.commit,
                      ),
                    const _DetailRow(
                      label: 'Connected to',
                      value: AppConfig.baseUrl,
                    ),
                  ],
                ),
              ),
            ),
            Gap.md,
            StaggeredEntrance(
              index: 4,
              child: _CopyBuildInfo(),
            ),
            Gap.section,
            StaggeredEntrance(
              index: 5,
              child: Text(
                'Legal',
                style: AppTextStyles.overline
                    .copyWith(color: AppColors.textSecondary),
              ),
            ),
            Gap.md,
            StaggeredEntrance(
              index: 6,
              child: Container(
                decoration: AppSpacing.cardDecoration(context),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final document in LegalDocument.values) ...[
                      if (document != LegalDocument.values.first)
                        Divider(
                          height: 1,
                          color: AppColors.borderOf(context),
                        ),
                      _LegalRow(document: document),
                    ],
                  ],
                ),
              ),
            ),
            Gap.section,
            Text(
              'Made for Zimbabwe · prices in USD, ZiG and ZAR',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: AppTextStyles.body
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
          Gap.hMd,
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyBuildInfo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DriverSecondaryButton(
      label: 'Copy build details',
      icon: Icons.content_copy_rounded,
      onPressed: () {
        Clipboard.setData(
          ClipboardData(
            text: '${AppInfo.supportReference} · ${AppConfig.baseUrl}',
          ),
        );
        DriverSnack.show(
          context,
          'Build details copied',
          icon: Icons.check_rounded,
        );
      },
    );
  }
}

class _LegalRow extends StatelessWidget {
  final LegalDocument document;

  const _LegalRow({required this.document});

  @override
  Widget build(BuildContext context) {
    return TapScale(
      semanticLabel: 'Open ${document.title}',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LegalDocumentScreen(document: document),
        ),
      ),
      child: Container(
        constraints:
            const BoxConstraints(minHeight: AppSpacing.minTouchTarget + 8),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(
              document == LegalDocument.privacy
                  ? Icons.privacy_tip_outlined
                  : Icons.description_outlined,
              size: 20,
              color: AppColors.textSecondary,
            ),
            Gap.hMd,
            Expanded(
              child: Text(
                document.title,
                style: AppTextStyles.body
                    .copyWith(color: AppColors.textPrimary),
              ),
            ),
            if (!document.isConfigured)
              const StatusChip(
                label: 'Not published',
                tone: StatusTone.warning,
              ),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
