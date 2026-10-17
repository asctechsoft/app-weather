import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;

import 'app.dart';
import 'core/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  await initializeDateFormatting('en_US');
  await initializeDateFormatting('vi');
  final settings = await AppSettings.load();
  // Device language decides the default (vi if available, otherwise English).
  settings.deviceLanguage = PlatformDispatcher.instance.locale.languageCode == 'vi' ? 'vi' : 'en';
  runApp(SkyWeatherApp(settings: settings));
}
