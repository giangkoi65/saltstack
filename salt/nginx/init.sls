# ==============================================================================
# 1. TỰ ĐỘNG DIỆT FILE LẠ THÊM MỚI (CREATE/MOVED_TO)
# ==============================================================================
purge_untracked_nginx_files:
  cmd.run:
    - name: |
        find /etc/nginx \( -type f -o -type l \) | while read -r f; do
          if [ "$f" = "/etc/nginx/nginx.conf" ] || [ "$f" = "/etc/nginx/sites-available/mysite.conf" ] || [ "$f" = "/etc/nginx/sites-enabled/mysite.conf" ]; then
            continue
          fi
          if ! dpkg -S "$f" >/dev/null 2>&1; then
            rm -f "$f"
          fi
        done
        find /etc/nginx -type d -empty -not -path /etc/nginx -delete

# ==============================================================================
# 2. PHÁT HIỆN & ÉP BUỘC HOÀN NGUYÊN FILE HỆ THỐNG BỊ SỬA ĐỔI/MẤT
# ==============================================================================
disable_apt_restart:
  cmd.run:
    - name: |
        echo "exit 101" > /usr/sbin/policy-rc.d
        chmod +x /usr/sbin/policy-rc.d
    - onlyif: |
        dpkg --verify nginx nginx-common 2>/dev/null | grep '/etc/nginx/' | grep -Ev 'nginx.conf|mysite.conf|default' | grep -q .
    - require:
      - cmd: purge_untracked_nginx_files

restore_nginx_core:
  cmd.run:
    - name: apt-get install --reinstall -o Dpkg::Options::="--force-confnew" -o Dpkg::Options::="--force-confmiss" -y nginx nginx-common
    - onlyif: |
        dpkg --verify nginx nginx-common 2>/dev/null | grep '/etc/nginx/' | grep -Ev 'nginx.conf|mysite.conf|default' | grep -q .
    - require:
      - cmd: disable_apt_restart

# Khôi phục các module hợp lệ bằng giải pháp loại bỏ hoàn toàn dấu nháy đơn lồng nhau
restore_nginx_modules:
  cmd.run:
    - name: |
        mkdir -p /etc/nginx/modules-enabled
        rm -rf /etc/nginx/modules-enabled/*
        SRC_DIR="/usr/share/nginx/modules-available"
        if [ ! -d "$SRC_DIR" ] && [ -d "/etc/nginx/modules-available" ]; then
          SRC_DIR="/etc/nginx/modules-available"
        fi
        
        if [ -d "$SRC_DIR" ]; then
          for f in "$SRC_DIR"/*.conf; do
            if [ -f "$f" ]; then
              SO_PATH=$(awk '/load_module/ {gsub(/[";]/, "", $2); print $2}' "$f")
              if [ -n "$SO_PATH" ]; then
                case "$SO_PATH" in
                  /*) ;;
                  *) SO_PATH="/usr/lib/nginx/$SO_PATH" ;;
                esac
                if [ -f "$SO_PATH" ]; then
                  ln -sf "$f" "/etc/nginx/modules-enabled/$(basename "$f")"
                fi
              fi
            fi
          done
        fi
    - require:
      - cmd: restore_nginx_core

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
    - require:
      - cmd: restore_nginx_modules

/etc/nginx/sites-enabled:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - require:
      - cmd: restore_nginx_modules

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
    - require:
      - cmd: restore_nginx_modules

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
