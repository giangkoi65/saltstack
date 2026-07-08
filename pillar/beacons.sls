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
          recurse: True
    - disable_during_state_run: True