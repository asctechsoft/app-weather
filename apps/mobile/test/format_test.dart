import 'package:flutter_test/flutter_test.dart';
import 'package:skyweather/core/format.dart';
import 'package:skyweather/core/models.dart';
import 'package:skyweather/core/settings.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  group('unit conversion (UNIT01)', () {
    test('temperature uses F = C × 1.8 + 32, delta uses × 1.8 only', () {
      final f = Fmt(const UnitPrefs(temperature: 'f'), 'en');
      expect(f.temp(0), 32);
      expect(f.temp(100), closeTo(212, 1e-9));
      expect(f.tempDelta(2), closeTo(3.6, 1e-9));
      expect(f.degDelta(2), '+4°');
    });

    test('wind speeds from m/s', () {
      expect(Fmt(const UnitPrefs(wind: 'kmh'), 'en').windNum(3.06), '11');
      expect(Fmt(const UnitPrefs(wind: 'ms'), 'en').windNum(3.06), '3.1');
      expect(Fmt(const UnitPrefs(wind: 'mph'), 'en').windNum(10), '22');
      expect(Fmt(const UnitPrefs(wind: 'kn'), 'en').windNum(10), '19');
    });

    test('pressure, precipitation, distance', () {
      expect(Fmt(const UnitPrefs(pressure: 'inhg'), 'en').pressureNum(1013.25), '29.92');
      expect(Fmt(const UnitPrefs(pressure: 'mmhg'), 'en').pressureNum(1013.25), '760');
      expect(Fmt(const UnitPrefs(precipitation: 'in'), 'en').precipNum(25.4), '1.00');
      expect(Fmt(const UnitPrefs(distance: 'mi'), 'en').distanceNum(16093.44), '10');
      expect(Fmt(UnitPrefs.defaults, 'en').distanceNum(9620), '9.6');
    });

    test('0 mm shows 0.0, null shows a dash (never 0)', () {
      final f = Fmt(UnitPrefs.defaults, 'en');
      expect(f.precipNum(0), '0.0');
      expect(f.precipNum(null), Fmt.dash);
      expect(f.deg(null), Fmt.dash);
      expect(f.pct(null), Fmt.dash);
      expect(f.windU(null), Fmt.dash);
    });

    test('switching units back and forth does not accumulate error', () {
      const c = 26.2;
      final toF = Fmt(const UnitPrefs(temperature: 'f'), 'en').temp(c)!;
      expect((toF - 32) / 1.8, closeTo(c, 1e-9));
    });
  });

  group('time is shown in the location timezone', () {
    test('UTC instant → Asia/Bangkok wall clock', () {
      final t = Fmt.local('2026-10-16T22:52:53Z', 'Asia/Bangkok');
      expect(t.hour, 5);
      expect(t.minute, 52);
      expect(Fmt(UnitPrefs.defaults, 'en').time('2026-10-16T22:52:53Z', 'Asia/Bangkok'), '5:52 AM');
      expect(Fmt(const UnitPrefs(timeFormat: '24'), 'en').time('2026-10-16T22:52:53Z', 'Asia/Bangkok'), '05:52');
    });

    test('London DST end: same instant offsets differ', () {
      final a = Fmt.local('2026-10-25T00:30:00Z', 'Europe/London');
      final b = Fmt.local('2026-10-25T01:30:00Z', 'Europe/London');
      expect(a.hour, 1);
      expect(b.hour, 1);
    });
  });

  group('settings', () {
    test('HomeLayout migration drops removed sections (sunMoon) and appends new ones', () {
      final l = HomeLayout.fromJson({
        'order': ['daily', 'sunMoon', 'hourly'],
        'hidden': ['sunMoon', 'map'],
      });
      expect(l.order.contains('sunMoon'), isFalse);
      expect(l.order.take(2), ['daily', 'hourly']);
      expect(l.order.toSet(), HomeLayout.allSections.toSet());
      expect(l.hidden, {'map'});
    });

    test('UnitPrefs rejects unknown values', () {
      final u = UnitPrefs.fromJson({'temperature': 'k', 'wind': 'mph'});
      expect(u.temperature, 'c');
      expect(u.wind, 'mph');
    });

    test('section parse keeps status and never invents data', () {
      final sec = Section.parse<Object?>({'status': 'unsupported', 'reasonCode': 'COVERAGE_NOT_VERIFIED', 'data': null}, (v) => v);
      expect(sec.status, 'unsupported');
      expect(sec.hasData, isFalse);
      final missing = Section.parse<Object?>(null, (v) => v);
      expect(missing.status, 'error');
    });
  });
}
