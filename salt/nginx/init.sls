# 1. Tự động tìm và diệt Symlink hỏng trước khi ép APT Reinstall
repair_nginx_core_files:
  cmd.run:
    - name: |
        echo "Đang quét và dọn dẹp các Symlink bị hỏng để tránh làm crash APT..."
        if [ -d /etc/nginx/sites-enabled ]; then
          find /etc/nginx/sites-enabled/ -xtype l -delete
        fi

        echo "Tiến hành reinstall core packages của Nginx..."
        PKGS=$(dpkg -l '*nginx*' | grep '^ii' | awk '{print $2}')
        if [ -n "$PKGS" ]; then
          apt-get install --reinstall -o Dpkg::Options::="--force-confmiss" -y $PKGS
        else
          echo "Nginx chưa được cài đặt, bỏ qua bước phục hồi core."
        fi
    - onlyif: |
        [ ! -f /etc/nginx/nginx.conf ] || \
        [ ! -d /etc/nginx/modules-available ] || \
        [ ! -d /etc/nginx/conf.d ] || \
        [ ! -d /etc/nginx/sites-available ] || \
        [ ! -d /etc/nginx/sites-enabled ] || \
        dpkg -V $(dpkg -l '*nginx*' | grep '^ii' | awk '{print $2}') 2>&1 | grep 'missing' | grep -v 'sites-enabled/default' -q
    - order: 1

# 2. Đảm bảo tất cả các thư mục trục cốt phải tồn tại sạch sẽ
ensure_nginx_directories:
  file.directory:
    - names:
        - /etc/nginx/modules-available
        - /etc/nginx/conf.d
        - /etc/nginx/sites-available
        - /etc/nginx/sites-enabled
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - require:
      - cmd: repair_nginx_core_files
    - require_in:
      - pkg: nginx_package

nginx_package:
  pkg.installed:
    - name: nginx
    - require:
      - cmd: repair_nginx_core_files

{% for mod in ['50-mod-http-geoip2', '50-mod-http-image-filter', '50-mod-http-xslt-filter', '50-mod-mail', '50-mod-stream', '70-mod-stream-geoip2'] %}
/etc/nginx/modules-enabled/{{ mod }}.conf:
  file.symlink:
    - target: /usr/share/nginx/modules-available/{{ mod.split('-', 1)[1] }}.conf
    - makedirs: True
    - require:
      - pkg: nginx
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
      - pkg: nginx

/etc/nginx/sites-enabled/default:
  file.absent:
    - require:
      - pkg: nginx

/var/www/mysite:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - require:
      - pkg: nginx

/var/www/mysite/index.html:
  file.managed:
    - source: salt://nginx/files/index.html
    - user: root
    - group: root
    - mode: 644
    - require:
      - file: /var/www/mysite

# 3. Bổ sung makedirs cho file cấu hình site
/etc/nginx/sites-available/mysite.conf:
  file.managed:
    - source: salt://nginx/files/mysite.conf.jinja
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - makedirs: True
    - require:
      - pkg: nginx

# 4. Bổ sung makedirs cho symlink kích hoạt site
/etc/nginx/sites-enabled/mysite.conf:
  file.symlink:
    - target: /etc/nginx/sites-available/mysite.conf
    - makedirs: True
    - require:
      - file: /etc/nginx/sites-available/mysite.conf

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

refresh_beacons_watcher:
  cmd.run:
    - name: salt-call saltutil.refresh_beacons
    - order: last
