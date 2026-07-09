beacons:
  inotify:
    - files:
        /etc/nginx:
          mask:
            - close_write  # Thay cho cả 'create' và 'modify' (file tạo mới hay sửa xong đều phải đóng)
            - moved_to     # Bắt khi hacker chuyển file lạ từ nơi khác vào đây
            - moved_from   # Bắt khi hacker di dời/giấu file cấu hình đi nơi khác
            - delete       # Bắt khi file hoặc thư mục con bên trong bị xóa
          recurse: True
          coalesce: True
        /var/www/mysite:
          mask:
            - close_write
            - moved_to
            - moved_from
            - delete
          recurse: True
          coalesce: True
    - disable_during_state_run: True
