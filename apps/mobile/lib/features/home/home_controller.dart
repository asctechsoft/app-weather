import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/settings.dart';

enum GpsResult { ok, serviceOff, denied, deniedForever, timeout, serverError }

/// Owns the Home snapshot for the active place.
/// - Shows the device cache for *that* place first, then refreshes.
/// - A response for a place the user already left is discarded (request generation).
class HomeController extends ChangeNotifier {
  HomeController(this.settings, {ApiClient? api}) : api = api ?? ApiClient.instance;

  final AppSettings settings;
  final ApiClient api;
  final _gen = RequestGeneration();

  Location? active;
  HomeSnapshot? snapshot;
  bool loading = false;
  Object? error;
  DateTime? lastFetchAt;
  bool fromCache = false;

  static String _cacheKey(String id) => 'skyweather.home.v1.$id';

  Future<void> select(Location loc, {bool forceNetwork = false}) async {
    final g = _gen.next();
    active = loc;
    error = null;
    // Never keep the previous place's numbers under the new name.
    if (snapshot?.location.locationId != loc.locationId) snapshot = null;
    fromCache = false;
    loading = true;
    notifyListeners();

    if (snapshot == null) {
      final cached = await _readCache(loc.locationId);
      if (!_gen.isCurrent(g)) return;
      if (cached != null) {
        snapshot = cached;
        fromCache = true;
        notifyListeners();
      }
    }
    await _fetch(g, loc);
  }

  Future<void> reload({bool manual = false}) async {
    final loc = active;
    if (loc == null) return;
    final g = _gen.next();
    loading = true;
    error = null;
    notifyListeners();
    if (manual) {
      try {
        await api.refresh(loc.locationId);
      } catch (_) {
        // Cooldown or failure: fall through to a normal GET that serves the cache policy.
      }
      if (!_gen.isCurrent(g)) return;
    }
    await _fetch(g, loc);
  }

  Future<void> _fetch(int g, Location loc) async {
    try {
      var json = await _getHome(loc);
      if (!_gen.isCurrent(g)) return;
      snapshot = HomeSnapshot(json);
      fromCache = false;
      lastFetchAt = DateTime.now();
      error = null;
      _writeCache(loc.locationId, json);
    } catch (e) {
      if (!_gen.isCurrent(g)) return;
      error = e;
    } finally {
      if (_gen.isCurrent(g)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  /// If the server forgot a place (data reset), re-register it by its GeoNames id once.
  Future<Json> _getHome(Location loc) async {
    try {
      return await api.home(loc.locationId);
    } on ApiException catch (e) {
      final gid = loc.geonamesId;
      if (e.code == 'LOCATION_NOT_FOUND' && gid != null) {
        await api.registerLocation('geonames', gid, settings.effectiveLanguage);
        return api.home(loc.locationId);
      }
      if (e.code == 'LOCATION_NOT_FOUND' && loc.isGps) {
        final fresh = Location.fromJson(await api.resolveGps(loc.latitude, loc.longitude, null));
        return api.home(fresh.locationId);
      }
      rethrow;
    }
  }

  Future<HomeSnapshot?> _readCache(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(id));
      if (raw == null) return null;
      return HomeSnapshot((jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String id, Json json) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey(id), jsonEncode(json));
    } catch (_) {}
  }

  /// Requests location permission only after an explicit user action, then resolves the
  /// GPS point on the server (weather uses the GPS coordinate, not a city centre).
  Future<(GpsResult, Location?)> locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return (GpsResult.serviceOff, null);
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) return (GpsResult.deniedForever, null);
      if (perm == LocationPermission.denied || perm == LocationPermission.unableToDetermine) return (GpsResult.denied, null);
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)),
      );
      try {
        final loc = Location.fromJson(await api.resolveGps(pos.latitude, pos.longitude, pos.accuracy));
        await settings.setGps(enabled: true, location: loc);
        return (GpsResult.ok, loc);
      } catch (_) {
        return (GpsResult.serverError, null);
      }
    } catch (e) {
      debugPrint('locate failed: $e');
      return (GpsResult.timeout, null);
    }
  }
}
