# Danh mục màn hình và change log (SW002)

- Nguồn: Đặc tả SkyWeather 1.0 §3, §7, §8, §16; backlog SW002, mục "Đối chiếu màn hình với nhóm triển khai".
- Trạng thái tài liệu: approved-by-PO-instruction 2026-10-17 (PO chỉ đạo "làm theo các quyết định trong file TODO").
- Ảnh tham chiếu mới: `scream_new/` (home, hourly, 10 ngày, map, air, setting, unit, sun/moon, app drawer). Các màn không có ảnh trong `scream_new/` dùng ảnh trong đặc tả (§16) hoặc wireframe cần UX duyệt.
- Số liệu, địa điểm, ngày và tên thiết bị trong ảnh chỉ là minh họa.

## Quy ước trạng thái

| Trạng thái | Ý nghĩa |
|---|---|
| implemented | Có màn Flutter gọi API thật (hoặc local settings), có điểm vào/ra. Chưa đồng nghĩa SW đã Done: còn thiếu bằng chứng thiết bị/staging, xem `docs/backlog-status.md`. |
| placeholder-unsupported | Có màn/entry nhưng hiển thị trạng thái "chưa hỗ trợ" có lý do, không có switch giả (thiếu nguồn hoặc hạ tầng). |
| not started | Chưa có code. |

Đường dẫn file tính từ `apps/mobile/lib/`. Route trong `ui/routes.dart` (class `Routes`), một số màn Settings mở bằng `pushPage` trong `features/settings/settings_screen.dart`.

## 1. 27 nhóm màn theo đặc tả

| Mã | Màn hình | Điểm vào | Điểm ra / Back | File Flutter | Trạng thái |
|---|---|---|---|---|---|
| HOME01 | Trang chủ | Khởi động khi có default hợp lệ; sau onboarding; chọn nơi từ PLACE01/Search | Drawer, dropdown địa điểm, nút +, từng card chỉ số/hourly/daily/AQI/map/aurora/widgets, insights, sunrise arc → ASTRO01, footer nguồn → SOURCE01 | `features/home/home_screen.dart`, `home_controller.dart`, `sky_scene.dart` | implemented |
| FC01 | Dự báo theo giờ | Home hourly card, hàng ngày trong FC02 / Home daily preview (kèm `date`), Drawer | Back giữ ngày + tab; chạm điểm/hàng → hour detail sheet | `features/forecast/hourly_screen.dart` | implemented |
| FC02 | Dự báo 10 ngày (horizon thật) | Home "View forecast", Drawer | Chạm hàng → FC01 đúng `date`; Back về Home | `features/forecast/daily_screen.dart` | implemented |
| ALERT01 | Cảnh báo thời tiết | Drawer; (sau này: insights official, push) | Back; preferences → NOTI01 | `features/alerts/alerts_screen.dart` | placeholder-unsupported (`COVERAGE_NOT_VERIFIED`) |
| MAP01 | Bản đồ thời tiết | Home map card, Drawer | Back | `features/map/map_screen.dart` | placeholder-unsupported (`MAP_PROVIDER_NOT_CONFIGURED`) |
| WIND01 | Gió | Home card gió, mini-stat gió ở hero | Back về Home cùng vị trí cuộn | `features/metrics/wind_screen.dart` (+ `charts_a.dart`/`charts_b.dart`) | implemented |
| RAIN01 | Lượng mưa | Home card mưa, insight mưa | Back | `features/metrics/rain_screen.dart` | implemented (toggle Rain alerts: chưa hỗ trợ) |
| HUM01 | Độ ẩm | Home card độ ẩm, mini-stat độ ẩm ở hero | Back | `features/metrics/humidity_screen.dart` | implemented |
| AQ01 | Chất lượng không khí | Home AQI card, insight AQI, Drawer | Back; chạm chất ô nhiễm → pollutant detail | `features/air/air_quality_screen.dart` | implemented (model CAMS, không trạm; AQI alerts chưa hỗ trợ) |
| VIS01 | Tầm nhìn | Home card tầm nhìn | Back | `features/metrics/visibility_screen.dart` | implemented |
| UV01 | Chỉ số UV | Home card UV, insight UV | Back | `features/metrics/uv_screen.dart` | implemented (UV alerts chưa hỗ trợ) |
| PRES01 | Áp suất | Home card áp suất | Back | `features/metrics/pressure_screen.dart` | implemented |
| FEEL01 | Nhiệt độ cảm nhận | Home card cảm nhận | Back | `features/metrics/feels_like_screen.dart` | implemented |
| ASTRO01 | Mặt trời và mặt trăng | **Drawer** (đường vào chính); sunrise arc trong hero Home (tạm giữ, xem change log C3) | Back | `features/astro/sun_moon_screen.dart` | implemented (thiên văn tính toán suncalc) |
| AUR01 | Cực quang | Home aurora card (mặc định ẩn), Drawer | Back; Explore another location → Search | `features/aurora/aurora_screen.dart` | implemented (Kp NOAA; OVATION map và aurora push chưa có) |
| PLACE01 | Quản lý địa điểm | Drawer "Manage places", header Home | Search/Add → SEARCH; chạm hàng → Home; star = default | `features/places/places_screen.dart` | implemented |
| SET01 | Cài đặt | Drawer | Mỗi hàng mở màn con; Back về Home | `features/settings/settings_screen.dart` | implemented (hàng Notifications ghi "Chưa hỗ trợ") |
| UNIT01 | Đơn vị | SET01 | Save/Reset/Back có discard | `features/settings/units_screen.dart` | implemented |
| APPEAR01 | Giao diện | SET01 | Save/Back có discard | `features/settings/appearance_screen.dart` | implemented |
| NOTI01 | Thông báo | SET01; (sau này: toggle ở UV01/AQ01/RAIN01, ALERT01) | Back | `features/settings/notifications_screen.dart` | placeholder-unsupported (chưa có push) |
| DEFAULT01 | Vị trí mặc định | SET01 | Search or add → PLACE01/Search; Save/Back có discard | `features/settings/default_location_screen.dart` | implemented |
| CUSTOM01 | Tùy chỉnh Home | SET01, Drawer, nút trên Home | Save/Reset/Back có discard | `features/settings/customize_home_screen.dart` (registry `HomeLayout` trong `core/settings.dart`) | implemented |
| WIDGET01 | Widget (preview) | SET01, Drawer, Home widgets card | Back | `features/settings/widgets_screen.dart` | placeholder-unsupported (preview có; widget OS chưa có native extension) |
| REFRESH01 | Làm mới | SET01 | Save/Back | `features/settings/refresh_screen.dart` | implemented (background refresh phụ thuộc OS, chưa có task nền) |
| SOURCE01 | Nguồn dữ liệu | SET01, Drawer, footer Home | Back | `features/settings/data_sources_screen.dart` | implemented |
| FEEDBACK01 | Góp ý | SET01, RATE01 "Send feedback" | Gửi → ticketId; Back giữ draft | `features/settings/feedback_screen.dart` | implemented (ảnh đính kèm: placeholder-unsupported) |
| RATE01 | Mời đánh giá | SET01 "Rate app"; auto prompt từ Home (5 phiên + 7 ngày, cooldown 90 ngày) | Close/Not now/Rate/Send feedback | `features/settings/rate_dialog.dart` | implemented (link store cần store ID thật) |

## 2. Màn và luồng bổ sung

| Mã | Màn / luồng | Điểm vào | Điểm ra / Back | File Flutter | Trạng thái |
|---|---|---|---|---|---|
| DRAWER01 | App Drawer | Nút menu trên Home | Manage places, Hourly, 10-day, Map, Alerts, Air quality, Sun & moon, Aurora, Customize Home, Widgets, Settings, Data & attribution; đóng bằng back/overlay/swipe | `features/home/app_drawer.dart` | implemented (wireframe chờ UX duyệt) |
| ONBOARD01 | Lần đầu mở app (GPS hoặc tìm city) | Khởi động khi chưa có địa điểm hợp lệ | GPS (giải thích trước khi xin quyền) → Home; Search → Home | `features/home/onboarding_screen.dart` | implemented |
| SEARCH01 | Tìm địa điểm | PLACE01 Add/Search, nút + Home, onboarding, DEFAULT01, AUR01 Explore | Chọn kết quả → place preview; Back | `features/places/search_screen.dart` | implemented |
| PREVIEW01 | Preview thời tiết địa điểm | Chọn kết quả ở SEARCH01 | Add (lưu, không tạo trùng) / mở Home / đóng sheet | `features/places/place_preview.dart` (bottom sheet) | implemented |
| HOUR01 | Chi tiết một giờ | Chạm điểm biểu đồ hoặc hàng trong FC01 | Đóng sheet → giữ ngày, tab | `features/forecast/hourly_screen.dart` (modal bottom sheet) | implemented |
| LANG01 | Chọn ngôn ngữ (System / vi / en) | SET01 | Chọn → áp dụng ngay, Back | `features/settings/language_screen.dart` | implemented |
| ALERT02 | Chi tiết cảnh báo | ALERT01 "View alert", push | Back về ALERT01 | — | not started (chờ nguồn alert có quyền) |
| POLL01 | Chi tiết chất ô nhiễm / giải thích US AQI | Chạm AQI/chất ô nhiễm ở AQ01 | Đóng sheet | `features/air/air_quality_screen.dart` (bottom sheet giải thích) | implemented một phần: có giải thích, chưa có biểu đồ lịch sử từng chất |
| WIDGET02 | Cấu hình từng widget (city/GPS, theme, nội dung) | Widget OS, WIDGET01 Customize | Save | — | not started (cần native widget SW072–SW074) |
| ABOUT01 | About | SET01 | Back | `features/settings/about_screen.dart` | implemented (version từ build qua package_info_plus) |
| LEGAL01 | Privacy policy / Terms | SET01 | Mở URL HTTPS từ `GET /v1/config` hoặc thông báo lỗi | `openLegal` trong `features/settings/settings_screen.dart` | implemented (URL thật chưa có) |

## 3. Change log phạm vi UI

| # | Ngày | Thay đổi | Lý do / nguồn | Ảnh hưởng | Trạng thái |
|---|---|---|---|---|---|
| C1 | 2026-10-17 | Current weather và Weather insights luôn khóa ở đầu Home, không kéo/tắt được trong CUSTOM01. | Đặc tả CUSTOM01, HOME01; SW070 | `HomeLayout.allSections` không chứa 2 khối này | approved-by-PO-instruction |
| C2 | 2026-10-17 | Bỏ khối Sun & Moon khỏi phần cuộn Home và khỏi registry Customize Home; migration layout cũ xóa ID `sunMoon`, giữ thứ tự còn lại. | Yêu cầu PO trong TODO (SW002, SW036, SW070) | `HomeLayout.fromJson` lọc ID không còn | approved-by-PO-instruction |
| C3 | 2026-10-17 | ASTRO01 vẫn trong scope, đường vào chính qua Drawer. Sunrise arc nhỏ trong hero Home **được giữ tạm** vì ảnh UI mới nhất (`scream_new/sc_home_*.png`) còn hiển thị; arc mở ASTRO01. | SW051 nói "không phụ thuộc Home arc đã bỏ" nhưng ảnh mới vẫn có arc | ASTRO01 không phụ thuộc arc; nếu UX xác nhận bỏ arc thì xóa `_SunArc` mà không mất đường vào | **open — chờ UX xác nhận** |
| C4 | 2026-10-17 | Bỏ card lớn bên phải hero; gió và độ ẩm hiển thị nhỏ trực tiếp trên nền (mini-stat), chạm mở WIND01/HUM01. | Đặc tả HOME01, §16; SW035 | `_MiniStat` trong `home_screen.dart` | approved (vị trí cuối cùng chờ UX duyệt) |
| C5 | 2026-10-17 | Home phải cuộn đủ: hourly, 10 ngày, AQI, các chỉ số, map, aurora, widgets theo capability. | TODO đầu file, SW036 | — | approved-by-PO-instruction |
| C6 | 2026-10-17 | AQ01: "Nearest station / Choose station" chỉ bật khi có adapter trạm thật (stationId, vị trí, khoảng cách, measurementAt). Với CAMS ghi "dữ liệu theo mô hình". | Đặc tả AQ01, §16 | Bản này không có station selector | approved; nguồn trạm: conditional |
| C7 | 2026-10-17 | MAP01 timeline lấy danh sách frame từ `GET /v1/maps/manifest`, không vẽ cố định 9 AM/Now/10 AM/11 AM như ảnh. Mưa phải ghi "Radar quan trắc" hoặc "Dự báo mưa". | Đặc tả MAP01, §16; SW057 | MAP01 hiện unsupported cho tới khi có nguồn map | approved; nguồn: conditional |
| C8 | 2026-10-17 | RAIN01: đổi "No rain recorded" thành "Ước tính chưa có mưa" với dữ liệu mô hình; bỏ "If it rains" nếu nguồn không có lượng mưa có điều kiện. | Đặc tả RAIN01 | — | approved |
| C9 | 2026-10-17 | RATE01: không dùng dãy sao tương tác để phân luồng; nút đánh giá trung lập, Send feedback cho mọi người. | Đặc tả RATE01; SW079 | `rate_dialog.dart` | approved |
| C10 | 2026-10-17 | NOTI01: critical alerts không phải switch vượt quyền OS; chỉ giải thích tuân thủ cài đặt thiết bị. | Đặc tả NOTI01, §16 | — | approved |
| C11 | 2026-10-17 | Màn chưa có nguồn/hạ tầng (ALERT01, MAP01, NOTI01, widget OS, ảnh feedback) hiển thị "chưa hỗ trợ" kèm lý do, không có switch giả. | Đặc tả §14 DoD; SW083 | `UnsupportedView` | approved |

## 4. Việc còn mở để SW002 đạt nghiệm thu

- Mỗi màn bổ sung (DRAWER01, ONBOARD01, SEARCH01, PREVIEW01, HOUR01, LANG01, ALERT02, POLL01, WIDGET02, ABOUT01) cần wireframe/ảnh được UX duyệt và ghi người duyệt.
- C3 (sunrise arc trong hero) cần UX xác nhận.
- QA đi lại toàn bộ sơ đồ điều hướng để xác nhận không còn luồng trỏ vào khối Sun & Moon trên Home.
