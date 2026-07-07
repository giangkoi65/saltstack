beacons:
  inotify:
    - files:
        /etc/nginx:
          mask:
            - close_write
            - moved_to
            - moved_from
            - create
            - delete
            - delete_self
          recurse: True
        /var/www/mysite:
          mask:
            - close_write
            - moved_to
            - moved_from
            - create
            - delete
            - delete_self
          recurse: True           # <--- Tự động đệ quy canh chừng hàng nghìn file con
    - disable_during_state_run: True
