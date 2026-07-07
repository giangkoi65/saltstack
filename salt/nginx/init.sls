# ==============================================================================
# 1. KHÔI PHỤC CORE TUYỆT ĐỐI BẰNG PACKAGE MANAGER (UPDATE-SAFE)
# ==============================================================================
repair_nginx_core_files:
  cmd.run:
    - name: |
        echo "🛑 Khóa tiến trình restart của APT..."
        echo "exit 101" > /usr/sbin/policy-rc.d
        chmod +x /usr/sbin/policy-rc.d

        echo "📦 Tiến hành cài đè hoàn nguyên file hệ thống từ Package gốc..."
        PKGS=$(dpkg -l '*nginx*' | grep '^ii' | awk '{print $2}')
        if [ -n "$PKGS" ]; then
          apt-get install --reinstall -o Dpkg::Options::="--force-confmiss" -o Dpkg::Options::="--force-confnew" -y $PKGS
        fi

        echo "🔓 Mở khóa policy-rc.d..."
        rm -f /usr/sbin/policy-rc.d
    - onlyif: |
        dpkg -V $(dpkg -l '*nginx*' | grep '^ii' | awk '{print $2}') 2>&1 | grep -v 'sites-enabled/default' | grep -qE 'missing|^\?\?5'
    - order: 1

# ==============================================================================
# 2. ANTI-DRIFT: QUẢN LÝ THƯ MỤC MẸ (🌟 SỬA ĐỔI EXCLUDE ĐỂ TRÁNH XÓA NHẦM)
# ==============================================================================
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
      - 'conf.d/'
      - 'sites-available/'
      - 'sites-enabled/'
      - 'modules-available/'
      - 'modules-enabled/'
      - 'snippets*'
    - require:
      - cmd: repair_nginx_core_files

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
    - exclude_pat: 'default'
    - require:
      - file: manage_nginx_root_dir

remove_nginx_default_sites:
  file.absent:
    - names:
      - /etc/nginx/sites-available/default
      - /etc/nginx/sites-enabled/default
    - require:
      - file: /etc/nginx/sites-available
      - file: /etc/nginx/sites-enabled
    - watch_in:
      - service: nginx_service

nginx_package:
  pkg.installed:
    - name: nginx
    - require:
      - cmd: repair_nginx_core_files

# ==============================================================================
# 3. QUẢN LÝ CONFIG TRỤC CỐT DƯỚI DẠNG TEMPLATE JINJA ĐỘC LẬP
# ==============================================================================
/etc/nginx/nginx.conf:
  file.managed:
    - source: salt://nginx/files/nginx.conf.jinja
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - require:
      - pkg: nginx_package
      - file: manage_nginx_root_dir

# ==============================================================================
# 4. QUẢN LÝ APP/SITE CONFIGURATION
# ==============================================================================
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
      - file: remove_nginx_default_sites

# ==============================================================================
# 5. ĐIỀU KHIỂN TIẾN TRÌNH DỊCH VỤ
# ==============================================================================
nginx_service:
  service.running:
    - name: nginx
    - enable: True
    - watch:
        - file: /etc/nginx/nginx.conf
        - file: /etc/nginx/sites-available/mysite.conf
        - file: /etc/nginx/sites-enabled/mysite.conf

refresh_beacons_watcher:
  cmd.run:
    - name: salt-call saltutil.refresh_beacons
    - order: last
