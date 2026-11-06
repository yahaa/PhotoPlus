import 'package:flutter/cupertino.dart';

/// Cupertino-leaning theme. TODO: align with iOS Photos look.
abstract final class AppTheme {
  static CupertinoThemeData get cupertino => const CupertinoThemeData(
        brightness: Brightness.light,
      );
}
