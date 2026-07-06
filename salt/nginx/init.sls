repair_nginx_missing_core_files:
  cmd.run:
    - name: apt-get install --reinstall -o Dpkg::Options::="--force-confmiss" -y nginx-common nginx-core
    - onlyif: dpkg -V nginx-common nginx-core 2>&1 | grep -q 'missing'
    - order: 1                                # Phải chạy đầu tiên trước khi quản lý các file khác

nginx_package:
  pkg.installed:
    - name: nginx
    - require:
      - cmd: repair_nginx_missing_core_files

/etc/nginx/nginx.conf:
  file.managed:
    - source: salt://nginx/files/nginx.conf
    - user: root
    - group: root
    - mode: 644
    - require:
      - pkg: nginx

# 1. Gỡ bỏ Virtual Host mặc định của Nginx để tránh xung đột port 80
/etc/nginx/sites-enabled/default:
  file.absent:
    - require:
      - pkg: nginx

# 2. Tạo thư mục chứa mã nguồn website trên Minion
/var/www/mysite:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - require:
      - pkg: nginx

# 3. Đẩy file nội dung index.html xuống Minion
/var/www/mysite/index.html:
  file.managed:
    - source: salt://nginx/files/index.html
    - user: root
    - group: root
    - mode: 644
    - require:
      - file: /var/www/mysite

# 4. Quản lý file cấu hình Virtual Host trong sites-available
/etc/nginx/sites-available/mysite.conf:
  file.managed:
    - source: salt://nginx/files/mysite.conf.jinja
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - require:
      - pkg: nginx

# 5. Tạo Symbolic Link trong sites-enabled để kích hoạt website
/etc/nginx/sites-enabled/mysite.conf:
  file.symlink:
    - target: /etc/nginx/sites-available/mysite.conf
    - require:
      - file: /etc/nginx/sites-available/mysite.conf

nginx_service:
  service.running:
    - name: nginx
    - enable: True
    - reload: True   # THẦN CHÚ 1: Dùng reload để worker cũ xử lý nốt traffic, worker mới cập nhật cấu hình mới. Không làm rớt kết nối của user!
    - sig: /usr/sbin/nginx # Giúp Salt nhận diện chính xác tiến trình Nginx đang chạy
    - watch:
      - file: /etc/nginx/nginx.conf
      - file: /etc/nginx/sites-available/mysite.conf
      - file: /etc/nginx/sites-enabled/mysite.conf

refresh_beacons_watcher:
  cmd.run:
    - name: salt-call saltutil.refresh_beacons
    - onchanges:
      - cmd: repair_nginx_missing_core_files  # Chỉ kích hoạt khi có sự kiện khôi phục thư mục/file hệ thống xảy ra
    - order: last                            # Luôn luôn chạy cuối cùng sau khi Nginx đã ổn định
