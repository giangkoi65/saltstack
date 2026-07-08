# ==============================================================================
# 1. TỰ ĐỘNG PHÁT HIỆN VÀ HOÀN NGUYÊN TOÀN BỘ FILE CORE BỊ SAI LỆCH (ANY MASK)
# ==============================================================================
disable_apt_restart:
  cmd.run:
    - name: |
        echo "exit 101" > /usr/sbin/policy-rc.d
        chmod +x /usr/sbin/policy-rc.d
    # 🔥 THAY ĐỔI CỐT LÕI: Tự động quét toàn bộ /etc/nginx, bỏ qua các file bạn tự quản lý bằng template
    - onlyif: |
        dpkg --verify nginx nginx-common 2>/dev/null | grep '/etc/nginx/' | grep -Ev 'nginx.conf|mysite.conf|default' | grep -q .
    - order: 1

restore_nginx_core:
  cmd.run:
    - name: apt-get install --reinstall -o Dpkg::Options::="--force-confmiss" -y nginx nginx-common
    - onlyif: |
        dpkg --verify nginx nginx-common 2>/dev/null | grep '/etc/nginx/' | grep -Ev 'nginx.conf|mysite.conf|default' | grep -q .
    - require:
      - cmd: disable_apt_restart

# Khôi phục lại các liên kết ảo của module hệ thống nếu thư mục trống hoặc bị xóa mất
restore_nginx_modules:
  cmd.run:
    - name: |
        mkdir -p /etc/nginx/modules-enabled
        if [ -d /usr/share/nginx/modules-available ]; then
          ln -sf /usr/share/nginx/modules-available/*.conf /etc/nginx/modules-enabled/
        elif [ -d /etc/nginx/modules-available ]; then
          ln -sf /etc/nginx/modules-available/*.conf /etc/nginx/modules-enabled/
        fi
    - onlyif: '[ ! -d /etc/nginx/modules-enabled ] || [ -z "$(ls -A /etc/nginx/modules-enabled 2>/dev/null)" ]'
    - require:
      - cmd: restore_nginx_core

enable_apt_restart:
  cmd.run:
    - name: rm -f /usr/sbin/policy-rc.d
    - onchanges:
      - cmd: disable_apt_restart

# ==============================================================================
# 2. ĐẢM BẢO CẤU TRÚC THƯ MỤC LÀM VIỆC CỦA VHOST LUÔN TỒN TẠI
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
# 3. QUẢN LÝ CÁC FILE CẤU HÌNH TÙY BIẾN THEO TEMPLATE (GHI ĐÈ NẾU SAI LỆCH)
# ==============================================================================
# Salt tự động kiểm tra nội dung (close_write), quyền hạn (attrib), mất file (delete) cho các block này
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
# 4. QUẢN LÝ MÃ NGUỒN VÀ DỊCH VỤ (ZERO DOWNTIME)
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
