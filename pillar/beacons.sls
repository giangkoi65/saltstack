beacons:
  inotify:
    - files:
        /etc/nginx:
          mask:
            - create
            - close_write  # Thay cho cả 'create' và 'modify' (file tạo mới hay sửa xong đều phải đóng)
            - moved_to     # Bắt khi hacker chuyển file lạ từ nơi khác vào đây
            - moved_from   # Bắt khi hacker di dời/giấu file cấu hình đi nơi khác
            - delete       # Bắt khi file hoặc thư mục con bên trong bị xóa
            - delete_self  # Chỉ dùng để phòng thủ nếu hacker xóa sạch sành sanh cả thư mục gốc /etc/nginx
            - attrib       # Bắt hành vi thay đổi quyền hạn file (chmod / chown)
          recurse: True
        /var/www/mysite:
          mask:
            - create
            - close_write
            - moved_to
            - moved_from
            - delete
            - delete_self
            - attrib
          recurse: True
    - disable_during_state_run: True
