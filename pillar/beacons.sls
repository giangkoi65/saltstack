beacons:
  inotify:
    - files:
        /etc/nginx:
          mask:
            - close_write
            - moved_to
            - create
            - delete
          recurse: True
        /etc/nginx/sites-available:
          mask:
            - close_write
            - moved_to
            - create
            - delete
          recurse: True
        /var/www/mysite:
          mask:
            - close_write
            - moved_to
            - create
            - delete
          recurse: True           # <--- Tự động đệ quy canh chừng hàng nghìn file con
    - disable_during_state_run: True
