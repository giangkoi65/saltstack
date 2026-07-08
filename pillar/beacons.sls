beacons:
  inotify:
    - files:
        /etc/nginx:
          mask:
            - close_write # Bắt trọn cả hành vi thêm file mới HOẶC sửa file cũ khi vừa ghi xong
            - moved_to # Bắt hành vi kéo/thả, di chuyển file lạ từ nơi khác vào đây
            - moved_from # Bắt hành vi tháo chạy, dời file cấu hình ra chỗ khác để phá hoại
            - delete # Bắt hành vi xóa file cấu hình
            - delete_self # Bắt hành vi xóa sạch cả thư mục cha /etc/nginx
            - attrib # Bắt hành vi hacker cố tình chmod/chown để leo thang đặc quyền
          recurse: True
        /var/www/mysite:
          mask:
            - close_write
            - moved_to
            - moved_from
            - delete
            - delete_self
            - attrib          
          recurse: True
    - disable_during_state_run: True