# ==============================================================================
# 1. CHẶN APT RESTART VÀ HOÀN NGUYÊN CORE CỦA HỆ THỐNG
# ==============================================================================
# Tạo khiên chặn: Ép các gói cài đặt của Ubuntu/Debian không được tự ý khởi động lại dịch vụ
disable_apt_restart:
  cmd.run:
    - name: |
        echo "exit 101" > /usr/sbin/policy-rc.d
        chmod +x /usr/sbin/policy-rc.d
    - order: 1

restore_nginx_core:
  cmd.run:
    - name: apt-get install --reinstall -o Dpkg::Options::="--force-confmiss" -y nginx nginx-common
    - require:
      - cmd: disable_apt_restart

# Tháo khiên: Trả lại trạng thái bình thường cho APT sau khi đã sửa xong core
enable_apt_restart:
  cmd.run:
    - name: rm -f /usr/sbin/policy-rc.d
    - require:
      - cmd: restore_nginx_core

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