import 'package:flutter/services.dart';

class AppInputFormatters {
  AppInputFormatters._();

  static List<TextInputFormatter> decimal({int maxDecimals = 2}) {
    final regex = RegExp('^\\d*(?:[\\.,]\\d{0,$maxDecimals})?');
    return [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]')),
      TextInputFormatter.withFunction((oldValue, newValue) {
        final text = newValue.text;
        if (text.isEmpty) return newValue;
        if (!regex.hasMatch(text)) return oldValue;
        return newValue;
      }),
    ];
  }

  static List<TextInputFormatter> integer() {
    final regex = RegExp(r'^\d*$');
    return [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
      TextInputFormatter.withFunction((oldValue, newValue) {
        final text = newValue.text;
        if (text.isEmpty) return newValue;
        if (!regex.hasMatch(text)) return oldValue;
        return newValue;
      }),
    ];
  }
}
