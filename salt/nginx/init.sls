# 1. Khóa tay APT và Phục hồi Core Nginx diện rộng (Cả missing lẫn modified)
repair_nginx_core_files:
  cmd.run:
    - name: |
        echo "🛑 Tạo Layer bảo vệ policy-rc.d để cấm APT tự ý Restart làm mất kết nối người dùng..."
        echo "exit 101" > /usr/sbin/policy-rc.d
        chmod +x /usr/sbin/policy-rc.d

        echo "🧹 Quét sạch các Symlink bị hỏng trong sites-enabled..."
        if [ -d /etc/nginx/sites-enabled ]; then
          find /etc/nginx/sites-enabled/ -xtype l -delete
        fi

        echo "📦 Tiến hành reinstall core packages của Nginx..."
        PKGS=$(dpkg -l '*nginx*' | grep '^ii' | awk '{print $2}')
        if [ -n "$PKGS" ]; then
          # Sử dụng --force-confmiss để bù file mất, --force-confold để giữ file cũ nếu có xung đột nhẹ
          apt-get install --reinstall -o Dpkg::Options::="--force-confmiss" -y $PKGS
        fi

        echo "🔓 Gỡ bỏ khóa policy-rc.d, trả lại quyền cho Salt quản lý tiến trình..."
        rm -f /usr/sbin/policy-rc.d
    - onlyif: |
        [ ! -f /etc/nginx/nginx.conf ] || \
        [ ! -d /etc/nginx/modules-available ] || \
        [ ! -d /etc/nginx/conf.d ] || \
        [ ! -d /etc/nginx/sites-available ] || \
        [ ! -d /etc/nginx/sites-enabled ] || \
        dpkg -V $(dpkg -l '*nginx*' | grep '^ii' | awk '{print $2}') 2>&1 | grep -v 'sites-enabled/default' | grep -qE 'missing|^\?\?5'
    - order: 1

# Quản lý tối cao thư mục gốc /etc/nginx, xóa mọi file lạ trừ các file hệ thống mặc định
manage_nginx_root_dir:
  file.directory:
    - name: /etc/nginx
    - user: root
    - group: root
    - mode: 755
    - clean: True
    # exclude_pat dùng để liệt kê các file/thư mục mặc định của OS mà ông KHÔNG MUỐN Salt xóa bậy
    - exclude_pat:
      - 'mime.types'
      - 'fastcgi_params'
      - 'uwsgi_params'
      - 'scgi_params'
      - 'koi-win'
      - 'koi-utf'
      - 'win-utf'
    - require:
      - cmd: repair_nginx_core_files
    - require_in:
      - file: /etc/nginx/nginx.conf

# 2. Quản lý thư mục trục cốt và QUÉT SẠCH FILE RÁC (Bổ sung clean: True toàn diện)
/etc/nginx/conf.d:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - clean: True
    - require:
      - cmd: repair_nginx_core_files

/etc/nginx/sites-available:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - clean: True
    - exclude_pat: 'default' # Giữ lại file default của hệ thống nếu APT đổ xuống
    - require:
      - cmd: repair_nginx_core_files

/etc/nginx/sites-enabled:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - clean: True
    - require:
      - cmd: repair_nginx_core_files

nginx_package:
  pkg.installed:
    - name: nginx
    - require:
      - cmd: repair_nginx_core_files

# 3. Cấu hình Modules và Core Files
{% for mod in ['50-mod-http-geoip2', '50-mod-http-image-filter', '50-mod-http-xslt-filter', '50-mod-mail', '50-mod-stream', '70-mod-stream-geoip2'] %}
/etc/nginx/modules-enabled/{{ mod }}.conf:
  file.symlink:
    - target: /usr/share/nginx/modules-available/{{ mod.split('-', 1)[1] }}.conf
    - makedirs: True
    - require:
      - pkg: nginx_package
    - watch_in:
      - service: nginx_service
{% endfor %}

/etc/nginx/nginx.conf:
  file.managed:
    - source: salt://nginx/files/nginx.conf
    - user: root
    - group: root
    - mode: 644
    - require:
      - pkg: nginx_package

# 4. Quản lý Source Code Web và File Cấu Hình Site
/var/www/mysite:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

/var/www/mysite/index.html:
  file.managed:
    - source: salt://nginx/files/index.html
    - user: root
    - group: root
    - mode: 644
    - require:
      - file: /var/www/mysite

/etc/nginx/sites-available/mysite.conf:
  file.managed:
    - source: salt://nginx/files/mysite.conf.jinja
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - require:
      - file: /etc/nginx/sites-available

/etc/nginx/sites-enabled/mysite.conf:
  file.symlink:
    - target: /etc/nginx/sites-available/mysite.conf
    - require:
      - file: /etc/nginx/sites-enabled
      - file: /etc/nginx/sites-available/mysite.conf

# 5. Kiểm soát Tiến trình Dịch vụ (Ép buộc Graceful Reload thay vì Restart)
nginx_service:
  service.running:
    - name: nginx
    - enable: True
    - reload: True # <--- GIỮ KẾT NỐI NGƯỜI DÙNG: Chỉ dùng lệnh SIGHUP (reload) thay vì restart
    - sig: /usr/sbin/nginx 
    - watch:
        - file: /etc/nginx/nginx.conf
        - file: /etc/nginx/sites-available/mysite.conf
        - file: /etc/nginx/sites-enabled/mysite.conf

# 6. Luôn luôn nạp lại cấu hình Beacon ở cuối phiên để tránh mất dấu Watcher
refresh_beacons_watcher:
  cmd.run:
    - name: salt-call saltutil.refresh_beacons
    - order: last
