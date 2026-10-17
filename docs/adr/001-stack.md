# ADR 001 — Nền tảng và công nghệ (SW001)

- Trạng thái: **approved-by-PO-instruction 2026-10-17** — PO yêu cầu "làm theo quyết định trong file TODO", nên stack tham khảo của SW001 được dùng làm quyết định làm việc. Bảng thiết bị hỗ trợ (phiên bản OS tối thiểu theo SDK thực dùng) vẫn cần TL bổ sung trước M5.
- Ngày: 2026-10-17

## Quyết định

| Thành phần | Lựa chọn | Phiên bản khóa |
|---|---|---|
| Mobile | Flutter cho Android + iOS (web/Windows chỉ để dev/kiểm thử) | Flutter 3.38.9 / Dart 3.10.8 |
| Weather Server | NestJS, TypeScript, Node ≥ 20 | @nestjs/* 10.4.15, TypeScript 5.6.3 |
| Worker | Cùng codebase với API, tiến trình/container riêng (`npm run worker`) | — |
| CSDL | PostgreSQL ≥ 16 (image `postgis/postgis:16-3.4` trong compose) | pg 8.13.1 |
| Cache, khóa, rate limit | Redis 7.2 (`REDIS_URL`); thiếu Redis thì dùng bộ nhớ trong tiến trình, chỉ cho dev | ioredis 5.4.1 |
| Object storage | S3-compatible (MinIO local) cho đính kèm feedback — chưa nối code | — |
| Timezone theo tọa độ | timezone-boundary-builder qua `geo-tz/all` (ODbL) | geo-tz 8.1.2 |
| Danh mục địa điểm | GeoNames dump (CC BY 4.0), import có kiểm soát | cities500 (prod), cities15000 (máy dev ít RAM) |
| Thiên văn | suncalc (thuật toán cố định, có version) | 1.9.0 |
| Test server | Vitest + SWC (giữ decorator metadata cho NestJS) + PostgreSQL nhúng | vitest 2.1.8 |

## Ghi chú triển khai

- **Không phụ thuộc PostGIS** ở lát cắt hiện tại: tìm nơi gần nhất dùng lọc bounding box trên `(latitude, longitude)` + `earthdistance` để sắp xếp. Timezone dùng polygon từ `geo-tz`. Không dùng index biểu thức `ll_to_earth()` vì PostgreSQL 17 build index với `search_path` hạn chế, không thấy được kiểu `earth`.
- **Bộ `geo-tz` mặc định gộp các zone trùng nhau từ 1970** (Hà Nội thành `Asia/Jakarta`), nên phải dùng `geo-tz/all`.
- **Database phải là UTF-8**. Migration từ chối chạy nếu không phải UTF-8: trên Windows `initdb` mặc định ra WIN1252.
- **Máy dev không có Docker** dùng `npm run db:dev` (PostgreSQL nhúng, cổng 54329).
- **Xác thực**: installation token do server cấp (`swi_…`), chỉ lưu hash SHA-256, hạn 90 ngày, làm mới được, thu hồi được. Trên mobile, token nằm trong secure storage.

## Phương án đã cân nhắc

- React Native: không chọn vì Flutter đã có trên máy dev và có plugin cho widget/push.
- Server Python (FastAPI + Astral/Skyfield): hợp với thiên văn hơn nhưng thêm một stack. Có thể tách microservice astronomy nếu sai số suncalc không đạt (SW054).
- PostGIS cho tìm nơi gần nhất và timezone: sẽ bổ sung nếu cần ranh giới hành chính dạng polygon (SW018, SW020 mở rộng).
