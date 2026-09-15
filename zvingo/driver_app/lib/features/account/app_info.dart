/// Build-time facts about this app binary.
///
/// **No version string is hard-coded here.** The account screen used to print
/// a literal `"Zvingo Driver v1.0.0"`, which stayed at 1.0.0 through every
/// release and made "what version are you on?" a useless support question.
///
/// The right source is `package_info_plus`, which reads the real version out
/// of the Android/iOS bundle at runtime. That package is **not** a dependency
/// of `driver_app` and `pubspec.yaml` is owned by another agent, so until it
/// is added the values come from the build itself via `--dart-define`, which
/// CI sets from the same place it sets the bundle version:
///
/// ```bash
/// flutter build apk --release \
///   --dart-define=APP_VERSION=$(grep '^version:' pubspec.yaml | cut -d' ' -f2 | cut -d+ -f1) \
///   --dart-define=APP_BUILD_NUMBER=$CI_BUILD_NUMBER \
///   --dart-define=API_BASE_URL=https://…
/// ```
///
/// When nothing is defined — a local `flutter run` — [AppInfo.versionLabel]
/// says "Development build" rather than claiming a version that is not real.
class AppInfo {
  AppInfo._();

  static const String appName = 'Zvingo Driver';

  /// Semantic version, e.g. `1.4.2`. Empty on an undefined build.
  static const String version = String.fromEnvironment('APP_VERSION');

  /// Build/version code, e.g. `184`. Empty on an undefined build.
  static const String buildNumber = String.fromEnvironment('APP_BUILD_NUMBER');

  /// Commit the binary was built from, for support to correlate a bug report
  /// with a build. Optional.
  static const String commit = String.fromEnvironment('APP_COMMIT');

  static bool get hasVersion => version.isNotEmpty;

  /// `Version 1.4.2 (184)`, `Version 1.4.2`, or `Development build`.
  static String get versionLabel {
    if (!hasVersion) return 'Development build';
    return buildNumber.isEmpty
        ? 'Version $version'
        : 'Version $version ($buildNumber)';
  }

  /// A one-line string a driver can read out to support.
  static String get supportReference {
    final parts = <String>[appName, versionLabel];
    if (commit.isNotEmpty) {
      parts.add('build ${commit.substring(0, commit.length.clamp(0, 8))}');
    }
    return parts.join(' · ');
  }
}

/// A legal or informational document the app displays but does not author.
///
/// **Finding X5: Zvingo has no hosted privacy policy, and no terms of
/// service.** The driver app previously shipped two invented paragraphs per
/// document, written by a code generator, presented to drivers as Zvingo's
/// legal position. That is worse than showing nothing: it is an unreviewed
/// contract, and both app stores require a real, hosted policy anyway.
///
/// So this app **renders** documents, it does not contain them. Each document
/// is fetched from a URL supplied at build time. Until a real document exists
/// and its URL is configured, the screen says so plainly and points the driver
/// at support — see `LegalDocumentScreen`.
enum LegalDocument {
  terms,
  privacy;

  String get title => switch (this) {
        LegalDocument.terms => 'Terms of Service',
        LegalDocument.privacy => 'Privacy Policy',
      };

  /// The `--dart-define` that supplies this document's location.
  String get defineName => switch (this) {
        LegalDocument.terms => 'LEGAL_TERMS_URL',
        LegalDocument.privacy => 'LEGAL_PRIVACY_URL',
      };

  /// Where to fetch it from, or empty when this build has no document.
  String get url => switch (this) {
        LegalDocument.terms =>
          const String.fromEnvironment('LEGAL_TERMS_URL'),
        LegalDocument.privacy =>
          const String.fromEnvironment('LEGAL_PRIVACY_URL'),
      };

  bool get isConfigured => url.isNotEmpty;

  /// One line explaining why the driver should care about this document.
  String get summary => switch (this) {
        LegalDocument.terms =>
          'The agreement between you and Zvingo about how you deliver, how you '
              'are paid, and what each side is responsible for.',
        LegalDocument.privacy =>
          'What Zvingo collects about you — including your location while '
              'you are online — how long it is kept, and who it is shared '
              'with.',
      };
}

/// Where a driver can reach a human.
///
/// Also build-time configured. Nothing here invents a phone number: an
/// unconfigured build shows no contact rather than a number that rings
/// nowhere.
class SupportContact {
  SupportContact._();

  static const String phone = String.fromEnvironment('SUPPORT_PHONE');
  static const String whatsApp = String.fromEnvironment('SUPPORT_WHATSAPP');
  static const String email = String.fromEnvironment('SUPPORT_EMAIL');

  /// The national emergency number for Zimbabwe. This is a published public
  /// service number, not a Zvingo configuration value.
  static const String emergencyServices = '999';

  static bool get hasAny =>
      phone.isNotEmpty || whatsApp.isNotEmpty || email.isNotEmpty;
}
