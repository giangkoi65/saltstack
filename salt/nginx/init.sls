# ==============================================================================
# 1. TỰ ĐỘNG DIỆT FILE LẠ THÊM MỚI (BAO GỒM CẢ TRONG THƯ MỤC CON)
# ==============================================================================
purge_untracked_nginx_files:
  cmd.run:
    - name: |
        # Lấy danh sách file tuyệt đối và quét sạch file không thuộc dpkg quản lý
        find /etc/nginx -type f -o -type l | while read -r f; do
          # Bỏ qua các file cấu hình do chính Salt quản lý công khai
          if [ "$f" = "/etc/nginx/nginx.conf" ] || [ "$f" = "/etc/nginx/sites-available/mysite.conf" ] || [ "$f" = "/etc/nginx/sites-enabled/mysite.conf" ]; then
            continue
          fi
          
          # Nếu file thuộc thư mục modules-enabled, bỏ qua vì Salt sẽ đồng bộ sau
          if echo "$f" | grep -q "^/etc/nginx/modules-enabled/"; then
            continue
          fi

          # Kiểm tra xem file có thuộc package nào không
          if ! dpkg -S "$f" >/dev/null 2>&1; then
            rm -f "$f"
          fi
        done
        # Xóa các thư mục rỗng phát sinh
        find /etc/nginx -type d -empty -not -path /etc/nginx -delete
    - order: 1

# ==============================================================================
# 2. PHÁT HIỆN & ÉP BUỘC HOÀN NGUYÊN FILE HỆ THỐNG BỊ SỬA ĐỔI (mime.types, koi-utf...)
# ==============================================================================
disable_apt_restart:
  cmd.run:
    - name: |
        echo "exit 101" > /usr/sbin/policy-rc.d
        chmod +x /usr/sbin/policy-rc.d
    - onlyif: |
        dpkg --verify nginx nginx-common 2>/dev/null | grep -E '\??5\?_?' | grep -q .
    - order: 2

restore_nginx_core:
  cmd.run:
    - name: |
        # Đoạn bẫy: Tìm các file hệ thống bị sửa đổi (mã trạng thái có số 5 - MD5 thay đổi) và xóa hẳn đi 
        # Việc xóa đi sẽ kích hoạt thuộc tính --force-confmiss của APT hoạt động hiệu quả 100%
        dpkg --verify nginx nginx-common 2>/dev/null | grep -E '\??5\?_?' | awk '{print $NF}' | while read -r miss_file; do
          if [ -f "$miss_file" ] && [ "$miss_file" != "/etc/nginx/nginx.conf" ]; then
            rm -f "$miss_file"
          fi
        done
        
        # Cài đè tối cao để kéo lại toàn bộ file sạch từ mirror
        apt-get install --reinstall -o Dpkg::Options::="--force-confnew" -o Dpkg::Options::="--force-confmiss" -y nginx nginx-common
    - onlyif: |
        dpkg --verify nginx nginx-common 2>/dev/null | grep -E '\??5\?_?' | grep -q .
    - require:
      - cmd: disable_apt_restart

restore_nginx_modules:
  cmd.run:
    - name: |
        mkdir -p /etc/nginx/modules-enabled
        SRC_DIR=""
        if [ -d /usr/share/nginx/modules-available ]; then
          SRC_DIR="/usr/share/nginx/modules-available"
        elif [ -d /etc/nginx/modules-available ]; then
          SRC_DIR="/etc/nginx/modules-available"
        fi
        
        if [ -n "$SRC_DIR" ]; then
          find /etc/nginx/modules-enabled/ -type l | while read -r sym; do
            if [ ! -f "$SRC_DIR/$(basename "$sym")" ]; then
              rm -f "$sym"
            fi
          done
          
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
