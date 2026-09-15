import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../core/app_colors.dart';
import '../../core/app_spacing.dart';
import '../../core/app_text_styles.dart';
import '../../widgets/widgets.dart';
import 'app_info.dart';

/// Renders a legal document that Zvingo hosts. It never contains one.
///
/// See the note on [LegalDocument]: the previous screens shipped two invented
/// paragraphs each, presented as Zvingo's terms and privacy position. Those
/// are gone. This screen fetches the real document from the URL supplied at
/// build time (`--dart-define=LEGAL_PRIVACY_URL=…`), renders it, and — when no
/// document is configured — says so honestly and hands the driver a way to get
/// a copy, rather than manufacturing a contract.
///
/// The renderer accepts plain text or light Markdown (`#` headings, `-`
/// bullets), which is what a legal document exported to text looks like. HTML
/// is stripped to its text rather than rendered, so a policy served as a web
/// page is still readable.
class LegalDocumentScreen extends StatefulWidget {
  final LegalDocument document;

  const LegalDocumentScreen({super.key, required this.document});

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  static const Duration _timeout = Duration(seconds: 15);

  bool _loading = false;
  String? _body;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (widget.document.isConfigured) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http
          .get(Uri.parse(widget.document.url))
          .timeout(_timeout);
      if (response.statusCode >= 400) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      if (!mounted) return;
      setState(() {
        _body = _toPlainText(response.body);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Turns an HTML page into readable text. Deliberately crude — the goal is
  /// legibility of a document, not fidelity of a web page.
  static String _toPlainText(String source) {
    if (!source.contains('<')) return source.trim();
    var text = source;
    text = text.replaceAll(
      RegExp(r'<(script|style)[^>]*>.*?</\1>',
          caseSensitive: false, dotAll: true),
      '',
    );
    text = text.replaceAll(
      RegExp(r'</(p|div|li|h[1-6]|tr)>', caseSensitive: false),
      '\n\n',
    );
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '- ');
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  @override
  Widget build(BuildContext context) {
    final padding = AppSpacing.screenPaddingOf(context);

    return Scaffold(
      appBar: DriverAppBar(
        title: widget.document.title,
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
            Text(
              widget.document.summary,
              style:
                  AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
            Gap.xl,
            if (!widget.document.isConfigured)
              _NotPublished(document: widget.document)
            else if (_loading)
              const _DocumentSkeleton()
            else if (_error != null)
              DriverErrorState(
                title: 'Could not load this document',
                message:
                    'We could not reach ${widget.document.title.toLowerCase()} '
                    'right now. Check your connection and try again.',
                onRetry: _load,
                technical: _error.toString(),
              )
            else if (_body == null || _body!.trim().isEmpty)
              _NotPublished(document: widget.document)
            else
              _DocumentBody(text: _body!),
          ],
        ),
      ),
    );
  }
}

/// The honest state for a document Zvingo has not published.
///
/// This is not a placeholder to be replaced with lorem legal text later — it
/// is what should show until a lawyer-reviewed document exists at a real URL.
class _NotPublished extends StatelessWidget {
  final LegalDocument document;

  const _NotPublished({required this.document});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: AppSpacing.cardDecoration(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.description_outlined,
                      size: 20, color: AppColors.warningOf(context)),
                  Gap.hSm,
                  Expanded(
                    child: Text(
                      'Not available in this version',
                      style:
                          AppTextStyles.onSurface(context, AppTextStyles.h3),
                    ),
                  ),
                ],
              ),
              Gap.md,
              Text(
                'Zvingo’s ${document.title.toLowerCase()} is not published '
                'in this build of the app, so we are not going to show you '
                'something that is not the real document.',
                style: AppTextStyles.body
                    .copyWith(color: AppColors.textSecondary),
              ),
              Gap.md,
              Text(
                'Ask Zvingo driver support for the current copy — you are '
                'entitled to it before you agree to anything.',
                style: AppTextStyles.body
                    .copyWith(color: AppColors.textSecondary),
              ),
              if (SupportContact.hasAny) ...[
                Gap.lg,
                _SupportLines(),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SupportLines extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final entries = <({IconData icon, String label, String value})>[
      if (SupportContact.phone.isNotEmpty)
        (
          icon: Icons.phone_outlined,
          label: 'Driver support',
          value: SupportContact.phone
        ),
      if (SupportContact.whatsApp.isNotEmpty)
        (
          icon: Icons.chat_outlined,
          label: 'WhatsApp',
          value: SupportContact.whatsApp
        ),
      if (SupportContact.email.isNotEmpty)
        (
          icon: Icons.mail_outline_rounded,
          label: 'Email',
          value: SupportContact.email
        ),
    ];

    return Column(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) Gap.sm,
          CopyableRow(
            icon: entries[i].icon,
            label: entries[i].label,
            value: entries[i].value,
          ),
        ],
      ],
    );
  }
}

/// A value the driver can copy to the clipboard.
///
/// The driver app has no `url_launcher` dependency, so it cannot open a dialer
/// or a browser. Copy-to-clipboard is a real, working action rather than a
/// button that silently fails — see the report for the dependency request.
class CopyableRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const CopyableRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return TapScale(
      semanticLabel: 'Copy $label $value',
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        DriverSnack.show(
          context,
          '$label copied',
          icon: Icons.content_copy_rounded,
        );
      },
      child: Container(
        constraints:
            const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceMutedOf(context),
          borderRadius: AppSpacing.brMd,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            Gap.hMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  Text(
                    value,
                    style: AppTextStyles.money
                        .copyWith(color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
            Icon(Icons.content_copy_rounded,
                size: 18, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _DocumentBody extends StatelessWidget {
  final String text;

  const _DocumentBody({required this.text});

  @override
  Widget build(BuildContext context) {
    final blocks = text.split(RegExp(r'\n\s*\n'));
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: AppSpacing.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < blocks.length; i++) ...[
            if (i > 0) Gap.md,
            _Block(text: blocks[i].trim()),
          ],
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  final String text;

  const _Block({required this.text});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    final heading = RegExp(r'^#{1,6}\s+').firstMatch(text);
    if (heading != null) {
      return Text(
        text.substring(heading.end),
        style: AppTextStyles.onSurface(context, AppTextStyles.h3),
      );
    }

    if (text.startsWith('- ') || text.startsWith('* ')) {
      final items = text
          .split('\n')
          .map((line) => line.replaceFirst(RegExp(r'^[-*]\s+'), '').trim())
          .where((line) => line.isNotEmpty);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '•',
                    style: AppTextStyles.body
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  Gap.hSm,
                  Expanded(
                    child: Text(
                      item,
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return Text(
      text,
      style: AppTextStyles.body.copyWith(
        color: AppColors.textSecondary,
        height: 1.55,
      ),
    );
  }
}

class _DocumentSkeleton extends StatelessWidget {
  const _DocumentSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: AppSpacing.cardDecoration(context),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox.line(widthFactor: 0.5, height: 18),
          Gap.md,
          SkeletonBox.line(),
          Gap.sm,
          SkeletonBox.line(),
          Gap.sm,
          SkeletonBox.line(widthFactor: 0.8),
          Gap.lg,
          SkeletonBox.line(widthFactor: 0.4, height: 18),
          Gap.md,
          SkeletonBox.line(),
          Gap.sm,
          SkeletonBox.line(widthFactor: 0.9),
        ],
      ),
    );
  }
}

/// `dart:io`'s `HttpException` is not available on web; this keeps the failure
/// type local and platform-independent.
class HttpException implements Exception {
  final String message;

  const HttpException(this.message);

  @override
  String toString() => message;
}
