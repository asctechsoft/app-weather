import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { RedisService } from './common/redis';
import { Db } from './db/db';
import { InstallationGuard, RateLimiter } from './installations/auth.guard';
import { InstallationsController } from './installations/installations.controller';
import { InstallationsService } from './installations/installations.service';
import { LocationRepository } from './locations/location.repository';
import { LocationsController } from './locations/locations.controller';
import { LocationsService } from './locations/locations.service';
import { MiscController } from './misc/misc.controller';
import { NoaaSwpcAdapter, OpenMeteoAirQualityAdapter, OpenMeteoForecastAdapter, OpenMeteoGeocodingAdapter } from './providers';
import { ExtrasService } from './weather/extras.service';
import { SnapshotService } from './weather/snapshot.service';
import { WeatherController } from './weather/weather.controller';
import { WeatherService } from './weather/weather.service';

/** Shared providers (API and worker). */
export const CORE_PROVIDERS = [
  Db,
  RedisService,
  LocationRepository,
  LocationsService,
  OpenMeteoForecastAdapter,
  OpenMeteoAirQualityAdapter,
  OpenMeteoGeocodingAdapter,
  NoaaSwpcAdapter,
  SnapshotService,
  WeatherService,
  ExtrasService,
];

@Module({
  controllers: [WeatherController, LocationsController, MiscController, InstallationsController],
  providers: [...CORE_PROVIDERS, InstallationsService, RateLimiter, { provide: APP_GUARD, useClass: InstallationGuard }],
})
export class AppModule {}
