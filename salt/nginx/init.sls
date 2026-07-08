# ==============================================================================
# 1. TỰ ĐỘNG DIỆT FILE LẠ THÊM MỚI (CHUẨN XÁC, AN TOÀN)
# ==============================================================================
purge_untracked_nginx_files:
  cmd.run:
    - name: |
        # Sử dụng dấu ngoặc \( \) để gom nhóm chính xác điều kiện tìm kiếm file thông thường hoặc symlink
        find /etc/nginx \( -type f -o -type l \) | while read -r f; do
          
          # Bỏ qua các file cấu hình do chính Salt quản lý công khai
          if [ "$f" = "/etc/nginx/nginx.conf" ] || [ "$f" = "/etc/nginx/sites-available/mysite.conf" ] || [ "$f" = "/etc/nginx/sites-enabled/mysite.conf" ]; then
            continue
          fi

          # Kiểm tra xem file có thuộc bất kỳ package nào của hệ thống không
          if ! dpkg -S "$f" >/dev/null 2>&1; then
            rm -f "$f"
          fi
        done
        # Xóa các thư mục rỗng phát sinh nhưng giữ lại thư mục gốc /etc/nginx
        find /etc/nginx -type d -empty -not -path /etc/nginx -delete
    - order: 1

# ==============================================================================
# 2. QUẢN LÝ CẤU TRÚC THƯ MỤC LÀM VIỆC CỦA VHOST
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
# 3. ĐỒNG BỘ MODULES (XỬ LÝ CẢ FILE THƯỜNG VÀ SYMLINK LẠ)
# ==============================================================================
restore_nginx_modules:
  cmd.run:
    - name: |
        mkdir -p /etc/nginx/modules-enabled
        SRC_DIR="/usr/share/nginx/modules-available"
        if [ ! -d "$SRC_DIR" ] && [ -d "/etc/nginx/modules-available" ]; then
          SRC_DIR="/etc/nginx/modules-available"
        fi
        
        if [ -d "$SRC_DIR" ]; then
          # Quét sạch bất kỳ file thường (-type f) hoặc symlink (-type l) lạ trong modules-enabled
          find /etc/nginx/modules-enabled/ \( -type f -o -type l \) | while read -r sym; do
            if [ ! -f "$SRC_DIR/$(basename "$sym")" ]; then
              rm -f "$sym"
            fi
          done
          
          # Tạo lại liên kết chuẩn cho các module hợp lệ
          for f in "$SRC_DIR"/*.conf; do
            if [ -f "$f" ]; then
              ln -sf "$f" "/etc/nginx/modules-enabled/$(basename "$f")"
            fi
          done
        fi
    - order: 2

# ==============================================================================
# 4. QUẢN LÝ CÁC FILE CẤU HÌNH THEO TEMPLATE (MƯỢT MÀ, KHÔNG DOWNTIME)
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
# 5. DỊCH VỤ NGINX (CHỈ RELOAD KHI THAY ĐỔI FILE CẤU HÌNH THỰC SỰ)
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
    - reload: True   # Sử dụng cơ chế Reload cấu hình mềm (Zero downtime cho người dùng)
    - watch:
        - file: /etc/nginx/nginx.conf
        - file: /etc/nginx/sites-available/mysite.conf
        - file: /var/www/mysite/index.html
