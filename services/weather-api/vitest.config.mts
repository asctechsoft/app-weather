import swc from 'unplugin-swc';
import { defineConfig } from 'vitest/config';

// SWC keeps `emitDecoratorMetadata`, which NestJS dependency injection needs in integration tests.
export default defineConfig({
  plugins: [swc.vite({ module: { type: 'es6' } })],
  test: {
    include: ['test/**/*.spec.ts'],
    testTimeout: 30_000,
    hookTimeout: 180_000,
    // One worker at a time keeps memory low and avoids parallel embedded PostgreSQL instances.
    fileParallelism: false,
    env: {
      PROVIDER_MODE: 'fixture',
      DATABASE_URL: 'postgres://skyweather:it@127.0.0.1:55432/skyweather',
      REDIS_URL: '',
      RATE_LIMIT_PER_MINUTE: '1000',
    },
  },
});
