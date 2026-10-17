# Backlog status SW001–SW099 (SW004)

- Ngày đánh giá: 2026-10-17. Căn cứ: code trong working tree (chưa commit: `apps/`, `services/`, `packages/`, `infra/`, `.github/`, `docs/`), README, ADR 001, OpenAPI, test hiện có.
- Đánh giá nghiêm: **Done-candidate** chỉ khi có đủ bằng chứng nghiệm thu của TODO. Code có nhưng thiếu bằng chứng thiết bị thật / staging / CI chạy xanh / người duyệt → **Partial**.
- Cập nhật 2026-10-17 (tối): các việc hạ tầng M0–M1 đã có code và test, ghi **Partial** vì còn thiếu bằng chứng staging/CI/thiết bị.
- Ưu tiên theo quy tắc TODO: **P0** = G01–G07, luồng chọn nơi và auth, bảo vệ dữ liệu, CI, hợp đồng; **P1** = màn và nghiệp vụ trong release; **C** = có điều kiện (radar, official alerts theo vùng, AQI trạm, aurora push).
- Chưa có board/issue tracker thật; bảng này là nguồn tạm cho tới khi tạo issue theo mã SW (người thực hiện, ước lượng, sprint do đội gán sau spike nguồn SW022).

Tổng quan nhanh: 0 Done-candidate · phần lớn M0–M2 ở Partial/In progress · M3 trở đi chủ yếu Not started/Blocked.

| Trạng thái | Ý nghĩa |
|---|---|
| Done-candidate | Đủ đầu ra + bằng chứng theo TODO, chờ người duyệt đóng |
| Partial | Có code/tài liệu, thiếu bằng chứng nghiệm thu hoặc thiếu phần |
| In progress | Lead đang làm tại thời điểm đánh giá |
| Not started | Chưa có gì |
| Blocked | Phụ thuộc mua gói/hợp đồng/tài khoản hoặc task chặn chưa xong |

## M0 — G01 Chốt phạm vi và chuẩn bị dự án

| SW | Task | Ưu tiên | Trạng thái | Bằng chứng / còn thiếu |
|---|---|---|---|---|
| SW001 | Chốt nền tảng và công nghệ | P0 | Partial | `docs/adr/001-stack.md` có phiên bản; ADR vẫn ghi "proposed" — cần cập nhật theo chỉ đạo PO, ghi người quyết định, bảng thiết bị/OS tối thiểu |
| SW002 | Khóa phạm vi theo UI | P0 | Partial | `docs/screens.md` có danh mục + change log; thiếu wireframe màn bổ sung được UX duyệt, C3 (arc) còn open |
| SW003 | Chốt quyết định còn mở | P0 | Partial | `docs/decision-log.md` có decision log + capability matrix; còn mục open (D022, D049, D071, D085) |
| SW004 | Lập backlog và mốc | P0 | Partial | File này; chưa có board/issue thật, người, ước lượng, sprint |

## M0 — G02 Tạo repository và project

| SW | Task | Ưu tiên | Trạng thái | Bằng chứng / còn thiếu |
|---|---|---|---|---|
| SW005 | Kho mã và quy tắc làm việc | P0 | Partial | `.gitignore`, `CONTRIBUTING.md`, gitleaks trong CI; worker nằm trong `services/weather-api/src/worker.ts` (cùng codebase, ADR 001). Thiếu CODEOWNERS (cần tên người), branch protection; code chưa commit |
| SW006 | Khởi tạo mobile | P0 | Partial | Android flavor dev/staging/prod (`com.asctechsoft.skyweather[.dev/.staging]`), tên app theo flavor, ký release qua `key.properties`; quyền vị trí foreground Android/iOS. Chưa build Android trên máy dev (thiếu Android SDK); iOS scheme cần macOS |
| SW007 | Khởi tạo API và worker | P0 | Partial | `DATABASE_URL` fail-fast, `/v1/health/live` + `/v1/health/ready` (DB, Redis), requestId; worker `npm run worker` (Kp NOAA 5 phút, prefetch nơi dùng trong 24 h, advisory lock theo job). Chưa chạy trên staging |
| SW008 | Môi trường local tái lập | P0 | Partial | `infra/docker-compose.yml`; không Docker: `npm run db:dev` (PostgreSQL nhúng UTF-8); `npm run migrate`, `import:geonames`. Đã dựng từ DB rỗng trên máy dev. Thiếu seed tối thiểu và lệnh reset |

## M0 — G03 Hạ tầng và tự động hóa

| SW | Task | Ưu tiên | Trạng thái | Bằng chứng / còn thiếu |
|---|---|---|---|---|
| SW009 | Tách môi trường và cấu hình | P0 | Not started | Chưa có dev/staging/prod, secret manager, IaC |
| SW010 | CI cho mọi PR | P0 | Partial | `.github/workflows/ci.yml` (gitleaks, lint, test, build, migrate ×2, npm audit, flutter analyze/test/build web); chưa chạy trên GitHub (code chưa push), chưa có bằng chứng cố ý làm fail |
| SW011 | CD staging và build thử | P0 | Blocked | Cần SW009 |
| SW012 | Backup và rollback có diễn tập | P0 | Blocked | Cần staging (SW009) |

## M1 — G04 Hợp đồng API và nền tảng dữ liệu

| SW | Task | Ưu tiên | Trạng thái | Bằng chứng / còn thiếu |
|---|---|---|---|---|
| SW013 | Schema chuẩn hóa | P0 | Partial | `packages/contracts/openapi.yaml`, `examples/*.json`, `domain/types.ts`; thiếu JSON Schema riêng, Alert/MapFrame đầy đủ, fixture parse cả hai phía cho thiếu/partial |
| SW014 | Lỗi và bảo vệ request | P0 | Partial | Installation token `swi_…` (hash SHA-256, hạn 90 ngày, rotate, revoke, xóa), guard toàn cục, rate limit 429 + Retry-After (Redis INCR hoặc bộ nhớ); test tích hợp 400/401/404/409. Thiếu test 403/429 tự động, app attestation |
| SW015 | Migration cơ sở dữ liệu | P0 | Partial | `migrations/001_init.sql` (đủ bảng §10.3), runner checksum + advisory lock + kiểm tra UTF-8; test chạy từ DB rỗng và chạy lại. Chưa có kiểm thử nâng cấp từ phiên bản trước (chưa có v2) |
| SW016 | Mock server và SDK nội bộ | P0 | Partial | `PROVIDER_MODE=fixture`, fixture provider trong `packages/contracts/fixtures`; mobile client viết tay (`core/api.dart`), chưa sinh từ schema, chưa có contract test báo breaking change |

## M1 — G05 Danh mục địa điểm toàn cầu

| SW | Task | Ưu tiên | Trạng thái | Bằng chứng / còn thiếu |
|---|---|---|---|---|
| SW017 | Import GeoNames có kiểm soát | P0 | Partial | `catalog/geonames.importer.ts` + CLI: tải có retry, checksum, giới hạn zip, validate tọa độ/timezone/trùng, diff, chặn thay đổi >5%, dry-run, lock, đánh dấu lượt bị gián đoạn. Đã import thật cities15000 (34.166 nơi); cities500 cần máy nhiều RAM hơn |
| SW018 | Chuẩn hóa Việt Nam có phiên bản | P0 | Not started | Cần importer SW017 và rà PDF QĐ 19/2025 |
| SW019 | Tìm kiếm đa ngôn ngữ | P0 | Partial | Catalog trước (alias bỏ dấu, prefix + trigram ≥0.5, xếp theo dân số), Open-Meteo Geocoding bổ sung; test Hà Nội/ha noi/Hanoi, London GB≠CA. Thiếu alternateNamesV2 theo ngôn ngữ và query corpus đầy đủ |
| SW020 | Resolve GPS và timezone | P0 | Partial | Timezone theo polygon timezone-boundary-builder (`geo-tz/all`), từ chối điểm có nhiều zone (422), nhãn nơi dân cư gần nhất ≤30 km (`nameApproximate`). Thiếu fixture hai phía ranh giới và chính sách vùng biển |
| SW021 | Đồng bộ và rollback danh mục | P0 | Not started | Cần SW017 |

## M1 — G06 Tích hợp weather và chuẩn hóa

| SW | Task | Ưu tiên | Trạng thái | Bằng chứng / còn thiếu |
|---|---|---|---|---|
| SW022 | Mở tài khoản và thử năng lực nguồn | P0 | Blocked | Chờ mua gói Open-Meteo thương mại (D070); chưa có provider register |
| SW023 | Adapter forecast chính | P0 | Partial | `providers/open-meteo.forecast.ts`, `domain/condition.ts`, `test/adapters.spec.ts`; chạy trên free endpoint, chưa thử customer endpoint |
| SW024 | Bộ tổng hợp và quy tắc chỉ số | P0 | Partial | `domain/rules.ts`, `test/rules.spec.ts` (DST, góc gió…); cần rà oracle độc lập đủ ngày 23/25 giờ cho mọi rule |
| SW025 | Cache và fallback | P0 | Partial | `RedisTtlCache` (khóa SET NX, chờ rồi dùng stale), circuit breaker theo provider (5 lỗi → mở 30 s, 4xx không tính), single-flight; test với ioredis-mock. Chưa chạy Redis thật trên staging |
| SW026 | API weather và kiểm soát chi phí | P0 | Partial | home/summaries/hourly/daily/metrics/refresh có; chưa có dashboard quota, budget alert |

## M1 — G07 Nền tảng mobile và assets

| SW | Task | Ưu tiên | Trạng thái | Bằng chứng / còn thiếu |
|---|---|---|---|---|
| SW027 | Kiến trúc và lưu trạng thái | P0 | Partial | Token installation lưu bằng `flutter_secure_storage`, tự rotate/đăng ký lại khi 401; `core/settings.dart` (versioned local, migration layout), `RequestGeneration` trong `home_controller.dart`; chưa có secure storage cho token (chưa có token) |
| SW028 | Design system theo UI | P0 | Partial | `ui/theme.dart`, `ui/widgets.dart`, `core/format.dart`; chưa có component gallery, kiểm text scale lớn/screen reader |
| SW029 | Bộ icon và nền thời tiết | P0 | Partial | Icon vector `ui/weather_icon.dart`, nền vẽ `sky_scene.dart`; bộ 36 icon + 8 nền PNG chưa có trong repo, chưa có asset manifest/test mapping |
| SW030 | Navigation và deep link | P0 | Partial | `ui/routes.dart` truyền Location; chưa có deep link (push/widget), chưa có route typed cho alertId/widgetInstanceId |

## M2 — G08 Khởi động và quản lý địa điểm

| SW | Task | Ưu tiên | Trạng thái | Bằng chứng / còn thiếu |
|---|---|---|---|---|
| SW031 | Luồng mở app lần đầu | P0 | Partial | `onboarding_screen.dart` (giải thích trước khi xin GPS, không mặc định Hà Nội); thiếu test thiết bị thật (deny/timeout) |
| SW032 | Search và preview địa điểm | P0 | Partial | `search_screen.dart`, `place_preview.dart`; thiếu lịch sử local, test thiết bị |
| SW033 | PLACE01 danh sách và chỉnh sửa | P1 | Partial | `places_screen.dart`, batch summaries; thiếu test repository, policy xóa city đang dùng ở widget |
| SW034 | DEFAULT01 | P1 | Partial | `default_location_screen.dart` (draft/Save/discard); thiếu test fallback |

## M2 — G09 Home và App Drawer

| SW | Task | Ưu tiên | Trạng thái | Bằng chứng / còn thiếu |
|---|---|---|---|---|
| SW035 | HOME01 hero | P1 | Partial | Hero + mini-stat gió/độ ẩm, không card lớn; thiếu visual QA so ảnh, nền PNG |
| SW036 | HOME01 phần cuộn đầy đủ | P1 | Partial | Đủ section, không Sun & Moon; thiếu kiểm màn nhỏ, ma trận card-route có chữ ký QA |
| SW037 | Insights và trạng thái từng khối | P1 | Partial | `_Insights` (reminder, tối đa 3); chưa có official alert, thiếu fixture UI cho từng trạng thái |
| SW038 | DRAWER01 | P1 | Partial | `app_drawer.dart` đủ item; wireframe chưa được UX duyệt |

## M2 — G10 Dự báo theo giờ và nhiều ngày

| SW | Task | Ưu tiên | Trạng thái | Bằng chứng / còn thiếu |
|---|---|---|---|---|
| SW039 | FC01 | P1 | Partial | `hourly_screen.dart` nhận date/metric; thiếu chart fixtures, test DST trùng giờ trên UI |
| SW040 | Chi tiết một giờ | P1 | Partial | Bottom sheet trong `hourly_screen.dart`; thiếu UX duyệt và test |
| SW041 | FC02 horizon thực tế | P1 | Partial | `daily_screen.dart`, server trả horizon thật; thiếu horizon tests phía mobile |
| SW042 | Đồng bộ forecast giữa các màn | P1 | Partial | Snapshot dùng chung ở server (`snapshot.service.ts`); thiếu cross-screen regression |

## M2 — G11 Chỉ số chi tiết phần một

| SW | Task | Ưu tiên | Trạng thái | Bằng chứng / còn thiếu |
|---|---|---|---|---|
| SW043 | WIND01 | P1 | Partial | Màn + rule góc tròn; Beaufort chưa có bảng (D049); thiếu fixtures UI |
| SW044 | RAIN01 | P1 | Partial | Màn + cửa sổ Today/24h/7d; thiếu aggregation tests DST đầy đủ |
| SW045 | HUM01 | P1 | Partial | Màn có; thiếu range tests |
| SW046 | FEEL01 | P1 | Partial | Màn có, delta ×1.8 có test (`format_test.dart`); thiếu test đủ |

## M2 — G12 Chỉ số chi tiết phần hai

| SW | Task | Ưu tiên | Trạng thái | Bằng chứng / còn thiếu |
|---|---|---|---|---|
| SW047 | VIS01 | P1 | Partial | Màn có; thiếu missing data cases |
| SW048 | UV01 | P1 | Partial | Màn có; thiếu boundary tests UI; UV alerts chờ push |
| SW049 | PRES01 | P1 | Partial | Màn có; thiếu trend fixtures |
| SW050 | AQ01 | P1 | Partial | Adapter CAMS + màn, không trạm giả; chạy free endpoint (D072 blocked), chưa có pollutant chart lịch sử |

## M3 — G13 Thiên văn và cực quang

| SW | Task | Ưu tiên | Trạng thái | Bằng chứng / còn thiếu |
|---|---|---|---|---|
| SW051 | ASTRO01 mặt trời | P1 | Partial | `providers/astronomy.ts` (suncalc), `sun_moon_screen.dart`, vào qua Drawer; thiếu test DST/Tromsø so nguồn tham chiếu |
| SW052 | ASTRO01 mặt trăng | P1 | Partial | Moon từ suncalc; upcoming phases cần kiểm; không có ephemeris (không dùng Skyfield) |
| SW053 | NOAA worker và AUR01 | P1 | Partial | `providers/noaa.ts`, `aurora_screen.dart`; gọi NOAA trong API (chưa có worker), OVATION map chưa có |
| SW054 | Kiểm soát phát hành thiên văn/aurora | C | Not started | Cần comparison test, feature flags; aurora push giữ off |

## M3 — G14 Bản đồ thời tiết

| SW | Task | Ưu tiên | Trạng thái | Bằng chứng / còn thiếu |
|---|---|---|---|---|
| SW055 | Chọn nguồn nền và weather layers | P1 | Blocked | Chờ mua OpenWeather Maps + MapTiler (D080, D082) |
| SW056 | Manifest và tile gateway | P1 | Blocked | `GET /v1/maps/manifest` trả unsupported; gateway chưa có |
| SW057 | MAP01 tương tác và timeline | P1 | Blocked | `map_screen.dart` placeholder |
| SW058 | Bật radar | C | Blocked | Chờ hợp đồng radar (D081) |

## M3 — G15 Cảnh báo và nhắc nhở

| SW | Task | Ưu tiên | Trạng thái | Bằng chứng / còn thiếu |
|---|---|---|---|---|
| SW059 | Ingest cảnh báo chính thức | C | Blocked | Chờ nguồn alert + coverage (D079) |
| SW060 | ALERT01 danh sách và chi tiết | P1 | Partial | `alerts_screen.dart` phân biệt unsupported với rỗng; chưa có list/detail thật |
| SW061 | Rule engine nhắc mưa UV AQI | P1 | Partial | Insights reminder phía server; chưa version cấu hình, chưa dedupe cho push |
| SW062 | Giới hạn vùng và thời hạn hữu ích | C | Not started | Cần push + alerts |

## M3 — G16 Push và cài đặt thông báo

| SW | Task | Ưu tiên | Trạng thái | Bằng chứng / còn thiếu |
|---|---|---|---|---|
| SW063 | FCM/APNs và token | P1 | Blocked | Cần tài khoản (D084) và installation auth (SW014) |
| SW064 | NOTI01 cấu hình có revision | P1 | Blocked | `notifications_screen.dart` placeholder; cần preferences API |
| SW065 | Scheduler timezone + quiet hours | P1 | Not started | Cần worker |
| SW066 | Nội dung push và mở đúng màn | P1 | Not started | Cần SW063, deep link SW030 |

## M3 — G17 Settings và cá nhân hóa

| SW | Task | Ưu tiên | Trạng thái | Bằng chứng / còn thiếu |
|---|---|---|---|---|
| SW067 | SET01 ngôn ngữ, chính sách, About | P1 | Partial | Settings đủ hàng, vi/en qua `core/l10n.dart` (hàm `tr`, chưa ARB/plural), About dùng package_info; URL privacy/terms thật chưa có |
| SW068 | UNIT01 | P1 | Partial | Draft/Reset/Save, `format_test.dart` có vector quy đổi; chưa áp cho widget/push |
| SW069 | APPEAR01 | P1 | Partial | Light/Dark/System, weather background, reduce motion; thiếu contrast matrix |
| SW070 | CUSTOM01 | P1 | Partial | Lock 2 khối đầu, migration bỏ `sunMoon`; thiếu layout migration tests |
| SW071 | REFRESH01 | P1 | Partial | Màn + cooldown server; chưa có background task, chưa có Wi-Fi only thực thi trên thiết bị |

## M3 — G18 Widget hệ điều hành

| SW | Task | Ưu tiên | Trạng thái | Bằng chứng / còn thiếu |
|---|---|---|---|---|
| SW072 | Thiết kế widget và cấu hình | P1 | Partial | Preview trong `widgets_screen.dart`; chưa có widgetInstanceId, native bridge contract |
| SW073 | Android widget | P1 | Not started | — |
| SW074 | iOS widget | P1 | Not started | Cần máy macOS + Apple signing |
| SW075 | Đồng bộ và vòng đời widget | P1 | Not started | — |

## M3 — G19 Nguồn dữ liệu và hỗ trợ

| SW | Task | Ưu tiên | Trạng thái | Bằng chứng / còn thiếu |
|---|---|---|---|---|
| SW076 | SOURCE01 attribution và coverage | P1 | Partial | `GET /v1/data-sources`, `data_sources_screen.dart`; thiếu cache offline attribution, attribution inventory |
| SW077 | FEEDBACK01 form và draft | P1 | Partial | Form, validation, diagnostics off, idempotency key; ảnh "chưa hỗ trợ", thiếu local draft tests |
| SW078 | Feedback upload và xử lý server | P1 | Not started | `POST /v1/feedback` lưu JSON; chưa có uploads, object storage, công cụ hỗ trợ, retention job |
| SW079 | RATE01 | P1 | Partial | `rate_dialog.dart` (5 phiên + 7 ngày + 90 ngày); store ID thật và native review flow chưa có |

## M4 — G20 Bảo mật, quyền riêng tư, vận hành

| SW | Task | Ưu tiên | Trạng thái | Bằng chứng / còn thiếu |
|---|---|---|---|---|
| SW080 | Quyền và ranh giới dữ liệu | P0 | Not started | Cần auth (SW014); chưa có data inventory |
| SW081 | Xóa dữ liệu và retention | P0 | Partial | `DELETE /v1/installations/me` (thu hồi token, xóa cascade push/prefs/events, tách feedback), nút xóa dữ liệu ở màn About. Thiếu job retention (feedback 180 ngày, attachment 90 ngày) |
| SW082 | Dashboard và cảnh báo vận hành | P1 | Not started | Cần staging |
| SW083 | Feature flags | P1 | Partial | `GET /v1/config` trả flag/capability; chưa có remote config theo region/appVersion, audit |

## M4 — G21 Kiểm thử tự động

| SW | Task | Ưu tiên | Trạng thái | Bằng chứng / còn thiếu |
|---|---|---|---|---|
| SW084 | Ma trận test từ đặc tả | P1 | Not started | Chưa chuyển QA01–QA28 thành test case |
| SW085 | Test adapter và nghiệp vụ | P1 | Partial | `adapters.spec.ts`, `rules.spec.ts` dùng fixture, không gọi live; chưa có report tái lập, live smoke có budget |
| SW086 | Test UI và E2E | P1 | Not started | Mobile chỉ có `format_test.dart` |
| SW087 | Hiệu năng và độ ổn định | P1 | Not started | — |

## M4 — G22 Tích hợp tổng thể và nghiệm thu

| SW | Task | Ưu tiên | Trạng thái | Bằng chứng / còn thiếu |
|---|---|---|---|---|
| SW088 | Smoke test dọc | P1 | Not started | Cần staging + API thật |
| SW089 | Nghiệm thu UI và nội dung | P1 | Not started | — |
| SW090 | Đóng lỗi và kiểm tra nâng cấp | P1 | Not started | — |
| SW091 | Chốt gói hoàn thành | P1 | Not started | — |

## M5 — G23 Phát hành store

| SW | Task | Ưu tiên | Trạng thái | Bằng chứng / còn thiếu |
|---|---|---|---|---|
| SW092 | Hồ sơ phát hành | P1 | Not started | Cần tài khoản store (D085) |
| SW093 | Build ký và kiểm tra release | P1 | Blocked | Cần signing accounts |
| SW094 | Test phân phối trước công khai | P1 | Not started | — |
| SW095 | Nộp duyệt và triển khai từng đợt | P1 | Not started | — |

## M6 — G24 Sau phát hành và bàn giao

| SW | Task | Ưu tiên | Trạng thái | Bằng chứng / còn thiếu |
|---|---|---|---|---|
| SW096 | Theo dõi tuần đầu | P1 | Not started | — |
| SW097 | Bàn giao mã và tài khoản | P1 | Not started | — |
| SW098 | Lịch bảo trì định kỳ | P1 | Not started | — |
| SW099 | Đóng dự án | P1 | Not started | — |

## Chặn lớn hiện tại

1. Mua gói Open-Meteo thương mại (D070) — chặn SW022 và việc coi weather/AQI là sẵn sàng production.
2. Staging (SW009) — chặn CD, backup, smoke, dashboard, mọi bằng chứng "Done" cần staging.
3. Installation auth (SW014, đang làm) — chặn push, feedback upload, data deletion.
4. Hợp đồng Maps/MapTiler/radar/alerts — chặn G14 và SW059.
5. Tài khoản Firebase/Apple Developer/store — chặn G16, SW074, G23.
