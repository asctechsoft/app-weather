import 'api.dart';

/// Canonical contract models (schema 1.0). Every numeric field is `num?`:
/// `null` means "not available" and must be displayed as "-", never as 0.

double? d(Object? v) => v is num ? v.toDouble() : null;
int? i(Object? v) => v is num ? v.toInt() : null;
String? s(Object? v) => v?.toString();
Json? m(Object? v) => v is Map ? v.cast<String, dynamic>() : null;
List<Json> lm(Object? v) => v is List ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : const [];

/// Reads a nested value with a dotted path: `jp(json, 'summary.peakGust.value')`.
Object? jp(Object? root, String path) {
  Object? cur = root;
  for (final k in path.split('.')) {
    if (cur is Map) {
      cur = cur[k];
    } else {
      return null;
    }
  }
  return cur;
}

class Location {
  Location({
    required this.locationId,
    required this.kind,
    required this.name,
    required this.countryCode,
    required this.country,
    required this.admin1,
    required this.latitude,
    required this.longitude,
    required this.timezone,
    required this.externalIds,
  });

  final String locationId;
  final String kind; // city | administrative_area | gps | place
  final String? name;
  final String? countryCode;
  final String? country;
  final String? admin1;
  final double latitude;
  final double longitude;
  final String timezone;
  final List<Json> externalIds;

  bool get isGps => kind == 'gps';

  String? get geonamesId {
    for (final e in externalIds) {
      if (e['provider'] == 'geonames') return e['externalId']?.toString();
    }
    return null;
  }

  factory Location.fromJson(Json j) => Location(
        locationId: j['locationId'] as String,
        kind: s(j['kind']) ?? 'place',
        name: s(j['name']),
        countryCode: s(j['countryCode']),
        country: s(j['country']),
        admin1: s(j['admin1']),
        latitude: d(j['latitude']) ?? 0,
        longitude: d(j['longitude']) ?? 0,
        timezone: s(j['timezone']) ?? 'UTC',
        externalIds: lm(j['externalIds']),
      );

  Json toJson() => {
        'locationId': locationId,
        'kind': kind,
        'name': name,
        'countryCode': countryCode,
        'country': country,
        'admin1': admin1,
        'latitude': latitude,
        'longitude': longitude,
        'timezone': timezone,
        'externalIds': externalIds,
      };
}

class SourceMeta {
  SourceMeta(this.json);
  final Json json;
  String? get providerId => s(json['providerId']);
  String? get dataKind => s(json['dataKind']);
  String? get validAt => s(json['validAt']);
  String? get fetchedAt => s(json['fetchedAt']);
  String? get expiresAt => s(json['expiresAt']);
  static SourceMeta? from(Object? v) => m(v) == null ? null : SourceMeta(m(v)!);
}

/// Section envelope: status is one of ready, empty, unsupported, stale, error.
class Section<T> {
  Section({required this.status, required this.reasonCode, required this.source, required this.data});

  final String status;
  final String? reasonCode;
  final SourceMeta? source;
  final T? data;

  bool get hasData => data != null && (status == 'ready' || status == 'stale');
  bool get isStale => status == 'stale';

  static Section<T> parse<T>(Object? raw, T Function(Object? data) parseData) {
    final j = m(raw);
    if (j == null) return Section(status: 'error', reasonCode: 'MISSING_SECTION', source: null, data: null);
    T? data;
    try {
      data = j['data'] == null ? null : parseData(j['data']);
    } catch (_) {
      return Section(status: 'error', reasonCode: 'PARSE_ERROR', source: SourceMeta.from(j['source']), data: null);
    }
    return Section(
      status: s(j['status']) ?? 'error',
      reasonCode: s(j['reasonCode']),
      source: SourceMeta.from(j['source']),
      data: data,
    );
  }
}

class CurrentData {
  CurrentData(this.j);
  final Json j;
  String get validAt => j['validAt'] as String;
  double? get temperatureC => d(j['temperatureC']);
  double? get feelsLikeC => d(j['feelsLikeC']);
  double? get humidityPct => d(j['humidityPct']);
  double? get dewPointC => d(j['dewPointC']);
  String get conditionCode => s(j['conditionCode']) ?? 'UNKNOWN';
  bool? get isDay => j['isDay'] as bool?;
  double? get windSpeedMs => d(j['windSpeedMs']);
  double? get windDirectionDeg => d(j['windDirectionDeg']);
  double? get windGustMs => d(j['windGustMs']);
  double? get seaLevelPressureHpa => d(j['seaLevelPressureHpa']);
  double? get cloudCoverPct => d(j['cloudCoverPct']);
  double? get visibilityM => d(j['visibilityM']);
  double? get uvIndex => d(j['uvIndex']);
  double? get precipitationMm => d(j['precipitationMm']);
}

class HourlyRecord {
  HourlyRecord(this.j);
  final Json j;
  String get time => j['time'] as String;
  String get localTime => j['localTime'] as String; // YYYY-MM-DDTHH:mm (location wall clock)
  String get localDate => j['localDate'] as String;
  int get utcOffsetSeconds => i(j['utcOffsetSeconds']) ?? 0;
  int get localHour => int.parse(localTime.substring(11, 13));
  double? get temperatureC => d(j['temperatureC']);
  double? get feelsLikeC => d(j['feelsLikeC']);
  double? get humidityPct => d(j['humidityPct']);
  double? get dewPointC => d(j['dewPointC']);
  double? get rainProbabilityPct => d(j['rainProbabilityPct']);
  double? get precipitationMm => d(j['precipitationMm']);
  String get conditionCode => s(j['conditionCode']) ?? 'UNKNOWN';
  bool? get isDay => j['isDay'] as bool?;
  double? get seaLevelPressureHpa => d(j['seaLevelPressureHpa']);
  double? get cloudCoverPct => d(j['cloudCoverPct']);
  double? get visibilityM => d(j['visibilityM']);
  double? get windSpeedMs => d(j['windSpeedMs']);
  double? get windDirectionDeg => d(j['windDirectionDeg']);
  double? get windGustMs => d(j['windGustMs']);
  double? get uvIndex => d(j['uvIndex']);
  String get intervalStartAt => j['intervalStartAt'] as String;
  String get intervalEndAt => j['intervalEndAt'] as String;

  static List<HourlyRecord> list(Object? v) => lm(v).map(HourlyRecord.new).toList();
}

class DailyRecord {
  DailyRecord(this.j);
  final Json j;
  String get localDate => j['localDate'] as String;
  String get conditionCode => s(j['conditionCode']) ?? 'UNKNOWN';
  double? get minC => d(j['minC']);
  double? get maxC => d(j['maxC']);
  String? get sunriseAt => s(j['sunriseAt']);
  String? get sunsetAt => s(j['sunsetAt']);
  double? get daylightSeconds => d(j['daylightSeconds']);
  double? get uvIndexMax => d(j['uvIndexMax']);
  double? get precipitationTotalMm => d(j['precipitationTotalMm']);
  double? get rainProbabilityMaxPct => d(j['rainProbabilityMaxPct']);

  static List<DailyRecord> list(Object? v) => lm(v).map(DailyRecord.new).toList();
}

class Extremum {
  Extremum(this.value, this.time, this.localTime);
  final double value;
  final String time;
  final String localTime;
  static Extremum? from(Object? v) {
    final j = m(v);
    if (j == null || d(j['value']) == null) return null;
    return Extremum(d(j['value'])!, s(j['time']) ?? '', s(j['localTime']) ?? '');
  }
}

class Insight {
  Insight(this.j);
  final Json j;
  String get type => j['type'] as String;
  double? get value => d(j['value']);
  String? get category => s(j['category']);
  String? get fromLocal => s(j['fromLocal']);
  String? get toLocal => s(j['toLocal']);
}

/// GET /v1/weather/home
class HomeSnapshot {
  HomeSnapshot(this.json)
      : location = Location.fromJson(m(json['location'])!),
        localDate = json['localDate'] as String,
        generatedAt = s(json['generatedAt']),
        current = Section.parse(jp(json, 'sections.current'), (v) => CurrentData(m(v)!)),
        today = Section.parse(jp(json, 'sections.today'), (v) => DailyRecord(m(v)!)),
        highlights = Section.parse(jp(json, 'sections.highlights'), (v) => m(v)!),
        hourly = Section.parse(jp(json, 'sections.hourly'), HourlyRecord.list),
        daily = Section.parse(jp(json, 'sections.daily'), DailyRecord.list),
        airQuality = Section.parse(jp(json, 'sections.airQuality'), (v) => m(v)!),
        insights = Section.parse(jp(json, 'sections.insights'), (v) => lm(v).map(Insight.new).toList()),
        officialAlerts = Section.parse(jp(json, 'sections.officialAlerts'), (v) => v),
        aurora = Section.parse(jp(json, 'sections.aurora'), (v) => m(v)!),
        map = Section.parse(jp(json, 'sections.map'), (v) => v);

  final Json json;
  final Location location;
  final String localDate;
  final String? generatedAt;
  final Section<CurrentData> current;
  final Section<DailyRecord> today;
  final Section<Json> highlights;
  final Section<List<HourlyRecord>> hourly;
  final Section<List<DailyRecord>> daily;
  final Section<Json> airQuality;
  final Section<List<Insight>> insights;
  final Section<Object?> officialAlerts;
  final Section<Json> aurora;
  final Section<Object?> map;
}
