# SkyWeather (app-weather)

Ứng dụng thời tiết toàn cầu. Repo hiện mới chứa tài liệu và ảnh UI tham chiếu, **chưa có source code app/server**.

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
- Khi đã có code, cập nhật mục này với lệnh build/test/lint thực tế.
