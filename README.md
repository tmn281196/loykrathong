# ลอยกระทง · Loy Krathong — T.N.G TECH

Trang web 3D (Three.js) cho đêm hội Loy Krathong: mỗi người nhập tên, chọn loại krathong và màu hoa, gửi lời chúc,
bông hoa của họ trôi trên sông và mọi người đều thấy theo thời gian thực.

Trang: https://tmn281196.github.io/loykrathong/

- `index.html`: toàn bộ trang (giao diện tiếng Thái, nhạc YouTube + nhạc tạo bằng Web Audio, pháo hoa, Wat Arun)
- `assets/`: logo TNG và ảnh xem trước khi chia sẻ link
- `firestore.rules`: luật bảo mật Firebase Firestore (chỉ được thêm người và nối thêm lời chúc)
- Dữ liệu lưu ở Firebase Firestore, collection `people`, khóa là tên viết thường

Cập nhật trang: sửa `index.html`, rồi `git commit` và `git push`; GitHub Pages tự cập nhật sau khoảng 1 phút.
