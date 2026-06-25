beacons:
  inotify:
    - files:
        /etc/nginx/nginx.conf:
          mask:
            - modify
            - close_write
        /etc/nginx/sites-available/mysite.conf:
          mask:
            - modify
            - close_write
    - disable_during_state_run: True
