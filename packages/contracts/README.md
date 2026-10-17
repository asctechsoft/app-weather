# SkyWeather contracts

Hợp đồng dữ liệu giữa mobile và Weather Server (schema `1.0`, đặc tả mục 9–10).

- `openapi.yaml` — danh sách route `/v1/...`, tham số và mã lỗi.
- `examples/` — response thật lấy từ server dev (Hà Nội, Open-Meteo free endpoint, ngày 2026-10-17). Chỉ để tham khảo cấu trúc; số liệu không phải dữ liệu chuẩn.
- `fixtures/` — payload gốc của nhà cung cấp dùng cho contract test của server (`PROVIDER_MODE=fixture`). Đã lưu theo giấy phép CC BY 4.0 (Open-Meteo) và public domain (NOAA). Không chứa key.

Quy tắc chung: đơn vị canonical °C, m/s, mm, hPa, m, %, độ, μg/m³; mọi instant là UTC (`...Z`); `localDate`/`localTime` theo IANA timezone của địa điểm; giá trị thiếu là `null`; mỗi section có `status` (`ready|empty|unsupported|stale|error`), `reasonCode` và `source`.
