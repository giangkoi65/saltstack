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
    - clean: True
#    - exclude_pat: 'default'
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
    - reload: True
    - watch:
        - file: /etc/nginx/nginx.conf
        - file: /etc/nginx/sites-available/mysite.conf
        - file: /etc/nginx/sites-enabled/mysite.conf

refresh_beacons_watcher:
  cmd.run:
    - name: salt-call saltutil.refresh_beacons
    - order: last
    - onchanges:
      - file: /etc/nginx

# ==============================================================================
# 6. DỌN SẠCH TUYỆT ĐỐI FILE/THƯ MỤC LẠ TOÀN BỘ /ETC/NGINX (DEEP SCAN ANTI-DRIFT)
# ==============================================================================
purge_untracked_nginx_structures:
  cmd.run:
    - name: |
        echo "🔍 [ANTI-DRIFT] Đang quét đệ quy toàn bộ cấu hình tại /etc/nginx..."
        
        # 1. Lấy động danh sách toàn bộ file và thư mục hợp pháp do APT/DPKG cài đặt
        PKG_FILES=$(dpkg -L nginx nginx-common nginx-core 2>/dev/null)
        
        # 2. Định nghĩa các thành phần custom do chính bạn quản lý qua Salt/Git
        MY_FILES="/etc/nginx/nginx.conf
        /etc/nginx/sites-available/mysite.conf
        /etc/nginx/sites-enabled/mysite.conf"
        
        # Hợp nhất thành một siêu Whitelist chuẩn
        WHITELIST=$(echo -e "${PKG_FILES}\n${MY_FILES}" | sort -u)
        
        # 3. Quét đệ quy sâu (-mindepth 1) 
        # Sử dụng 'sort -r' để sắp xếp ngược, đảm bảo file/thư mục con bị xóa trước, thư mục cha xóa sau
        find /etc/nginx -mindepth 1 | sort -r | while read -r current_item; do
          if ! echo "$WHITELIST" | grep -qxF "$current_item"; then
            echo "🗑️ [ANTI-DRIFT] Phát hiện mục lạ trái phép: $current_item -> TIẾN HÀNH XÓA SẠCH!"
            rm -rf "$current_item"
          fi
        done
    - require:
        - cmd: repair_nginx_core_files
        - file: /etc/nginx/nginx.conf
        - file: /etc/nginx/sites-available/mysite.conf
        - file: /etc/nginx/sites-enabled/mysite.conf