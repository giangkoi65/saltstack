# 1. Khóa tay APT và Khôi phục Tuyệt đối Core Nginx (Mất file hoặc Sửa nội dung file hệ thống)
repair_nginx_core_files:
  cmd.run:
    - name: |
        echo "🛑 Tạo Layer bảo vệ policy-rc.d..."
        echo "exit 101" > /usr/sbin/policy-rc.d
        chmod +x /usr/sbin/policy-rc.d

        echo "🧹 Quét sạch các Symlink bị hỏng trong sites-enabled..."
        if [ -d /etc/nginx/sites-enabled ]; then
          find /etc/nginx/sites-enabled/ -xtype l -delete
        fi

        echo "📦 Tiến hành cài đè phục hồi core packages của Nginx..."
        PKGS=$(dpkg -l '*nginx*' | grep '^ii' | awk '{print $2}')
        if [ -n "$PKGS" ]; then
          # --force-confmiss: bù file mất | --force-confold: cài đè cấu hình mặc định nếu bị đổi
          apt-get install --reinstall -o Dpkg::Options::="--force-confmiss" -y $PKGS
        fi

        echo "🔓 Gỡ bỏ khóa policy-rc.d..."
        rm -f /usr/sbin/policy-rc.d
    # 🌟 FIX: Chỉ cần dpkg phát hiện mất file hoặc sửa file (trừ sites-enabled/default), chạy phục hồi ngay
    - onlyif: |
        dpkg -V $(dpkg -l '*nginx*' | grep '^ii' | awk '{print $2}') 2>&1 | grep -v 'sites-enabled/default' | grep -qE 'missing|^\?\?5'
    - order: 1

# 2. Quản lý tối cao thư mục gốc /etc/nginx, xóa mọi file lạ của hacker
manage_nginx_root_dir:
  file.directory:
    - name: /etc/nginx
    - user: root
    - group: root
    - mode: 755
    - clean: True
    - exclude_pat:
      - 'mime.types'
      - 'fastcgi.conf'
      - 'fastcgi_params'
      - 'proxy_params'
      - 'uwsgi_params'
      - 'scgi_params'
      - 'koi-win'
      - 'koi-utf'
      - 'win-utf'
      - 'modules-available'
      - 'modules-enabled'
      - 'snippets'
    - require:
      - cmd: repair_nginx_core_files

# 3. Quản lý thư mục con trục cốt và QUÉT SẠCH FILE RÁC
/etc/nginx/conf.d:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - clean: True
    - require:
      - file: manage_nginx_root_dir

/etc/nginx/sites-available:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - clean: True
    - exclude_pat: 'default'
    - require:
      - file: manage_nginx_root_dir

/etc/nginx/sites-enabled:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - clean: True
    - require:
      - file: manage_nginx_root_dir

nginx_package:
  pkg.installed:
    - name: nginx
    - require:
      - cmd: repair_nginx_core_files

# 4. Cấu hình Modules động và Core Files
{% for mod in ['50-mod-http-geoip2', '50-mod-http-image-filter', '50-mod-http-xslt-filter', '50-mod-mail', '50-mod-stream', '70-mod-stream-geoip2'] %}
/etc/nginx/modules-enabled/{{ mod }}.conf:
  file.symlink:
    - target: /usr/share/nginx/modules-available/{{ mod.split('-', 1)[1] }}.conf
    - makedirs: True
    - require:
      - pkg: nginx_package
      - file: manage_nginx_root_dir
    - watch_in:
      - service: nginx_service
{% endfor %}

# Quản lý file cấu hình tối cao nginx.conf
/etc/nginx/nginx.conf:
  file.managed:
    - source: salt://nginx/files/nginx.conf
    - user: root
    - group: root
    - mode: 644
    - require:
      - pkg: nginx_package
      - file: manage_nginx_root_dir

# BỔ SUNG: Khóa chặt các file thông số nhạy cảm mà hacker hay lợi dụng để tiêm độc cấu hình
{% for core_file in ['fastcgi.conf', 'fastcgi_params', 'koi-utf', 'koi-win', 'mime.types', 'proxy_params', 'scgi_params', 'uwsgi_params', 'win-utf'] %}
/etc/nginx/{{ core_file }}:
  file.managed:
    - source: salt://nginx/files/{{ core_file }}
    - user: root
    - group: root
    - mode: 644
    - require:
      - pkg: nginx_package
    - watch_in:
      - service: nginx_service
{% endfor %}

# 5. Quản lý Source Code Web và File Cấu Hình Site
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

# 6. Kiểm soát Tiến trình Dịch vụ (Graceful Reload)
nginx_service:
  service.running:
    - name: nginx
    - enable: True
    - reload: True
    - sig: /usr/sbin/nginx 
    - watch:
        - file: /etc/nginx/nginx.conf
        - file: /etc/nginx/sites-available/mysite.conf
        - file: /etc/nginx/sites-enabled/mysite.conf

# 7. Luôn luôn nạp lại cấu hình Beacon ở cuối phiên
refresh_beacons_watcher:
  cmd.run:
    - name: salt-call saltutil.refresh_beacons
    - order: last