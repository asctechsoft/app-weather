import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'installation.dart';

typedef Json = Map<String, dynamic>;

class ApiException implements Exception {
  ApiException(this.status, this.code, {this.messageKey, this.retryAfterSeconds, this.requestId});

  final int status;
  final String code;
  final String? messageKey;
  final int? retryAfterSeconds;
  final String? requestId;

  bool get isNetwork => status == 0;

  @override
  String toString() => 'ApiException($status, $code)';
}

/// Thin typed client for the internal Weather Server (spec §10.2).
class ApiClient {
  ApiClient({http.Client? client, String? baseUrl, InstallationAuth? auth})
      : _client = client ?? http.Client(),
        _base = baseUrl ?? AppConfig.apiBaseUrl {
    this.auth = auth ?? InstallationAuth(this);
  }

  static final ApiClient instance = ApiClient();

  final http.Client _client;
  final String _base;
  late final InstallationAuth auth;
  static const _timeout = Duration(seconds: 12);

  Uri _uri(String path, [Map<String, String?>? query]) {
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null) q[k] = v;
    });
    return Uri.parse('$_base$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  Future<Json> get(String path, [Map<String, String?>? query]) =>
      _authed((h) => _client.get(_uri(path, query), headers: {'Accept': 'application/json', ...h}));

  Future<Json> post(String path, Object body, {Map<String, String>? headers}) => _authed((h) => _client.post(
        _uri(path),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json', ...?headers, ...h},
        body: jsonEncode(body),
      ));

  Future<Json> delete(String path) => _authed((h) => _client.delete(_uri(path), headers: {'Accept': 'application/json', ...h}));

  /// Sends with the installation bearer token. On 401 the token is refreshed (or the
  /// installation re-registered) once, then the request is retried.
  Future<Json> _authed(Future<http.Response> Function(Map<String, String> authHeaders) call) async {
    final token = await auth.token();
    try {
      return await _send(() => call({'Authorization': 'Bearer $token'}));
    } on ApiException catch (e) {
      if (e.status != 401) rethrow;
      final fresh = await auth.recover(token);
      return _send(() => call({'Authorization': 'Bearer $fresh'}));
    }
  }

  /// Unauthenticated request (installation registration / token refresh).
  Future<Json> sendPublic(String method, String path, {Object? body, String? bearer}) => _send(() => _client.send(
        http.Request(method, _uri(path))
          ..headers.addAll({
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            if (bearer != null) 'Authorization': 'Bearer $bearer',
          })
          ..body = body == null ? '' : jsonEncode(body),
      ).then(http.Response.fromStream));

  Future<Json> _send(Future<http.Response> Function() call) async {
    http.Response res;
    try {
      res = await call().timeout(_timeout);
    } on TimeoutException {
      throw ApiException(0, 'TIMEOUT');
    } catch (_) {
      throw ApiException(0, 'NETWORK');
    }
    if (res.statusCode == 204) return <String, dynamic>{};
    Json body;
    try {
      body = (jsonDecode(utf8.decode(res.bodyBytes)) as Map).cast<String, dynamic>();
    } catch (_) {
      throw ApiException(res.statusCode, 'MALFORMED');
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    throw ApiException(
      res.statusCode,
      body['code']?.toString() ?? 'HTTP_${res.statusCode}',
      messageKey: body['messageKey']?.toString(),
      retryAfterSeconds: (body['retryAfterSeconds'] as num?)?.toInt(),
      requestId: body['requestId']?.toString(),
    );
  }

  // ---- endpoints ----
  Future<Json> searchLocations(String q, String locale, {int limit = 20}) =>
      get('/v1/locations/search', {'q': q, 'locale': locale, 'limit': '$limit'});
  Future<Json> resolveGps(double lat, double lon, double? accuracy) =>
      post('/v1/locations/resolve', {'latitude': lat, 'longitude': lon, 'accuracy': accuracy, 'source': 'gps'});
  Future<Json> registerLocation(String provider, String externalId, String locale) =>
      post('/v1/locations/register', {'provider': provider, 'externalId': externalId, 'locale': locale});
  Future<Json> home(String locationId) => get('/v1/weather/home', {'locationId': locationId});
  Future<Json> summaries(List<String> ids) => get('/v1/weather/summaries', {'locationIds': ids.join(',')});
  Future<Json> hourly(String locationId, {String? date, String? metric}) =>
      get('/v1/weather/hourly', {'locationId': locationId, 'date': date, 'metric': metric});
  Future<Json> daily(String locationId, {int days = 10}) =>
      get('/v1/weather/daily', {'locationId': locationId, 'days': '$days'});
  Future<Json> metric(String metric, String locationId, {String? date, String? window}) =>
      get('/v1/weather/metrics/$metric', {'locationId': locationId, 'date': date, 'window': window});
  Future<Json> refresh(String locationId, {String scope = 'all'}) =>
      post('/v1/weather/refresh', {'locationId': locationId, 'scope': scope});
  Future<Json> airQuality(String locationId, {String? date}) =>
      get('/v1/air-quality', {'locationId': locationId, 'date': date});
  Future<Json> astronomy(String locationId, {String? date}) =>
      get('/v1/astronomy', {'locationId': locationId, 'date': date});
  Future<Json> aurora(String locationId, {String hemisphere = 'north'}) =>
      get('/v1/aurora', {'locationId': locationId, 'hemisphere': hemisphere});
  Future<Json> dataSources(String? locationId) => get('/v1/data-sources', {'locationId': locationId});
  Future<Json> config(String locale) => get('/v1/config', {'locale': locale});
  /// Revokes the token and deletes this installation's server-side data (SW081).
  Future<void> deleteInstallation() async {
    await delete('/v1/installations/me');
    await auth.forget();
  }

  Future<Json> sendFeedback(Json body, String idempotencyKey) =>
      post('/v1/feedback', body, headers: {'Idempotency-Key': idempotencyKey});
}

/// Discards responses that belong to an older request (e.g. the user switched
/// location while a request was in flight). Spec §4: request generation.
class RequestGeneration {
  int _gen = 0;
  int next() => ++_gen;
  bool isCurrent(int g) => g == _gen;
}
