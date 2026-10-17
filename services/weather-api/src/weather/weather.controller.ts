import { Body, Controller, Get, HttpCode, Param, Post, Query } from '@nestjs/common';
import { badRequest } from '../common/errors';
import { ExtrasService } from './extras.service';
import { WeatherService } from './weather.service';

function requireId(id: string | undefined): string {
  if (!id) throw badRequest('locationId', 'validation.required');
  return id;
}

@Controller('v1')
export class WeatherController {
  constructor(
    private readonly weather: WeatherService,
    private readonly extras: ExtrasService,
  ) {}

  @Get('weather/home')
  home(@Query('locationId') locationId?: string) {
    return this.weather.home(requireId(locationId));
  }

  @Get('weather/summaries')
  summaries(@Query('locationIds') locationIds?: string) {
    return this.weather.summaries((locationIds ?? '').split(',').map((s) => s.trim()).filter(Boolean));
  }

  @Get('weather/hourly')
  hourly(@Query('locationId') locationId?: string, @Query('date') date?: string, @Query('metric') metric?: string) {
    return this.weather.hourly(requireId(locationId), date, metric);
  }

  @Get('weather/daily')
  daily(@Query('locationId') locationId?: string, @Query('days') days?: string) {
    return this.weather.daily(requireId(locationId), days === undefined ? 10 : Number(days));
  }

  @Get('weather/metrics/:metric')
  metric(@Param('metric') metric: string, @Query('locationId') locationId?: string, @Query('date') date?: string, @Query('window') window?: string) {
    return this.weather.metric(metric, requireId(locationId), date, window);
  }

  @Post('weather/refresh')
  @HttpCode(200)
  refresh(@Body() body: { locationId?: string; scope?: string }) {
    return this.weather.refresh(requireId(body?.locationId), body?.scope ?? 'all');
  }

  @Get('air-quality')
  airQuality(@Query('locationId') locationId?: string, @Query('date') date?: string) {
    return this.extras.airQuality(requireId(locationId), date);
  }

  @Get('astronomy')
  astronomy(@Query('locationId') locationId?: string, @Query('date') date?: string) {
    return this.extras.astronomy(requireId(locationId), date);
  }

  @Get('aurora')
  aurora(@Query('locationId') locationId?: string, @Query('hemisphere') hemisphere?: string) {
    return this.extras.aurora(requireId(locationId), hemisphere);
  }
}
