# ลอยกระทง · Loy Krathong

Trang web 3D (Three.js) cho đêm hội Loy Krathong: mỗi người nhập tên, chọn màu hoa và gửi lời chúc,
bông hoa (krathong) của họ trôi trên sông và mọi người đều thấy theo thời gian thực.

- `index.html`: toàn bộ trang (giao diện tiếng Thái, nhạc YouTube + nhạc bản địa tạo bằng Web Audio)
- `firestore.rules`: luật bảo mật Firebase Firestore (chỉ được thêm người và nối thêm lời chúc)
- Dữ liệu lưu ở Firebase Firestore, collection `people`, khóa là tên viết thường

Chạy kiểu cũ trên máy (không cần Firebase): `start.bat` (Python server + Cloudflare Tunnel).
