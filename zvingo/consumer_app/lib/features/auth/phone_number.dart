import 'package:flutter/services.dart';

/// Phone-number handling for Zimbabwe-first, E.164-everywhere sign-in.
///
/// The backend (`app/auth/schemas.py::UserCreate._phone_must_be_e164`) accepts
/// **only** `+` followed by digits, so every value that leaves this app is
/// normalised through [toE164]. The user, meanwhile, types the way they speak:
/// `077 123 4567` or `77 123 4567`, and the `+263` sits in the field as a fixed
/// prefix rather than something they have to remember.
class ZvPhone {
  const ZvPhone._();

  /// Zimbabwe. The only dial code the consumer app defaults to.
  static const String defaultDialCode = '+263';

  /// National significant number length for Zimbabwe (`7X XXX XXXX`).
  static const int nationalLength = 9;

  /// Mobile prefixes in use in Zimbabwe (Econet 77/78, NetOne 71, Telecel 73).
  static const List<String> mobilePrefixes = <String>['71', '73', '77', '78'];

  /// Digits only, country code and any leading trunk `0` removed.
  ///
  /// Accepts every shape a person might paste: `+263 77 123 4567`,
  /// `263771234567`, `0771234567`, `077-123-4567`.
  static String nationalDigits(String raw,
      {String dialCode = defaultDialCode}) {
    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final code = dialCode.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith(code)) {
      digits = digits.substring(code.length);
    }
    while (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.length > nationalLength) {
      digits = digits.substring(0, nationalLength);
    }
    return digits;
  }

  /// `+263771234567` — what the API is given. Returns `null` when [raw] has no
  /// digits at all, so callers can tell "empty" from "invalid".
  static String? toE164(String raw, {String dialCode = defaultDialCode}) {
    final digits = nationalDigits(raw, dialCode: dialCode);
    if (digits.isEmpty) return null;
    return '$dialCode$digits';
  }

  /// `77 123 4567` — what the user sees while typing.
  static String formatNational(String raw,
      {String dialCode = defaultDialCode}) {
    final digits = nationalDigits(raw, dialCode: dialCode);
    if (digits.isEmpty) return '';
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2 || i == 5) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  /// `+263 77 123 4567` — for display next to a saved account.
  static String formatDisplay(String? raw,
      {String dialCode = defaultDialCode}) {
    if (raw == null || raw.trim().isEmpty) return '';
    final national = formatNational(raw, dialCode: dialCode);
    if (national.isEmpty) return raw.trim();
    return '$dialCode $national';
  }

  /// Masks all but the last three digits: `+263 •• ••• •567`.
  ///
  /// Used wherever we confirm *where* a code was sent without reprinting the
  /// whole number on a screen someone might be reading over a shoulder.
  static String mask(String? raw, {String dialCode = defaultDialCode}) {
    final digits = nationalDigits(raw ?? '', dialCode: dialCode);
    if (digits.length < 4) return formatDisplay(raw, dialCode: dialCode);
    final tail = digits.substring(digits.length - 3);
    return '$dialCode •• ••• •$tail';
  }

  /// Plain-language validation. `null` means the number is usable.
  ///
  /// Every message names the fix, never just "invalid" (§5.3: an error is copy,
  /// not a red border).
  static String? validate(String? raw, {String dialCode = defaultDialCode}) {
    final digits = nationalDigits(raw ?? '', dialCode: dialCode);
    if (digits.isEmpty) return 'Enter your mobile number';
    if (digits.length < nationalLength) {
      final missing = nationalLength - digits.length;
      return 'That is $missing digit${missing == 1 ? '' : 's'} short — '
          'Zimbabwe numbers have $nationalLength, like 77 123 4567';
    }
    if (dialCode == defaultDialCode && !mobilePrefixes.any(digits.startsWith)) {
      return 'That does not look like a Zimbabwe mobile number '
          '(${mobilePrefixes.join(', ')}…)';
    }
    return null;
  }

  /// True when the number is complete enough to submit.
  static bool isComplete(String? raw, {String dialCode = defaultDialCode}) =>
      validate(raw, dialCode: dialCode) == null;
}

/// Formats a national number as it is typed: `77 123 4567`.
///
/// Digits-only input with grouping; the caret is kept at the end of the text
/// the user just typed rather than snapping to the start.
class ZvPhoneInputFormatter extends TextInputFormatter {
  const ZvPhoneInputFormatter({this.dialCode = ZvPhone.defaultDialCode});

  final String dialCode;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = ZvPhone.formatNational(newValue.text, dialCode: dialCode);
    // Count the digits before the caret so grouping spaces never eat a keypress.
    final digitsBeforeCaret = newValue.text
        .substring(0, newValue.selection.end.clamp(0, newValue.text.length))
        .replaceAll(RegExp(r'[^0-9]'), '')
        .length;

    var offset = 0;
    var seen = 0;
    while (offset < formatted.length && seen < digitsBeforeCaret) {
      if (formatted.codeUnitAt(offset) != 0x20) seen++;
      offset++;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
