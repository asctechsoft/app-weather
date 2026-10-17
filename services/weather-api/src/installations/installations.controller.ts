import { Body, Controller, Delete, Headers, HttpCode, Patch, Post, Req } from '@nestjs/common';
import { AuthedRequest, Public } from './auth.guard';
import { InstallationsService } from './installations.service';

@Controller('v1/installations')
export class InstallationsController {
  constructor(private readonly installations: InstallationsService) {}

  /** Registers an anonymous installation and returns its bearer token (shown once). */
  @Public()
  @Post()
  @HttpCode(201)
  register(@Body() body: { platform?: string; appVersion?: string; locale?: string; timezone?: string }) {
    return this.installations.register(body ?? {});
  }

  /** Rotates the token; accepts a recently expired token (public so an expired token can refresh). */
  @Public()
  @Post('me/token')
  @HttpCode(200)
  refresh(@Headers('authorization') authorization?: string) {
    return this.installations.refresh(authorization?.startsWith('Bearer ') ? authorization.slice(7).trim() : undefined);
  }

  /** Keeps locale/timezone/app version in sync (used for push scheduling and units in messages). */
  @Patch('me')
  @HttpCode(204)
  async update(@Req() req: AuthedRequest, @Body() body: { locale?: string; timezone?: string; appVersion?: string }) {
    await this.installations.updateProfile(req.installation!, body ?? {});
  }

  /** Revokes the token and deletes this installation's server-side data. */
  @Delete('me')
  @HttpCode(204)
  async remove(@Req() req: AuthedRequest) {
    await this.installations.deleteInstallation(req.installation!);
  }
}
