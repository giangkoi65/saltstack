# ==============================================================================
# 1. CHẶN APT RESTART VÀ HOÀN NGUYÊN CORE CỦA HỆ THỐNG (CÓ ĐIỀU KIỆN CHẶN LOOP)
# ==============================================================================
disable_apt_restart:
  cmd.run:
    - name: |
        echo "exit 101" > /usr/sbin/policy-rc.d
        chmod +x /usr/sbin/policy-rc.d
    # 🔥 CHỈ CHẠY khi thực sự phát hiện mất file core (mime.types mất HOẶC thư mục modules bị trống)
    - onlyif: |
        [ ! -f /etc/nginx/mime.types ] || [ -z "$(ls -A /etc/nginx/modules-enabled 2>/dev/null)" ]
    - order: 1

restore_nginx_core:
  cmd.run:
    - name: apt-get install --reinstall -o Dpkg::Options::="--force-confmiss" -y nginx nginx-common
    - onlyif: |
        [ ! -f /etc/nginx/mime.types ] || [ -z "$(ls -A /etc/nginx/modules-enabled 2>/dev/null)" ]
    - require:
      - cmd: disable_apt_restart

# 🔥 SỬA LỖI MODULES: Tự động kéo lại các liên kết ảo sang module gốc nếu thư mục trống
restore_nginx_modules:
  cmd.run:
    - name: |
        echo "Đang khôi phục các liên kết modules ảo..."
        if [ -d /usr/share/nginx/modules-available ]; then
          ln -sf /usr/share/nginx/modules-available/*.conf /etc/nginx/modules-enabled/
        elif [ -d /etc/nginx/modules-available ]; then
          ln -sf /etc/nginx/modules-available/*.conf /etc/nginx/modules-enabled/
        fi
    - onlyif: '[ -z "$(ls -A /etc/nginx/modules-enabled 2>/dev/null)" ]'
    - require:
      - cmd: restore_nginx_core

enable_apt_restart:
  cmd.run:
    - name: rm -f /usr/sbin/policy-rc.d
    # Chỉ dọn dẹp policy nếu bước chặn phía trên thực sự có chạy
    - onchanges:
      - cmd: disable_apt_restart

remove_default_vhost:
  file.absent:
    - name: /etc/nginx/sites-enabled/default
    - require:
      - cmd: restore_nginx_core

# ==============================================================================
# 2. ÁP DỤNG CẤU HÌNH TÙY BIẾN TỪ TEMPLATE JINJA
# ==============================================================================
/etc/nginx/nginx.conf:
  file.managed:
    - source: salt://nginx/files/nginx.conf.jinja
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - require:
      - cmd: restore_nginx_core

/etc/nginx/sites-available/mysite.conf:
  file.managed:
    - source: salt://nginx/files/mysite.conf.jinja
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - require:
      - cmd: restore_nginx_core

/etc/nginx/sites-enabled/mysite.conf:
  file.symlink:
    - target: /etc/nginx/sites-available/mysite.conf
    - require:
      - file: /etc/nginx/sites-available/mysite.conf

# ==============================================================================
# 3. QUẢN LÝ MÃ NGUỒN VÀ DỊCH VỤ (ZERO DOWNTIME)
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
