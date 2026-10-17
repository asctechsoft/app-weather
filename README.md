# SkyWeather (app-weather)

Ứng dụng thời tiết toàn cầu gồm app Flutter và Weather Server (NestJS). Mobile chỉ gọi Weather Server; key nhà cung cấp chỉ nằm ở server.

## Cấu trúc

```
apps/mobile/              Flutter app (Android, iOS; web/Windows để dev)
services/weather-api/     Weather Server NestJS: adapter, chuẩn hóa, cache, rule, route /v1
packages/contracts/       OpenAPI, ví dụ response, fixture nhà cung cấp cho contract test
docs/adr/                 Quyết định kiến trúc (ADR)
scream_new/               Ảnh UI tham chiếu
*.docx                    Đặc tả nghiệp vụ + API v1.0 và backlog SW001..SW099
```

## Chạy local

Yêu cầu: Node ≥ 20, Flutter 3.38.x (Dart 3.10).

### Hạ tầng local

Có Docker: `docker compose -f infra/docker-compose.yml up -d` (PostgreSQL/PostGIS, Redis, MinIO).

Không có Docker: `cd services/weather-api && npm run db:dev`. Lệnh này chạy PostgreSQL nhúng ở cổng 54329 và in ra `DATABASE_URL`.

### Weather Server

```bash
cd services/weather-api
npm ci
npm run build
export DATABASE_URL=postgres://skyweather:skyweather_dev@127.0.0.1:54329/skyweather
npm run migrate                                   # migration có khóa, chạy lặp lại an toàn
npm run import:geonames -- --dataset cities500    # danh mục địa điểm (máy ít RAM: cities15000)
npm start                                         # http://127.0.0.1:8080/v1/health/ready
npm run worker                                    # job nền: Kp NOAA, prefetch nơi đang dùng (cần Redis để chia sẻ cache)
npm test                                          # unit + tích hợp trên PostgreSQL nhúng
```

- Mọi route `/v1` (trừ health, config, đăng ký installation) đều cần `Authorization: Bearer <token>`. Lấy token qua `POST /v1/installations`.
- Import GeoNames sẽ từ chối kích hoạt nếu hơn 5% địa điểm biến mất so với dataset đang dùng. Muốn kích hoạt thì thêm `--approve-large-changes` sau khi đã duyệt. Có thể chạy thử bằng `--dry-run`.

Cấu hình qua biến môi trường (xem `.env.example`, không commit `.env`):

| Biến | Mặc định | Ghi chú |
|---|---|---|
| `PORT` | 8080 | |
| `PROVIDER_MODE` | live | `fixture` đọc `packages/contracts/fixtures`, không gọi mạng |
| `OPEN_METEO_*_HOST` | host free | Production: `customer-api.open-meteo.com` + `OPEN_METEO_API_KEY` |
| `DATA_DIR` | ./data | Kho JSON dev (locations, feedback). Production dùng PostgreSQL |
| `CORS_ORIGINS` | * | Chỉ dùng `*` ở local |

Free endpoint Open-Meteo chỉ dùng cho phát triển, không dùng cho bản thương mại.

### Mobile

```bash
cd apps/mobile
flutter pub get
flutter analyze
flutter test
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8080
# Android (flavor dev/staging/prod cài song song):
flutter run --flavor dev --dart-define=APP_ENV=dev --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

Bản release Android lấy khóa ký từ `android/key.properties`; file này bị git ignore và do CI cung cấp. iOS cần cấu hình scheme/bundle ID theo môi trường trên macOS (chưa làm).

Nếu máy dùng proxy hệ thống, gọi server local bằng `curl --noproxy '*'`.

## Phạm vi đã có trong bản này

- Server: tìm địa điểm (GeoNames qua Open-Meteo Geocoding, ID UUIDv5 ổn định), resolve GPS + timezone, Home snapshot, summaries (≤20), hourly theo ngày, daily (horizon thật), metrics (wind, rain, humidity, visibility, uv, pressure, feels-like), AQI mô hình (CAMS, không có trạm), thiên văn tính toán, Kp NOAA, data-sources, feedback idempotent, refresh có cooldown.
- App: onboarding (GPS hoặc tìm city), Home + Drawer + Customize Home, dự báo giờ/10 ngày, các màn chỉ số, AQI, Sun & moon, Aurora, quản lý địa điểm, cài đặt (ngôn ngữ vi/en, đơn vị, giao diện, làm mới, vị trí mặc định), nguồn dữ liệu, góp ý.
- Hạ tầng: PostgreSQL (migration), danh mục GeoNames, tìm kiếm không dấu, resolve GPS theo polygon timezone, installation token, rate limit, cache Redis + circuit breaker, worker, CI.
- Chưa có nguồn/hạ tầng nên hiển thị "chưa hỗ trợ" (không có switch giả): cảnh báo chính thức, bản đồ/radar, push notification, widget hệ điều hành, đính kèm ảnh feedback.
