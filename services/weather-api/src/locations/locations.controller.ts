import { Body, Controller, Get, HttpCode, Param, Post, Query } from '@nestjs/common';
import { badRequest } from '../common/errors';
import { LocationsService } from './locations.service';

@Controller('v1/locations')
export class LocationsController {
  constructor(private readonly locations: LocationsService) {}

  @Get('search')
  async search(@Query('q') q?: string, @Query('locale') locale?: string, @Query('limit') limit?: string, @Query('countryCode') countryCode?: string) {
    const results = await this.locations.search(q ?? '', locale ?? 'en', limit ? Number(limit) : 10, countryCode || undefined);
    return { query: q, results };
  }

  @Post('resolve')
  @HttpCode(200)
  resolve(@Body() body: { latitude?: number; longitude?: number; accuracy?: number | null; source?: string }) {
    if (typeof body?.latitude !== 'number' || typeof body?.longitude !== 'number') throw badRequest('latitude', 'validation.required');
    return this.locations.resolve(body.latitude, body.longitude, body.accuracy ?? null);
  }

  @Post('register')
  @HttpCode(200)
  register(@Body() body: { provider?: string; externalId?: string; locale?: string }) {
    return this.locations.registerExternal(body?.provider ?? '', String(body?.externalId ?? ''), body?.locale ?? 'en');
  }

  @Get(':id')
  get(@Param('id') id: string) {
    return this.locations.get(id);
  }
}
