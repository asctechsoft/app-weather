# SkyWeather (app-weather)

Ứng dụng thời tiết toàn cầu: app Flutter (`apps/mobile`) + Weather Server NestJS (`services/weather-api`) + hợp đồng (`packages/contracts`).

## Lệnh
- Server: `cd services/weather-api && npm run build && npm start` (port 8080), `npm test` (vitest, gồm test tích hợp trên PostgreSQL nhúng), `npm run lint` (tsc --noEmit).
- DB: `DATABASE_URL` bắt buộc. Không có Docker thì dùng `npm run db:dev` (PostgreSQL nhúng, cổng 54329); tiếp theo `npm run migrate`, `npm run import:geonames -- --dataset cities15000`. Worker chạy bằng `npm run worker`.
- Migration là file SQL trong `services/weather-api/migrations`, chỉ thêm file mới, không sửa file đã chạy (có checksum). DB phải là UTF-8.
- Mọi route `/v1` cần installation token (`@Public()` cho ngoại lệ). Timezone theo tọa độ dùng `geo-tz/all`, không dùng `geo-tz`.
- Mobile: `cd apps/mobile && flutter analyze && flutter test`; chạy `flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8080`.
- Máy dev có proxy hệ thống: gọi server local bằng `curl --noproxy '*'`.
- Máy dev ít RAM (8 GB): tránh chạy song song nhiều tiến trình `flutter`/`dart`.
- `vm_service` được pin 15.3.0 trong `dependency_overrides` vì bản 15.4.0 không giải nén được trên máy dev.

## Cấu trúc
- `SkyWeather_Dac_ta_nghiep_vu_va_API.docx`: đặc tả nghiệp vụ + API v1.0 (27 nhóm màn hình, Weather Server, hợp đồng dữ liệu). Nguồn sự thật về nghiệp vụ.
- `SkyWeather_ToDoList_Dev_Tu_Project_Den_Phat_Hanh.docx`: backlog 99 task (SW001..SW099) trong 24 nhóm G01..G24, mốc M0..M6.
- `scream_new/`: ảnh UI mới (home, hourly, 10 ngày, map, air, setting, unit, sun/moon, app drawer).

## Kiến trúc đã chốt trong đặc tả
- Mobile chỉ gọi Weather Server nội bộ; API key nhà cung cấp chỉ nằm ở server, mobile không phụ thuộc JSON thô của provider.
- Nguồn đề xuất: Open-Meteo (thời tiết, AQI mô hình), GeoNames (địa điểm), WeatherAPI (thiên văn, cảnh báo), OpenWeather Maps (lớp bản đồ), NOAA SWPC (cực quang). Đây là đề xuất, chưa phải hợp đồng đã mua.
- Không bắt buộc đăng nhập; địa điểm và settings lưu trên máy; server giữ installation có token cho push.

## Quy tắc nghiệp vụ cần tuân thủ
- Tọa độ WGS84; giờ hiển thị theo IANA timezone của nơi đang xem; địa điểm dùng ID nội bộ ổn định.
- Giá trị thiếu là `null`, hiển thị "-" kèm lý do, không thay bằng 0.
- Mỗi khối có trạng thái: loading, ready, empty, unsupported, stale, error; một khối lỗi không làm trắng Home.
- Mỗi section ghi nguồn, loại (model/observation) và thời điểm dữ liệu; không dùng `fetchedAt` giả làm thời điểm dự báo.
- Không biến dự báo thành cảnh báo chính thức; không ghép dữ liệu hai provider mà không ghi nguồn.
- Số liệu Hà Nội, ngày, tên thiết bị trong ảnh chỉ là minh họa, không hard-code.
- Ngôn ngữ mặc định theo thiết bị, ra mắt vi + en.

## Làm việc với repo
- Tài liệu và trao đổi bằng tiếng Việt; tên code, biến, commit message bằng tiếng Anh.
- Task đặt theo mã SW (vd SW035); nhắc mã task trong commit/PR.
- Đừng commit secret/API key. Không sửa file `.docx` gốc nếu chưa được yêu cầu.
- Nhánh chính: `main`, remote `https://github.com/asctechsoft/app-weather.git`.
- Màn mới dùng `DetailScaffold` + `AsyncLoader` + `Fmt` (mọi quy đổi đơn vị/giờ) + `tr(context, en, vi)`; null hiển thị "-".
- Tính năng chưa có nguồn hiển thị `UnsupportedView`, không đặt switch giả.
