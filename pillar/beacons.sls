beacons:
  inotify:
    - files:
        /etc/nginx:
          mask:
            - modify       # Bắt thêm hành vi sửa đổi trực tiếp dữ liệu bên trong file
            - attrib       # Bắt hành vi đổi quyền (chmod/chown) trái phép
            - close_write
            - moved_to
            - moved_from
            - create
            - delete
            - delete_self
          recurse: True
        /var/www/mysite:
          mask:
            - modify
            - attrib
            - close_write
            - moved_to
            - moved_from
            - create
            - delete
            - delete_self
          recurse: True
    - disable_during_state_run: True