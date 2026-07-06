repair_nginx_missing_core_files:
  cmd.run:
    - name: |
        # 1. Thu thập danh sách các gói nginx đang có trên hệ thống
        PKGS=$(dpkg-query -f='${binary:Package} ${db:Status-Status}\n' -W '*nginx*' 2>/dev/null | grep ' installed' | cut -d' ' -f1)
        if [ -z "$PKGS" ]; then
          echo "Nginx chưa được cài đặt trên hệ thống. Bỏ qua bước sửa lỗi."
          exit 0
        fi
        
        # 2. Cài đặt lại để kéo toàn bộ file cấu hình tĩnh (.conf) về lại hệ thống
        apt-get install --reinstall -o Dpkg::Options::="--force-confmiss" -y $PKGS
        
        # 3. Ép cấu hình gói core trước để chắc chắn thư mục /etc/nginx/modules-enabled được sinh ra
        dpkg-reconfigure -fnoninteractive nginx-common
        
        # 4. Vòng lặp cấu hình cuốn chiếu từng gói một để các module nhận diện được thư mục và tạo symlink
        for pkg in $PKGS; do
          dpkg-reconfigure -fnoninteractive $pkg
        done
    - onlyif: |
        [ ! -d /etc/nginx/modules-enabled ] || \
        [ -z "$(ls -A /etc/nginx/modules-enabled 2>/dev/null)" ] || \
        dpkg-query -f='${binary:Package} ${db:Status-Status}\n' -W '*nginx*' 2>/dev/null | grep ' installed' | cut -d' ' -f1 | xargs dpkg -V 2>&1 | grep -q 'missing'
    - order: 1

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
