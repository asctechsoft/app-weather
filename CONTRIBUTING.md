# Đóng góp vào SkyWeather (SW005)

Tài liệu và trao đổi bằng tiếng Việt; tên code, biến, commit message, tên nhánh bằng tiếng Anh. Mọi thay đổi gắn với một mã task SW (xem `docs/backlog-status.md`).

## Tài liệu cần đọc trước

- `SkyWeather_Dac_ta_nghiep_vu_va_API.docx` — nguồn sự thật nghiệp vụ (không sửa file `.docx` gốc nếu chưa được yêu cầu).
- `SkyWeather_ToDoList_Dev_Tu_Project_Den_Phat_Hanh.docx` — backlog SW001..SW099.
- `docs/screens.md` (màn hình, change log), `docs/decision-log.md` (quyết định, capability), `docs/adr/`.
- `packages/contracts/openapi.yaml` — hợp đồng API giữa mobile và Weather Server.

## Nhánh

- Nhánh chính: `main` (được bảo vệ, chỉ merge qua PR).
- Đặt tên: `feature/SWxxx-short-name` (vd `feature/SW035-home-hero`). Sửa lỗi: `fix/SWxxx-short-name`. Việc không gắn task (hiếm): `chore/short-name`.
- Một nhánh nên chỉ chứa một task SW hoặc một nhóm nhỏ liên quan chặt.

## Commit message

- Tiếng Anh, thể mệnh lệnh, dòng đầu ≤ 72 ký tự, có mã SW:
  ```
  SW044 Add 24-hour sliding window to rain metrics

  Explain why if not obvious.
  ```
- Không gộp thay đổi không liên quan vào cùng commit.

## Pull request

- Tiêu đề có mã SW; mô tả gồm: thay đổi gì, vì sao, cách kiểm tra, ảnh chụp màn (với UI), ảnh hưởng tới contract/migration.
- Điều kiện merge:
  - CI xanh (secret scan, lint/type check, test, build, migrate, flutter analyze/test). Không bỏ qua job thất bại để merge.
  - Ít nhất một review được duyệt (TL hoặc người sở hữu vùng code). Thay đổi `openapi.yaml` cần cả BE và MOB review.
  - Đổi contract phải cập nhật `packages/contracts` (OpenAPI + examples) trong cùng PR.
- Task chỉ chuyển Done khi có bằng chứng theo tiêu chí nghiệm thu của TODO (test, build, ảnh thiết bị, link staging); UI đẹp hoặc HTTP 200 riêng lẻ chưa đủ.

## Không được đưa vào git

- Secret, API key, token, `.env` (chỉ commit `.env.example` với placeholder), chứng chỉ/keystore ký (`*.jks`, `*.p12`, `*.pem`, `key.properties`).
- Dump DB, dữ liệu import thô (GeoNames tải về, `data/`, `data-*/`), log có dữ liệu thật.
- Tọa độ GPS thật của người dùng, nội dung feedback/ảnh đính kèm thật, push token.
- Response provider chưa khử key. Fixture chỉ lưu khi được phép theo điều khoản nguồn và đã xóa `apikey`/`key`/`appid`.

Nếu lỡ commit secret: báo TL ngay, xoay vòng (rotate) key — xóa khỏi lịch sử git không đủ.

## Chạy local

Yêu cầu: Node ≥ 20 (CI dùng 22), Flutter 3.38.x (Dart 3.10). Hạ tầng local (PostGIS, Redis, MinIO) đang được bổ sung:

```bash
docker compose -f infra/docker-compose.yml up -d
```

Thông tin đăng nhập trong compose chỉ dùng cho local.

### Weather Server

```bash
cd services/weather-api
npm ci
npm run build
npm start                 # http://127.0.0.1:8080/v1/health
npm test                  # vitest: rule, DST, adapter contract, cache
npm run lint              # type check
```

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
# Android emulator mặc định trỏ http://10.0.2.2:8080
```

Nếu máy dùng proxy hệ thống, gọi server local bằng `curl --noproxy '*'`. Không đưa provider secret vào `--dart-define` hay resource mobile; mobile chỉ biết `API_BASE_URL`, `APP_ENV` và (sau này) public map token đã hạn chế.

## Fixture mode

- `PROVIDER_MODE=fixture` làm server đọc response mẫu trong `packages/contracts/fixtures` thay vì gọi provider. Dùng cho dev UI, CI và test; không bao giờ là mặc định của production.
- Ví dụ response của từng route nằm ở `packages/contracts/examples` — giữ đồng bộ với `openapi.yaml`.
- Thêm fixture mới cho trường hợp thiếu field, code lạ, partial, unsupported, stale, lỗi 429… thay vì sửa fixture cũ cho vừa test.

## Kỳ vọng về test

- Unit test **không gọi provider live hay endpoint trả phí**. Smoke test live (nếu có) chạy riêng, có ngân sách và không nằm trong `npm test`.
- Rule và phép tổng hợp (min/max, tổng mưa theo cửa sổ, gust max, delta áp suất, UV window, quy đổi đơn vị) kiểm bằng **oracle độc lập**: giá trị kỳ vọng tính tay hoặc từ vector cố định, không chép lại công thức của implementation.
- Bắt buộc có case: ngày DST 23/25 giờ, `null` khác `0`, code lạ → `UNKNOWN`, vùng cực không có sunrise, giờ địa phương theo IANA timezone (không theo timezone máy).
- Test không phụ thuộc thời tiết hôm nay hay đồng hồ hệ thống: cố định thời điểm và dữ liệu.
- Lỗi được sửa phải kèm regression test tái hiện đúng lỗi.

## Quy tắc nghiệp vụ hay bị vi phạm

- Giá trị thiếu là `null`, hiển thị "-" kèm lý do; không thay bằng 0.
- Mỗi section ghi nguồn, loại (model/observation) và thời điểm dữ liệu; không dùng `fetchedAt` làm thời điểm dự báo.
- Không biến dự báo thành cảnh báo chính thức; không trộn dữ liệu hai provider mà không ghi nguồn.
- Tính năng chưa có nguồn/quyền hiển thị "chưa hỗ trợ" kèm lý do, không có switch giả.
- Số liệu Hà Nội, ngày, tên thiết bị trong ảnh UI chỉ là minh họa, không hard-code.
