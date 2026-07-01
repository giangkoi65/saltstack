beacons:
  inotify:
    - files:
        /etc/nginx/nginx.conf:
          mask:
            - close_write
            - moved_to
            - create
            - delete
        /etc/nginx/sites-available/mysite.conf:
          mask:
            - close_write
            - moved_to
            - create
            - delete
        /var/www/mysite:
          mask:
            - close_write
            - moved_to
            - create
            - delete
          recurse: True           # <--- Tự động đệ quy canh chừng hàng nghìn file con
    - disable_during_state_run: True
