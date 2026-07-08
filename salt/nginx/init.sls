# ==============================================================================
# 1. TỰ ĐỘNG PHÁT HIỆN SỰ CỐ (SỬA/XÓA/MV) VÀ CÀI LẠI SẠCH TỪ KHÔ GỐC (APT)
# ==============================================================================
repair_nginx_core_files:
  cmd.run:
    - name: |
        echo "🛑 Khóa tiến trình restart của APT..."
        echo "exit 101" > /usr/sbin/policy-rc.d
        chmod +x /usr/sbin/policy-rc.d

        PKGS=$(dpkg -l '*nginx*' | grep '^ii' | awk '{print $2}')
        
        echo "⚠️ Phát hiện cấu hình core bị can thiệp (Sửa/Xóa/Di chuyển)!"
        echo "🧹 Tiến hành tải và cài đặt lại sạch hoàn toàn từ APT Repository..."
        
        # --force-confnew: Ghi đè cấu hình mặc định lên các file đã bị chỉnh sửa
        # --force-confmiss: Cài bù lại hoàn toàn các file đã bị xóa hoặc di chuyển (mv)
        apt-get install --reinstall -o Dpkg::Options::="--force-confnew" -o Dpkg::Options::="--force-confmiss" -y $PKGS

        echo "🔓 Mở khóa policy-rc.d..."
        rm -f /usr/sbin/policy-rc.d
    - onlyif: |
        # Bộ lọc thông minh sử dụng dpkg -V để phát hiện mọi thay đổi cấu trúc/nội dung
        # Loại trừ tuyệt đối các file vhost và cấu hình do Salt quản lý để tránh xung đột lặp lại
        dpkg -V nginx nginx-common nginx-core 2>/dev/null | grep '/etc/nginx/' | grep -vE '(/etc/nginx/nginx\.conf|/etc/nginx/sites-available/mysite\.conf|/etc/nginx/sites-enabled/|/etc/nginx/sites-available/default)'
    - shell: /bin/bash
    - order: 1

# ==============================================================================
# 2. KHÓA CHẶT THƯ MỤC CẤU HÌNH VÀ DIỆT FILE LẠ (ĐÃ SỬA LỖI EXCLUDE_PAT)
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
    - clean: True
    - require:
      - file: manage_nginx_root_dir

/etc/nginx/modules-enabled:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - clean: False
    - require:
      - file: manage_nginx_root_dir

/etc/nginx/sites-available:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - clean: True 
    # ĐÃ SỬA: Gom thành 1 chuỗi Regex để Salt không nhận diện nhầm làm xóa file vhost
    - exclude_pat: '.*(default|mysite\.conf)$'
    - require:
      - file: manage_nginx_root_dir

/etc/nginx/sites-enabled:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - clean: True 
    # ĐÃ SỬA: Đưa về định dạng chuỗi Regex chuẩn
    - exclude_pat: '.*mysite\.conf$'
    - require:
      - file: manage_nginx_root_dir

nginx_package:
  pkg.installed:
    - name: nginx
    - require:
      - cmd: repair_nginx_core_files

# ==============================================================================
# 3. QUẢN LÝ FILE TRỤC CỐT (ÁP TEMPLATE ĐÈ LÊN SAU KHI ĐÃ LÀM SẠCH HỆ THỐNG)
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
# 4. QUÉT SẠCH THƯ MỤC RÁC THỪA NGOÀI DANH SÁCH
# ==============================================================================
purge_untracked_nginx_root_files:
  cmd.run:
    - name: |
        echo "🔍 Đang rà quét và quét sạch mọi thành phần lạ tại /etc/nginx..."
        PKG_FILES=$(dpkg -L nginx nginx-common nginx-core 2>/dev/null)
        
        WHITELIST=$(cat << EOF
        /etc/nginx
        /etc/nginx/nginx.conf
        /etc/nginx/sites-available/mysite.conf
        /etc/nginx/sites-enabled/mysite.conf
        EOF
        )
        ALL_WHITELIST=$(echo -e "${PKG_FILES}\n${WHITELIST}" | sort -u)

        find /etc/nginx -mindepth 1 | sort -r | while read -r item; do
          if [[ "$item" == "/etc/nginx/conf.d"* || "$item" == "/etc/nginx/modules-enabled"* || "$item" == "/etc/nginx/sites-available"* || "$item" == "/etc/nginx/sites-enabled"* ]]; then
            continue
          fi
          
          if ! echo "$ALL_WHITELIST" | grep -qxF "$item"; then
            echo "🗑️ [ANTI-DRIFT] Xóa thành phần lạ: $item"
            rm -rf "$item"
          fi
        done
    - shell: /bin/bash
    - require:
      - cmd: repair_nginx_core_files
      - file: /etc/nginx/nginx.conf
    - order: 6

# ==============================================================================
# 5. KHỞI ĐỘNG DỊCH VỤ VÀ WATCHER BEACONS
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
    - onchanges:
      - cmd: repair_nginx_core_files
      - file: manage_nginx_root_dir
