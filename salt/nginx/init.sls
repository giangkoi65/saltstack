# 1. Khôi phục lại các file cấu hình tĩnh cơ bản của Nginx nếu bị xóa sạch
repair_nginx_core_files:
  cmd.run:
    - name: apt-get install --reinstall -o Dpkg::Options::="--force-confmiss" -y nginx-common nginx-core
    - onlyif: |
        [ ! -f /etc/nginx/nginx.conf ] || \
        dpkg -V nginx-common nginx-core 2>&1 | grep -q 'missing'
    - order: 1

nginx_package:
  pkg.installed:
    - name: nginx
    - require:
      - cmd: repair_nginx_core_files

# 2. Tự động quản lý và ép tạo lại toàn bộ Symlink Modules bằng Jinja Loop
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

# Gỡ bỏ Virtual Host mặc định của Nginx để tránh xung đột port 80
/etc/nginx/sites-enabled/default:
  file.absent:
    - require:
      - pkg: nginx

# Tạo thư mục chứa mã nguồn website trên Minion
/var/www/mysite:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - require:
      - pkg: nginx

# Đẩy file nội dung index.html xuống Minion
/var/www/mysite/index.html:
  file.managed:
    - source: salt://nginx/files/index.html
    - user: root
    - group: root
    - mode: 644
    - require:
      - file: /var/www/mysite

# Quản lý file cấu hình Virtual Host trong sites-available
/etc/nginx/sites-available/mysite.conf:
  file.managed:
    - source: salt://nginx/files/mysite.conf.jinja
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - require:
      - pkg: nginx

# Tạo Symbolic Link trong sites-enabled để kích hoạt website
/etc/nginx/sites-enabled/mysite.conf:
  file.symlink:
    - target: /etc/nginx/sites-available/mysite.conf
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
    - onchanges:
      - cmd: repair_nginx_core_files  
    - order: last
