import 'package:flutter/widgets.dart';

import 'api.dart';
import 'settings.dart';

/// Lightweight bilingual strings (vi + en at launch). Each call site carries both
/// translations so features stay self-contained: `tr(context, 'Humidity', 'Độ ẩm')`.
String tr(BuildContext context, String en, String vi) => SettingsScope.of(context).effectiveLanguage == 'vi' ? vi : en;

bool isVi(BuildContext context) => SettingsScope.of(context).effectiveLanguage == 'vi';

/// Condition text comes from the internal condition code, never from provider text.
String conditionLabel(BuildContext context, String code, {bool? isDay}) {
  final vi = isVi(context);
  switch (code) {
    case 'CLEAR':
      return isDay == false ? (vi ? 'Trời quang' : 'Clear') : (vi ? 'Nắng' : 'Sunny');
    case 'MOSTLY_CLEAR':
      return isDay == false ? (vi ? 'Ít mây' : 'Mostly clear') : (vi ? 'Nắng nhẹ' : 'Mostly sunny');
    case 'PARTLY_CLOUDY':
      return vi ? 'Có mây' : 'Partly cloudy';
    case 'OVERCAST':
      return vi ? 'Nhiều mây' : 'Overcast';
    case 'FOG':
      return vi ? 'Sương mù' : 'Fog';
    case 'DRIZZLE':
      return vi ? 'Mưa phùn' : 'Drizzle';
    case 'RAIN':
      return vi ? 'Mưa' : 'Rain';
    case 'FREEZING_RAIN':
      return vi ? 'Mưa băng' : 'Freezing rain';
    case 'SNOW':
      return vi ? 'Tuyết' : 'Snow';
    case 'SHOWERS':
      return vi ? 'Mưa rào' : 'Showers';
    case 'THUNDERSTORM':
      return vi ? 'Dông' : 'Thunderstorms';
    default:
      return vi ? 'Không xác định' : 'Unknown';
  }
}

String uvCategoryLabel(BuildContext context, String? c) => switch (c) {
      'low' => tr(context, 'Low', 'Thấp'),
      'moderate' => tr(context, 'Moderate', 'Trung bình'),
      'high' => tr(context, 'High', 'Cao'),
      'very_high' => tr(context, 'Very high', 'Rất cao'),
      'extreme' => tr(context, 'Extreme', 'Cực cao'),
      _ => '-',
    };

String aqiCategoryLabel(BuildContext context, String? c) => switch (c) {
      'good' => tr(context, 'Good', 'Tốt'),
      'moderate' => tr(context, 'Moderate', 'Trung bình'),
      'unhealthy_sensitive' => tr(context, 'Unhealthy for sensitive groups', 'Kém với nhóm nhạy cảm'),
      'unhealthy' => tr(context, 'Unhealthy', 'Có hại'),
      'very_unhealthy' => tr(context, 'Very unhealthy', 'Rất có hại'),
      'hazardous' => tr(context, 'Hazardous', 'Nguy hại'),
      _ => '-',
    };

String humidityLabelText(BuildContext context, String? c) => switch (c) {
      'low' => tr(context, 'Low humidity', 'Độ ẩm thấp'),
      'moderate' => tr(context, 'Moderate humidity', 'Độ ẩm trung bình'),
      'high' => tr(context, 'High humidity', 'Độ ẩm cao'),
      'very_high' => tr(context, 'Very high humidity', 'Độ ẩm rất cao'),
      _ => '-',
    };

String visibilityLabelText(BuildContext context, String? c) => switch (c) {
      'very_poor' => tr(context, 'Very poor visibility', 'Tầm nhìn rất hạn chế'),
      'poor' => tr(context, 'Limited visibility', 'Tầm nhìn hạn chế'),
      'moderate' => tr(context, 'Moderate visibility', 'Tầm nhìn khá'),
      'good' => tr(context, 'Good visibility', 'Tầm nhìn tốt'),
      _ => '-',
    };

String pressureTrendText(BuildContext context, String? trend, String? rate) => switch ((trend, rate)) {
      ('steady', _) => tr(context, 'Steady', 'Ổn định'),
      ('rising', 'fast') => tr(context, 'Rising quickly', 'Tăng nhanh'),
      ('rising', _) => tr(context, 'Rising slowly', 'Tăng chậm'),
      ('falling', 'fast') => tr(context, 'Falling quickly', 'Giảm nhanh'),
      ('falling', _) => tr(context, 'Falling slowly', 'Giảm chậm'),
      _ => tr(context, 'Trend unknown', 'Chưa xác định xu hướng'),
    };

String compassText(BuildContext context, String? c) {
  if (c == null) return '-';
  if (!isVi(context)) return c;
  const map = {'N': 'B', 'S': 'N', 'E': 'Đ', 'W': 'T'};
  return c.split('').map((ch) => map[ch] ?? ch).join();
}

/// Human explanation for a section status / reason code (shown next to "-").
String reasonText(BuildContext context, String? status, String? reason) {
  switch (reason) {
    case 'COVERAGE_NOT_VERIFIED':
      return tr(context, 'No verified alert source covers this area yet', 'Chưa có nguồn cảnh báo được xác minh cho khu vực này');
    case 'MAP_PROVIDER_NOT_CONFIGURED':
      return tr(context, 'Weather map source is not configured yet', 'Chưa cấu hình nguồn bản đồ thời tiết');
    case 'NO_ACTIVE_INSIGHTS':
      return tr(context, 'No reminders right now', 'Hiện không có nhắc nhở');
    case 'UPSTREAM_REFRESH_FAILED':
      return tr(context, 'Could not refresh — showing last data', 'Không làm mới được — đang hiển thị dữ liệu trước');
    case 'CURRENT_TOO_OLD':
      return tr(context, 'Current conditions are out of date', 'Dữ liệu hiện tại đã cũ');
    case 'STALE_DATA_NO_REMINDERS':
      return tr(context, 'Reminders paused while data is out of date', 'Tạm dừng nhắc nhở khi dữ liệu đã cũ');
    case 'NO_DATA':
      return tr(context, 'Not available from the source', 'Nguồn chưa cung cấp');
  }
  return switch (status) {
    'unsupported' => tr(context, 'Not supported here', 'Chưa hỗ trợ tại đây'),
    'stale' => tr(context, 'Data may be out of date', 'Dữ liệu có thể đã cũ'),
    'empty' => tr(context, 'No data', 'Không có dữ liệu'),
    'error' => tr(context, 'Could not load', 'Không tải được'),
    _ => '',
  };
}

String errorText(BuildContext context, Object error) {
  if (error is ApiException) {
    if (error.isNetwork) return tr(context, 'Cannot reach the SkyWeather server. Check your connection.', 'Không kết nối được máy chủ SkyWeather. Kiểm tra kết nối mạng.');
    switch (error.code) {
      case 'LOCATION_NOT_FOUND':
        return tr(context, 'This place is not known to the server.', 'Máy chủ không tìm thấy địa điểm này.');
      case 'DATE_OUT_OF_HORIZON':
        return tr(context, 'This date is outside the forecast range.', 'Ngày này nằm ngoài phạm vi dự báo.');
      case 'UPSTREAM_UNAVAILABLE':
        return tr(context, 'Weather source is temporarily unavailable.', 'Nguồn thời tiết tạm thời không khả dụng.');
      case 'SEARCH_UNAVAILABLE':
        return tr(context, 'Search is temporarily unavailable.', 'Tìm kiếm tạm thời không khả dụng.');
      case 'TIMEZONE_UNRESOLVED':
        return tr(context, 'Could not determine the time zone for this position.', 'Không xác định được múi giờ cho vị trí này.');
    }
  }
  return tr(context, 'Something went wrong.', 'Đã xảy ra lỗi.');
}

String providerName(String? id) => switch (id) {
      'open_meteo' => 'Open-Meteo',
      'open_meteo_air_quality' => 'Open-Meteo (CAMS)',
      'noaa_swpc' => 'NOAA SWPC',
      'computed' => 'SunCalc',
      'fixture' => 'Fixture (dev)',
      null => '-',
      _ => id,
    };

String dataKindLabel(BuildContext context, String? k) => switch (k) {
      'model' => tr(context, 'model', 'mô hình'),
      'observation' => tr(context, 'observation', 'quan trắc'),
      'derived' => tr(context, 'derived', 'tính từ dữ liệu'),
      'computed' => tr(context, 'computed', 'tính toán'),
      _ => '-',
    };
