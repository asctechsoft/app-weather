import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'config.dart';
import 'models.dart';

/// Versioned unit preferences (UNIT01). Canonical data is never changed — only display.
class UnitPrefs {
  const UnitPrefs({
    this.temperature = 'c',
    this.wind = 'kmh',
    this.precipitation = 'mm',
    this.pressure = 'hpa',
    this.distance = 'km',
    this.timeFormat = '12',
  });

  final String temperature; // c | f
  final String wind; // kmh | ms | mph | kn
  final String precipitation; // mm | in
  final String pressure; // hpa | inhg | mmhg
  final String distance; // km | mi
  final String timeFormat; // 12 | 24

  static const defaults = UnitPrefs();

  UnitPrefs copyWith({String? temperature, String? wind, String? precipitation, String? pressure, String? distance, String? timeFormat}) =>
      UnitPrefs(
        temperature: temperature ?? this.temperature,
        wind: wind ?? this.wind,
        precipitation: precipitation ?? this.precipitation,
        pressure: pressure ?? this.pressure,
        distance: distance ?? this.distance,
        timeFormat: timeFormat ?? this.timeFormat,
      );

  Json toJson() => {
        'temperature': temperature,
        'wind': wind,
        'precipitation': precipitation,
        'pressure': pressure,
        'distance': distance,
        'timeFormat': timeFormat,
      };

  factory UnitPrefs.fromJson(Json? j) {
    if (j == null) return defaults;
    String pick(String k, List<String> allowed, String fb) => allowed.contains(j[k]) ? j[k] as String : fb;
    return UnitPrefs(
      temperature: pick('temperature', ['c', 'f'], 'c'),
      wind: pick('wind', ['kmh', 'ms', 'mph', 'kn'], 'kmh'),
      precipitation: pick('precipitation', ['mm', 'in'], 'mm'),
      pressure: pick('pressure', ['hpa', 'inhg', 'mmhg'], 'hpa'),
      distance: pick('distance', ['km', 'mi'], 'km'),
      timeFormat: pick('timeFormat', ['12', '24'], '12'),
    );
  }

  @override
  bool operator ==(Object other) => other is UnitPrefs && jsonEncode(toJson()) == jsonEncode(other.toJson());
  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

class AppearancePrefs {
  const AppearancePrefs({this.theme = 'dark', this.weatherBackground = true, this.reduceMotion = false});
  final String theme; // system | light | dark
  final bool weatherBackground;
  final bool reduceMotion;

  AppearancePrefs copyWith({String? theme, bool? weatherBackground, bool? reduceMotion}) => AppearancePrefs(
        theme: theme ?? this.theme,
        weatherBackground: weatherBackground ?? this.weatherBackground,
        reduceMotion: reduceMotion ?? this.reduceMotion,
      );

  Json toJson() => {'theme': theme, 'weatherBackground': weatherBackground, 'reduceMotion': reduceMotion};
  factory AppearancePrefs.fromJson(Json? j) => AppearancePrefs(
        theme: ['system', 'light', 'dark'].contains(j?['theme']) ? j!['theme'] as String : 'dark',
        weatherBackground: j?['weatherBackground'] as bool? ?? true,
        reduceMotion: j?['reduceMotion'] as bool? ?? false,
      );
}

/// Home sections below the locked "current weather" + "insights" blocks (CUSTOM01).
/// Sun & moon is intentionally not a Home section (moved to the drawer).
class HomeLayout {
  const HomeLayout({required this.order, required this.hidden});

  static const allSections = ['hourly', 'daily', 'conditions', 'airQuality', 'map', 'aurora', 'widgets'];
  static const defaults = HomeLayout(order: allSections, hidden: {'aurora'});

  final List<String> order;
  final Set<String> hidden;

  List<String> get visible => order.where((s) => !hidden.contains(s)).toList();

  Json toJson() => {'order': order, 'hidden': hidden.toList()};

  /// Migration: drop unknown/removed IDs (e.g. legacy `sunMoon`), append new ones, keep user choices.
  factory HomeLayout.fromJson(Json? j) {
    if (j == null) return defaults;
    final order = (j['order'] as List? ?? const []).map((e) => e.toString()).where(allSections.contains).toList();
    for (final sct in allSections) {
      if (!order.contains(sct)) order.add(sct);
    }
    final hidden = (j['hidden'] as List? ?? const []).map((e) => e.toString()).where(allSections.contains).toSet();
    return HomeLayout(order: order, hidden: hidden);
  }
}

class RefreshPrefs {
  const RefreshPrefs({this.onOpen = true, this.onReturn = true, this.background = false, this.intervalMinutes = 60, this.wifiOnly = false});
  final bool onOpen;
  final bool onReturn;
  final bool background;
  final int intervalMinutes; // 30 | 60 | 120
  final bool wifiOnly;

  RefreshPrefs copyWith({bool? onOpen, bool? onReturn, bool? background, int? intervalMinutes, bool? wifiOnly}) => RefreshPrefs(
        onOpen: onOpen ?? this.onOpen,
        onReturn: onReturn ?? this.onReturn,
        background: background ?? this.background,
        intervalMinutes: intervalMinutes ?? this.intervalMinutes,
        wifiOnly: wifiOnly ?? this.wifiOnly,
      );

  Json toJson() => {'onOpen': onOpen, 'onReturn': onReturn, 'background': background, 'intervalMinutes': intervalMinutes, 'wifiOnly': wifiOnly};
  factory RefreshPrefs.fromJson(Json? j) => RefreshPrefs(
        onOpen: j?['onOpen'] as bool? ?? true,
        onReturn: j?['onReturn'] as bool? ?? true,
        background: j?['background'] as bool? ?? false,
        intervalMinutes: [30, 60, 120].contains(j?['intervalMinutes']) ? j!['intervalMinutes'] as int : 60,
        wifiOnly: j?['wifiOnly'] as bool? ?? false,
      );
}

/// All local, versioned settings. Saved places, layout, units, theme and refresh policy
/// stay on the device in this release (spec §10.3).
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  static const _key = 'skyweather.settings';
  static const schemaVersion = 1;

  final SharedPreferences? _prefs;

  String language = 'system'; // system | en | vi
  UnitPrefs units = UnitPrefs.defaults;
  AppearancePrefs appearance = const AppearancePrefs();
  HomeLayout homeLayout = HomeLayout.defaults;
  RefreshPrefs refresh = const RefreshPrefs();
  List<Location> savedPlaces = [];
  bool gpsEnabled = false;
  Location? gpsLocation;
  String? gpsUpdatedAt;
  String? defaultMode; // gps | saved | null (not chosen yet)
  String? defaultLocationId;
  int sessions = 0;
  String? firstUseAt;
  String? lastRatePromptAt;

  /// Locale resolved from the device when language == system (vi if the device is Vietnamese, else en).
  String deviceLanguage = 'en';

  String get effectiveLanguage => language == 'system' ? deviceLanguage : language;

  bool get hasDefault =>
      (defaultMode == 'gps' && gpsEnabled) ||
      (defaultMode == 'saved' && savedPlaces.any((p) => p.locationId == defaultLocationId));

  Location? get defaultLocation {
    if (defaultMode == 'gps') return gpsLocation;
    if (defaultMode == 'saved') {
      for (final p in savedPlaces) {
        if (p.locationId == defaultLocationId) return p;
      }
    }
    return null;
  }

  static Future<AppSettings> load() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      prefs = null;
    }
    final s = AppSettings._(prefs);
    final raw = prefs?.getString(_key);
    if (raw != null) {
      try {
        s._fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
      } catch (_) {
        // Corrupt settings: keep defaults; the user can pick a place again.
      }
    }
    s.sessions += 1;
    s.firstUseAt ??= DateTime.now().toUtc().toIso8601String();
    await s._persist();
    return s;
  }

  void _fromJson(Json j) {
    language = ['system', 'en', 'vi'].contains(j['language']) ? j['language'] as String : 'system';
    units = UnitPrefs.fromJson(m(j['units']));
    appearance = AppearancePrefs.fromJson(m(j['appearance']));
    homeLayout = HomeLayout.fromJson(m(j['homeLayout']));
    refresh = RefreshPrefs.fromJson(m(j['refresh']));
    savedPlaces = lm(j['savedPlaces']).map(Location.fromJson).take(AppConfig.savedPlacesMax).toList();
    gpsEnabled = j['gpsEnabled'] as bool? ?? false;
    gpsLocation = m(j['gpsLocation']) == null ? null : Location.fromJson(m(j['gpsLocation'])!);
    gpsUpdatedAt = s(j['gpsUpdatedAt']);
    defaultMode = s(j['defaultMode']);
    defaultLocationId = s(j['defaultLocationId']);
    sessions = i(j['sessions']) ?? 0;
    firstUseAt = s(j['firstUseAt']);
    lastRatePromptAt = s(j['lastRatePromptAt']);
    _repairDefault();
  }

  Json _toJson() => {
        'schemaVersion': schemaVersion,
        'language': language,
        'units': units.toJson(),
        'appearance': appearance.toJson(),
        'homeLayout': homeLayout.toJson(),
        'refresh': refresh.toJson(),
        'savedPlaces': savedPlaces.map((e) => e.toJson()).toList(),
        'gpsEnabled': gpsEnabled,
        'gpsLocation': gpsLocation?.toJson(),
        'gpsUpdatedAt': gpsUpdatedAt,
        'defaultMode': defaultMode,
        'defaultLocationId': defaultLocationId,
        'sessions': sessions,
        'firstUseAt': firstUseAt,
        'lastRatePromptAt': lastRatePromptAt,
      };

  Future<void> _persist() async {
    try {
      await _prefs?.setString(_key, jsonEncode(_toJson()));
    } catch (_) {}
  }

  Future<void> _commit() async {
    _repairDefault();
    await _persist();
    notifyListeners();
  }

  /// A default that points to a removed place (or disabled GPS) falls back to the first saved place.
  void _repairDefault() {
    final valid = (defaultMode == 'gps' && gpsEnabled) ||
        (defaultMode == 'saved' && savedPlaces.any((p) => p.locationId == defaultLocationId));
    if (valid) return;
    if (savedPlaces.isNotEmpty) {
      defaultMode = 'saved';
      defaultLocationId = savedPlaces.first.locationId;
    } else if (gpsEnabled) {
      defaultMode = 'gps';
      defaultLocationId = null;
    } else {
      defaultMode = null;
      defaultLocationId = null;
    }
  }

  // ---- mutations (each persists atomically) ----
  Future<void> setLanguage(String v) async {
    language = v;
    await _commit();
  }

  Future<void> setUnits(UnitPrefs v) async {
    units = v;
    await _commit();
  }

  Future<void> setAppearance(AppearancePrefs v) async {
    appearance = v;
    await _commit();
  }

  Future<void> setHomeLayout(HomeLayout v) async {
    homeLayout = v;
    await _commit();
  }

  Future<void> setRefresh(RefreshPrefs v) async {
    refresh = v;
    await _commit();
  }

  bool isSaved(String locationId) => savedPlaces.any((p) => p.locationId == locationId);
  bool get placesFull => savedPlaces.length >= AppConfig.savedPlacesMax;

  /// Returns false when the list is full (caller explains; nothing is dropped silently).
  Future<bool> addPlace(Location loc, {bool makeDefaultIfNone = true}) async {
    if (isSaved(loc.locationId)) return true;
    if (placesFull) return false;
    savedPlaces = [...savedPlaces, loc];
    if (makeDefaultIfNone && defaultMode == null) {
      defaultMode = 'saved';
      defaultLocationId = loc.locationId;
    }
    await _commit();
    return true;
  }

  Future<void> removePlace(String locationId) async {
    savedPlaces = savedPlaces.where((p) => p.locationId != locationId).toList();
    await _commit();
  }

  Future<void> reorderPlaces(int oldIndex, int newIndex) async {
    final list = [...savedPlaces];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item);
    savedPlaces = list;
    await _commit();
  }

  Future<void> setDefault({required String mode, String? locationId}) async {
    defaultMode = mode;
    defaultLocationId = mode == 'saved' ? locationId : null;
    await _commit();
  }

  Future<void> setGps({required bool enabled, Location? location}) async {
    gpsEnabled = enabled;
    if (location != null) {
      gpsLocation = location;
      gpsUpdatedAt = DateTime.now().toUtc().toIso8601String();
    }
    if (enabled && defaultMode == null) defaultMode = 'gps';
    await _commit();
  }

  Future<void> markRatePrompted() async {
    lastRatePromptAt = DateTime.now().toUtc().toIso8601String();
    await _commit();
  }

  ThemeMode get themeMode => switch (appearance.theme) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };
}

/// Makes [AppSettings] available to the widget tree and rebuilds dependents on change.
class SettingsScope extends InheritedNotifier<AppSettings> {
  const SettingsScope({super.key, required AppSettings settings, required super.child}) : super(notifier: settings);

  static AppSettings of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SettingsScope>()!.notifier!;
  static AppSettings read(BuildContext context) => context.getInheritedWidgetOfExactType<SettingsScope>()!.notifier!;
}
