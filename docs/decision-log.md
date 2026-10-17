# Decision log và capability matrix (SW003)

- Cơ sở: PO chỉ đạo "làm theo các quyết định trong file TODO". Vì vậy stack tham khảo trong SW001 và các giá trị đề xuất của đặc tả 1.0 được chấp nhận làm quyết định làm việc với trạng thái **approved-by-PO-instruction 2026-10-17**.
- Các mục cần hợp đồng/gói thương mại vẫn là **conditional (blocked on purchase)**: dev dựng contract bằng fixture, tính năng giữ flag off/unsupported cho tới khi có quyền và kiểm thử. Không mục nào ở đây được hiểu là đã mua.
- Vai trò: PO, TL, BE, MOB, DATA, QA, UX, DevOps. Không ghi tên người.

## Trạng thái

| Trạng thái | Ý nghĩa |
|---|---|
| approved | approved-by-PO-instruction 2026-10-17; dùng làm tiêu chí phát triển và kiểm thử. Có thể chỉnh bằng một dòng mới trong log (không sửa dòng cũ). |
| conditional | Đã chọn hướng, nhưng phụ thuộc mua gói/hợp đồng/kiểm chứng coverage. Chỉ bật ngoài fixture khi có bằng chứng entitlement + test. |
| open | Chưa quyết định; cần owner chốt. |

## 1. Quyết định

### Nền tảng và kiến trúc

| ID | Chủ đề | Quyết định / giá trị | Nguồn | Trạng thái | Owner | Review-by |
|---|---|---|---|---|---|---|
| D001 | Nền tảng phát hành | Android + iOS cùng đợt. Web/Windows chỉ để dev/kiểm thử. | SW001; đặc tả §14 | approved | PO, TL | OS tối thiểu chốt theo SDK thực dùng trước M2 |
| D002 | Mobile framework | Flutter 3.38.9 / Dart 3.10.8 (khóa trong CI) | SW001; ADR 001 | approved | TL, MOB | Đánh giá lại khi spike widget native (SW072) |
| D003 | API và worker | NestJS TypeScript (Node ≥ 20, CI dùng 22), API `services/weather-api`, worker `services/weather-worker` | SW001, SW007 | approved | TL, BE | Worker chưa có — tạo ở M0 |
| D004 | Cơ sở dữ liệu | PostgreSQL 16 + PostGIS 3.4 | SW001; đặc tả §10.1 | approved | BE, DATA | — |
| D005 | Cache / lock | Redis 7.2 (dev: in-memory TTL + single-flight) | SW001; §10.4 | approved | BE | Thay in-memory trước staging |
| D006 | Object storage | S3-compatible (MinIO local), cho attachment feedback | SW001; §10.1 | approved | DevOps | Nhà cung cấp cloud chốt ở SW009 |
| D007 | Thiên văn | suncalc 1.9.0 thay Astral/Skyfield để giữ một runtime; sai số so nguồn tham chiếu ở SW054 | ADR 001; §5.6 | approved | BE | Nếu sai số không đạt → tách service astronomy |
| D008 | Không đăng nhập | Không bắt account; saved places, units, appearance, homeLayout, refreshPolicy lưu local; server giữ installation có bearer token (expiry/refresh/revoke) | §2, §10.3, §12; SW014 | approved | TL, BE | — |
| D009 | Mobile chỉ gọi Weather Server | Provider secret chỉ ở server; ngoại lệ: base map dùng public restricted token phía client nếu hợp đồng yêu cầu | §1, §10.1; TODO nguyên tắc | approved | TL | — |
| D010 | Thời gian | Lưu UTC (epoch từ provider), hiển thị theo IANA timezone của địa điểm; không cộng 86400 s | §11.1 | approved | BE, MOB | — |
| D011 | Canonical units | °C, m/s, mm, hPa, m, %, độ, μg/m³; quy đổi ở lớp trình bày mobile, làm tròn một lần | §9.1, UNIT01 | approved | BE, MOB | — |
| D012 | ID địa điểm | UUID nội bộ ổn định (hiện tại UUIDv5 từ provider + externalId); tên không làm khóa | §6.1 | approved | BE, DATA | Giữ tương thích khi chuyển sang Postgres |

### Ngôn ngữ, nội dung, phạm vi UI

| ID | Chủ đề | Quyết định / giá trị | Nguồn | Trạng thái | Owner | Review-by |
|---|---|---|---|---|---|---|
| D020 | Ngôn ngữ ra mắt | vi + en; mặc định theo thiết bị, fallback en | §2; SW067 | approved | PO | — |
| D021 | Sun & Moon trên Home | Bỏ khối khỏi Home và Customize Home; ASTRO01 qua Drawer | TODO; SW002, SW036, SW070 | approved | PO, UX | — |
| D022 | Sunrise arc trong hero Home | Tạm giữ vì ảnh UI mới còn arc | `docs/screens.md` C3 | open | UX, PO | Trước UI signoff SW089 |
| D023 | Hành vi tab Sun/Moon | Tab cuộn tới phần tương ứng trong một trang | ASTRO01; §14 | approved | UX | Xác nhận khi UI signoff |
| D024 | Widgets trên Home | Card giới thiệu/shortcut tới WIDGET01, không phải forecast | CUSTOM01; §14 | approved | UX | — |
| D025 | Aurora section Home | Mặc định ẩn; local outlook định tính, nhãn thử nghiệm, không % nhìn thấy | AUR01, CUSTOM01 | approved | PO | — |

### Giới hạn và ngưỡng sản phẩm

| ID | Chủ đề | Quyết định / giá trị | Nguồn | Trạng thái | Owner | Review-by |
|---|---|---|---|---|---|---|
| D030 | Số địa điểm lưu | Tối đa 20 city (GPS không chiếm slot); summaries batch ≤ 20 | PLACE01; SW014, SW033 | approved | PO | — |
| D031 | Tìm kiếm | Tối thiểu 2 ký tự, debounce 300 ms, tối đa 20 kết quả | §6.3; SW019 | approved | PO, BE | — |
| D032 | Manual refresh | Cooldown 60 s / installation / location | REFRESH01; SW025 | approved | BE | — |
| D033 | Tần suất background | 30 phút / 1 giờ / 2 giờ (mong muốn, OS điều phối) | REFRESH01 | approved | MOB | — |
| D034 | TTL cache | Current 15 phút (stale tối đa 2 h); Hourly/Daily 30 phút (6 h); AQI 60 phút (3 h); Astronomy 24 h theo ngày (7 ngày); Alert polling 5 phút (15 phút hoặc đến expires); Map manifest 5 phút (15 phút); NOAA 5 phút (30 phút); Search 24 h (7 ngày) | §10.4; SW025 | approved | BE, TL | Điều chỉnh theo hợp đồng khi mua gói |
| D035 | Timeout provider | 3 s / provider, 5 s tổng foreground; retry backoff + jitter; circuit breaker theo provider | §10.4 | approved | BE | — |
| D036 | Rain reminder | Trong 2 h tới amount ≥ 0.2 mm và PoP ≥ 50% (nếu có); một lần/cửa sổ sự kiện | §11.2; SW061 | approved | PO, BE | — |
| D037 | Next shower (RAIN01) | ≥ 0.2 mm/h và PoP ≥ 50% trong 48 h, nhãn "dự kiến" | RAIN01 | approved | PO | — |
| D038 | High UV reminder | UV hourly ≥ 6 trong 3 h tới; một lần/location/localDate/band | §11.2 | approved | PO | — |
| D039 | AQI reminder | US AQI ≥ 151 trong 3 h tới; một lần/ngày/mức tăng đáng kể | §11.2 | approved | PO | — |
| D040 | Quiet hours | Mặc định 22:00–07:00 theo timezone thiết bị đã đăng ký | NOTI01; SW065 | approved | PO | — |
| D041 | Daily forecast push | Theo timezone địa điểm; GPS cần vị trí mới trong 24 h | NOTI01, §11.2 | approved | PO | — |
| D042 | Aurora push | Tắt mặc định, chỉ bật khi logic vùng quan sát được kiểm thử | §11.2; SW054 | approved (giữ off) | PO, QA | — |
| D043 | Nhãn độ ẩm | < 30% thấp; 30–< 60% trung bình; 60–80% cao; > 80% rất cao | HUM01 | approved | PO | — |
| D044 | Nhãn tầm nhìn | < 1 km rất hạn chế; 1–< 5 km hạn chế; 5–< 10 km khá; ≥ 10 km tốt | VIS01 | approved | PO | — |
| D045 | Mức UV | EPA: 0–2, 3–5, 6–7, 8–10, ≥ 11; phân loại bằng số chưa làm tròn; strong UV window = dải liên tục UV ≥ 6 chứa cực đại | UV01 | approved | PO | — |
| D046 | Mức AQI | US AQI 0–50, 51–100, 101–150, 151–200, 201–300, ≥ 301 (AirNow) | AQ01 | approved | PO | — |
| D047 | Áp suất trend | p(t) − p(t−3h); \|delta\| < 1 hPa = ổn định | PRES01 | approved | PO | — |
| D048 | Feels like "similar" | \|delta\| < 0.5 °C (trước làm tròn) | FEEL01 | approved | PO | — |
| D049 | Beaufort | Ẩn cho đến khi có bảng chuẩn có version | WIND01 | open | BE, QA | Trước M2 |
| D050 | Rate prompt | Sau 5 phiên và 7 ngày; tối đa 1 lần/90 ngày; không khi app đang lỗi/cảnh báo nghiêm trọng | RATE01; SW079 | approved | PO | — |
| D051 | Feedback | Subject 5–120, message 10–5000 ký tự; ≤ 3 ảnh JPEG/PNG/WebP, ≤ 5 MB/ảnh; diagnostics mặc định off | FEEDBACK01; SW078 | approved | PO | — |
| D052 | Mục tiêu hiệu năng | Home từ cache ≤ 1 s; API cached p95 < 500 ms; uncached < 5 s hoặc partial | §12; SW087 | approved | TL, QA | Đo thật ở SW087 |
| D053 | Cảnh báo quota | 70 / 85 / 95% | §12; SW082 | approved | DevOps | — |

### Retention và quyền riêng tư

| ID | Chủ đề | Quyết định / giá trị | Nguồn | Trạng thái | Owner | Review-by |
|---|---|---|---|---|---|---|
| D060 | Lịch sử alert | 30 ngày (không hứa lịch sử trước khi bắt đầu thu thập) | ALERT01 | approved | PO | Đồng bộ privacy policy |
| D061 | Feedback ticket | 180 ngày | FEEDBACK01 | approved | PO | Đồng bộ privacy policy |
| D062 | Attachment | 90 ngày; loại EXIF vị trí; scan trước khi đọc | FEEDBACK01, §12 | approved | PO, BE | — |
| D063 | Tọa độ GPS raw | Bản mới nhất / installation tối đa 24 h (chỉ khi phục vụ push), sau đó xóa/ẩn danh; không lưu đường di chuyển; không xin background location | §12, PLACE01 | approved | PO, BE | — |
| D064 | Weather snapshot | Chỉ lưu theo quyền hợp đồng nguồn | §10.3, §12 | conditional | BE, PO | Khi có điều khoản gói |
| D065 | Telemetry | requestId, endpoint, provider, latency, cacheHit, reasonCode; không tọa độ chính xác, không nội dung feedback; không quảng cáo/tracking vị trí | §12 | approved | TL | — |

### Nguồn dữ liệu (cần mua / kiểm chứng)

| ID | Chủ đề | Quyết định / giá trị | Nguồn | Trạng thái | Owner | Review-by |
|---|---|---|---|---|---|---|
| D070 | Weather chính | Open-Meteo customer API (gói thương mại). Free endpoint chỉ dev. | §5.1, §5.2; SW022 | conditional — blocked on purchase | PO, BE | Trước staging có traffic thật |
| D071 | Ngân sách provider | Tính theo active locations × refresh; chỉ prefetch điểm hoạt động | §12; SW026 | open | PO, TL | Sau spike SW022 |
| D072 | AQI | Open-Meteo Air Quality (CAMS model, US AQI); cùng gói thương mại D070 | §5.3 | conditional — blocked on purchase | PO, BE | Cùng D070 |
| D073 | AQI trạm | Chưa chọn nhà cung cấp; station selector ẩn | §5.3; AQ01 | conditional — blocked on purchase | PO | Sau release đầu |
| D074 | Danh mục địa điểm | GeoNames cities500 + admin1/admin2/countryInfo/alternateNamesV2 (CC BY 4.0, ghi công) | §6.1; SW017 | approved | DATA | — |
| D075 | Danh mục Việt Nam | Bảng `vn_admin_units` từ NQ 202/2025/QH15 và QĐ 19/2025/QĐ-TTg; DATA kiểm tra từng mã với PDF gốc | §6.2; SW018 | approved (dữ liệu chưa import) | DATA, PO | Trước M1 |
| D076 | Geocoding online | Open-Meteo Geocoding bổ sung (đang dùng làm nguồn tìm kiếm chính ở bản dev) | §6.3 | conditional — kiểm quyền sử dụng thương mại | BE, PO | Cùng D070 |
| D077 | Timezone theo GPS | timezone-boundary-builder (ODbL) import PostGIS, point-in-polygon | §6.3; SW020 | approved (chưa import) | DATA | — |
| D078 | Thiên văn bổ sung | WeatherAPI Astronomy (độ sáng trăng) — tùy chọn | §5.4 | conditional | PO | Chỉ khi suncalc không đủ |
| D079 | Official alerts | WeatherAPI alerts ở vùng xác minh được; vùng ưu tiên chưa chốt | §5.4; SW059 | conditional — blocked on purchase + coverage | PO, BE | Vùng ưu tiên: open |
| D080 | Lớp bản đồ dự báo | OpenWeather Maps 2.0 (TA2, WND, PR0) qua tile gateway | §5.5; SW055–SW056 | conditional — blocked on purchase + quyền proxy/cache | PO, BE | — |
| D081 | Radar | RainViewer thương mại hoặc đối tác radar; free API không dùng | §5.5; SW058 | conditional — blocked on purchase | PO | Có thể Deferred khỏi release đầu |
| D082 | Bản đồ nền | MapTiler Cloud, public restricted key theo môi trường, client gọi trực tiếp (không proxy) | §5.5; SW055 | conditional — blocked on purchase | PO, MOB | — |
| D083 | Cực quang | NOAA SWPC Kp + OVATION, worker tải toàn cục rồi cache | §5.6; SW053 | approved (public feed) | BE | Kiểm độ tươi feed |
| D084 | Push | FCM (Android) + APNs (iOS), credential theo môi trường | SW063 | conditional — cần tài khoản Firebase/Apple Developer | DevOps, MOB | Trước M3 |
| D085 | Store accounts | Google Play Console, Apple Developer Program | SW092–SW095 | open | PO | Trước M5 |

## 2. Capability matrix

Trạng thái trong bản build hiện tại (2026-10-17, chưa commit):

| Tính năng | Nguồn | Trạng thái build này | Điều kiện để bật ngoài fixture/dev |
|---|---|---|---|
| Weather forecast (current/hourly/daily/metrics) | Open-Meteo | Chạy với **free endpoint** (dev) và `PROVIDER_MODE=fixture` | Mua gói thương mại (D070), cấu hình `OPEN_METEO_*` customer host + key trong secret manager, spike SW022 tại bộ điểm QA |
| AQI mô hình | Open-Meteo Air Quality (CAMS) | Chạy free endpoint; không trạm; AQI alerts "chưa hỗ trợ" | Như D070/D072; ghi attribution CAMS |
| AQI trạm | Chưa chọn | Ẩn | Hợp đồng nguồn trạm + adapter có stationId/measurementAt (D073) |
| Geocoding / catalog | Open-Meteo Geocoding (GeoNames dataset) qua server; ID UUIDv5; kho JSON dev | Chạy; chưa có catalog Postgres, chưa có dữ liệu VN chính thức | Import GeoNames + VN vào PostGIS (SW017–SW018, đang làm), xác nhận quyền dùng Geocoding thương mại |
| Resolve GPS + timezone | Server | Chạy (bản dev) | Polygon timezone-boundary-builder trong PostGIS (SW020) |
| Astronomy | suncalc (tính toán) | Chạy | So sai số với nguồn tham chiếu nhiều vĩ độ (SW054) |
| Aurora Kp | NOAA SWPC | Chạy (Kp forecast) | Worker cache toàn cục (SW053) |
| Aurora OVATION map | NOAA SWPC | Chưa có | Worker + bản đồ (SW053) |
| Aurora push | — | Off | Logic vùng quan sát được kiểm thử + push (D042) |
| Official alerts | WeatherAPI (đề xuất) | `unsupported` / `COVERAGE_NOT_VERIFIED` | Gói WeatherAPI + xác minh coverage theo vùng (D079), ingest SW059 |
| Forecast map layers | OpenWeather Maps 2.0 | `unsupported` / `MAP_PROVIDER_NOT_CONFIGURED` | Gói Maps + quyền proxy/cache (D080), manifest + gateway SW056 |
| Radar | RainViewer/đối tác | Không có | Hợp đồng thương mại + test coverage (D081); có thể Deferred |
| Base map | MapTiler Cloud | Không có | Gói + public restricted key theo môi trường (D082) |
| Push notifications | FCM / APNs | "Chưa hỗ trợ" | Tài khoản + credential (D084), installation auth (SW014), scheduler (SW065) |
| OS widgets | Native Android AppWidget / iOS WidgetKit | Chỉ preview trong app | Native extension + device test (SW072–SW075) |
| Feedback text | Weather Server | Chạy, idempotent, kho JSON dev | Postgres + công cụ hỗ trợ nội bộ (SW078) |
| Feedback attachments | Object storage | "Chưa hỗ trợ" | Upload URL ngắn hạn, MIME thật, loại EXIF, scan (SW078) |
| Data sources / attribution | Server `GET /v1/data-sources` | Chạy | Cập nhật khi đổi nguồn |
