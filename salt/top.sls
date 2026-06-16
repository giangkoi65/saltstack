main: # <--- Sử dụng môi trường main
  'ubuntu-minion-*':
    - nginx # <--- Trỏ đến thư mục nginx (chính là file nginx/init.sls của bạn)
