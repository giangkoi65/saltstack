nginx:
  pkg.installed: []
  service.running:
    - enable: True
    - reload: True
    - watch:
      - file: /etc/nginx/nginx.conf
      - file: /etc/nginx/sites-available/mysite.conf
      - file: /etc/nginx/sites-enabled/mysite.conf
      - file: /etc/nginx/sites-enabled/default

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
    - user: www-data
    - group: www-data
    - mode: 755
    - makedirs: True
    - require:
      - pkg: nginx

# 3. Đẩy file nội dung index.html xuống Minion
/var/www/mysite/index.html:
  file.managed:
    - source: salt://nginx/files/index.html
    - user: www-data
    - group: www-data
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
