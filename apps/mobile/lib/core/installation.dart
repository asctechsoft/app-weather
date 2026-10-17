import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api.dart';

/// Anonymous installation credential (SW014, SW027).
/// The server issues a bearer token; it is kept in secure storage (Keychain / Keystore),
/// never in plain preferences, and never logged.
class InstallationAuth {
  InstallationAuth(this._api, {FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final ApiClient _api;
  final FlutterSecureStorage _storage;
  static const _key = 'skyweather.installation.token';

  String? _token;
  Future<String>? _pending;

  /// Current token, registering this installation on first use.
  Future<String> token() async {
    if (_token != null) return _token!;
    return _pending ??= _load().whenComplete(() => _pending = null);
  }

  Future<String> _load() async {
    try {
      final stored = await _storage.read(key: _key);
      if (stored != null && stored.isNotEmpty) return _token = stored;
    } catch (_) {
      // Storage unavailable (e.g. private browser window): fall back to a session-only token.
    }
    return _register();
  }

  /// Called after a 401: try to rotate the token, otherwise register a new installation.
  Future<String> recover(String failedToken) async {
    if (_token != null && _token != failedToken) return _token!; // another request already recovered
    return _pending ??= _recover(failedToken).whenComplete(() => _pending = null);
  }

  Future<String> _recover(String failedToken) async {
    try {
      final r = await _api.sendPublic('POST', '/v1/installations/me/token', bearer: failedToken);
      return _save(r['token'] as String);
    } on ApiException catch (e) {
      if (e.status != 401) rethrow;
      return _register();
    }
  }

  Future<String> _register() async {
    String version = '0.0.0';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.buildNumber.isEmpty ? info.version : '${info.version}+${info.buildNumber}';
    } catch (_) {}
    final r = await _api.sendPublic('POST', '/v1/installations', body: {
      'platform': _platform(),
      'appVersion': version,
      'locale': PlatformDispatcher.instance.locale.languageCode,
    });
    return _save(r['token'] as String);
  }

  Future<String> _save(String token) async {
    _token = token;
    try {
      await _storage.write(key: _key, value: token);
    } catch (_) {}
    return token;
  }

  /// Local reset after the server-side installation has been deleted.
  Future<void> forget() async {
    _token = null;
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }

  static String _platform() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.windows => 'windows',
      TargetPlatform.macOS => 'macos',
      _ => 'linux',
    };
  }
}
