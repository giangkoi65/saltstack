# ==============================================================================
# 1. KHÔI PHỤC CORE TUYỆT ĐỐI BẰNG PACKAGE MANAGER (UPDATE-SAFE)
# ==============================================================================
repair_nginx_core_files:
  cmd.run:
    - name: |
        echo "🛑 Khóa tiến trình restart của APT..."
        echo "exit 101" > /usr/sbin/policy-rc.d
        chmod +x /usr/sbin/policy-rc.d

        PKGS=$(dpkg -l '*nginx*' | grep '^ii' | awk '{print $2}')
        if [ -n "$PKGS" ]; then
          echo "🧹 Tự động tìm và XÓA SẠCH các file cấu hình bị thay đổi (trừ default)..."
          dpkg -V $PKGS 2>&1 | grep -v 'sites-enabled/default' | awk '{print $NF}' | xargs rm -f

          echo "📦 Cài bù hoàn nguyên file sạch từ Package gốc..."
          apt-get install --reinstall -o Dpkg::Options::="--force-confmiss" -y $PKGS
        fi

        echo "🔓 Mở khóa policy-rc.d..."
        rm -f /usr/sbin/policy-rc.d
    - onlyif: |
        dpkg -V $(dpkg -l '*nginx*' | grep '^ii' | awk '{print $2}') 2>&1 | grep -v 'sites-enabled/default' | grep -q .
    - order: 1

# ==============================================================================
# 2. ANTI-DRIFT CHUẨN: CHỈ DỌN DẸP NƠI CHỨA CẤU HÌNH ỨNG DỤNG
# ==============================================================================
manage_nginx_root_dir:
  file.directory:
    - name: /etc/nginx
    - user: root
    - group: root
    - mode: 755
    - require:
      - cmd: repair_nginx_core_files

/etc/nginx/conf.d:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - clean: True # Diệt file lạ
    - require:
      - file: manage_nginx_root_dir

/etc/nginx/modules-enabled:
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
    - clean: True # 🔥 Giữ nghiêm ngặt tại đây để diệt file lạ
    - exclude_pat: 'default'
    - require:
      - file: manage_nginx_root_dir

/etc/nginx/sites-enabled:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - clean: True # 🔥 Giữ nghiêm ngặt tại đây để diệt file cấu hình lén kích hoạt
    - require:
      - file: manage_nginx_root_dir

nginx_package:
  pkg.installed:
    - name: nginx
    - require:
      - cmd: repair_nginx_core_files

# ==============================================================================
# 3. QUẢN LÝ CONFIG TRỤC CỐT DƯỚI DẠNG TEMPLATE JINJA
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

# ==============================================================================
# 5. ĐIỀU KHIỂN TIẾN TRÌNH DỊCH VỤ
# ==============================================================================
nginx_service:
  service.running:
    - name: nginx
    - enable: True
    - sig: /usr/sbin/nginx 
    - watch:
        - file: /etc/nginx/nginx.conf
        - file: /etc/nginx/sites-available/mysite.conf
        - file: /etc/nginx/sites-enabled/mysite.conf

refresh_beacons_watcher:
  cmd.run:
    - name: salt-call saltutil.refresh_beacons
    - order: last
