# ==============================================================================
# 1. TỰ ĐỘNG DIỆT FILE LẠ THÊM MỚI (CREATE/MOVED_TO) - CHẠY ĐẦU TIÊN
# ==============================================================================
purge_untracked_nginx_files:
  cmd.run:
    - name: |
        find /etc/nginx -type f -o -type l | while read -r f; do
          if ! dpkg -S "$f" >/dev/null 2>&1; then
            case "$f" in
              /etc/nginx/sites-available/mysite.conf|/etc/nginx/sites-enabled/mysite.conf)
                ;;
              /etc/nginx/modules-enabled/*)
                ;;
              *)
                rm -f "$f"
                ;;
            esac
          fi
        done
        find /etc/nginx -type d -empty -not -path /etc/nginx -delete
    - order: 1

# ==============================================================================
# 2. PHÁT HIỆN & HOÀN NGUYÊN FILE CORE BỊ SAI LỆCH (CLOSE_WRITE/DELETE/ATTRIB)
# ==============================================================================
disable_apt_restart:
  cmd.run:
    - name: |
        echo "exit 101" > /usr/sbin/policy-rc.d
        chmod +x /usr/sbin/policy-rc.d
    - onlyif: |
        dpkg --verify nginx nginx-common 2>/dev/null | grep '/etc/nginx/' | grep -Ev 'nginx.conf|mysite.conf|default' | grep -q .
    - order: 2

restore_nginx_core:
  cmd.run:
    - name: apt-get install --reinstall -o Dpkg::Options::="--force-confnew" -o Dpkg::Options::="--force-confmiss" -y nginx nginx-common
    - onlyif: |
        dpkg --verify nginx nginx-common 2>/dev/null | grep '/etc/nginx/' | grep -Ev 'nginx.conf|mysite.conf|default' | grep -q .
    - require:
      - cmd: disable_apt_restart

# 🔥 SỬA ĐỒI GỐC: Tự động khôi phục chuẩn xác mọi symlink module có sẵn trong hệ thống
restore_nginx_modules:
  cmd.run:
    - name: |
        mkdir -p /etc/nginx/modules-enabled
        # Tìm thư mục chứa module gốc (tùy phiên bản Ubuntu cấu trúc có thể ở /usr/share hoặc /etc)
        SRC_DIR=""
        if [ -d /usr/share/nginx/modules-available ]; then
          SRC_DIR="/usr/share/nginx/modules-available"
        elif [ -d /etc/nginx/modules-available ]; then
          SRC_DIR="/etc/nginx/modules-available"
        fi
        
        if [ -n "$SRC_DIR" ]; then
          # 1. Quét ngược: Xóa các symlink trong modules-enabled nếu file gốc tương ứng không còn tồn tại
          find /etc/nginx/modules-enabled/ -type l | while read -r sym; do
            if [ ! -f "$SRC_DIR/$(basename "$sym")" ]; then
              rm -f "$sym"
            fi
          done
          
          # 2. Khôi phục: Tạo lại tất cả các symlink từ các file cấu hình module chính thống hiện có
          for f in "$SRC_DIR"/*.conf; do
            if [ -f "$f" ]; then
              ln -sf "$f" "/etc/nginx/modules-enabled/$(basename "$f")"
            fi
          done
        fi
    - order: 3

enable_apt_restart:
  cmd.run:
    - name: rm -f /usr/sbin/policy-rc.d
    - onchanges:
      - cmd: disable_apt_restart

# ==============================================================================
# 3. ĐẢM BẢO CẤU TRÚC THƯ MỤC LÀM VIỆC CỦA VHOST LUÔN TỒN TẠI
# ==============================================================================
/etc/nginx/sites-available:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

/etc/nginx/sites-enabled:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

remove_default_vhost:
  file.absent:
    - name: /etc/nginx/sites-enabled/default
    - require:
      - file: /etc/nginx/sites-enabled

# ==============================================================================
# 4. QUẢN LÝ CÁC FILE CẤU HÌNH TÙY BIẾN THEO TEMPLATE (GHI ĐÈ NẾU SAI LỆCH)
# ==============================================================================
/etc/nginx/nginx.conf:
  file.managed:
    - source: salt://nginx/files/nginx.conf.jinja
    - template: jinja
    - user: root
    - group: root
    - mode: 644

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
# 5. QUẢN LÝ MÃ NGUỒN VÀ DỊCH VỤ (ZERO DOWNTIME)
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
    - reload: True
    - watch:
        - file: /etc/nginx/nginx.conf
        - file: /etc/nginx/sites-available/mysite.conf
        - file: /var/www/mysite/index.html
