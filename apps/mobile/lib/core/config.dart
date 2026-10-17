import 'package:flutter/foundation.dart';

/// Build-time configuration. Provider secrets never live in the app: the app only
/// talks to the SkyWeather Weather Server.
class AppConfig {
  static const String _apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'dev');

  static String get apiBaseUrl {
    if (_apiBaseUrl.isNotEmpty) return _apiBaseUrl;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080'; // Android emulator → host machine
    }
    return 'http://127.0.0.1:8080';
  }

  static const int savedPlacesMax = 20;
  static const int searchMinChars = 2;
  static const Duration searchDebounce = Duration(milliseconds: 300);
  static const Duration refreshCooldown = Duration(seconds: 60);
}
