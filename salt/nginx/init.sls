# ==============================================================================
# 1. TỰ ĐỘNG KHÔI PHỤC KHI CẤU HÌNH NGINX BỊ LỖI CÚ PHÁP HOẶC MẤT FILE CORE
# ==============================================================================
disable_apt_restart:
  cmd.run:
    - name: |
        echo "exit 101" > /usr/sbin/policy-rc.d
        chmod +x /usr/sbin/policy-rc.d
    # 🔥 CHẠY KHI: Cấu hình Nginx lỗi (nginx -t trả về lỗi) HOẶC file core mime.types bị mất
    - unless: nginx -t && [ -f /etc/nginx/mime.types ]
    - order: 1

restore_nginx_core:
  cmd.run:
    - name: apt-get install --reinstall -o Dpkg::Options::="--force-confmiss" -y nginx nginx-common
    - unless: nginx -t && [ -f /etc/nginx/mime.types ]
    - require:
      - cmd: disable_apt_restart

restore_nginx_modules:
  cmd.run:
    - name: |
        echo "Dọn dẹp file rác và nối lại modules sạch..."
        # Xóa file lỗi *.conf nếu có
        rm -f /etc/nginx/modules-enabled/*.conf 2>/dev/null
        rm -f /etc/nginx/modules-enabled/\*.conf 2>/dev/null
        
        # Tạo lại liên kết chuẩn
        for target_dir in /usr/share/nginx/modules-available /etc/nginx/modules-available; do
          if [ -d "$target_dir" ]; then
            for file in "$target_dir"/*.conf; do
              if [ -e "$file" ]; then ln -sf "$file" /etc/nginx/modules-enabled/; fi
            done
          fi
        done
    - unless: nginx -t
    - require:
      - cmd: restore_nginx_core

enable_apt_restart:
  cmd.run:
    - name: rm -f /usr/sbin/policy-rc.d
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

/etc/nginx/sites-available/mysite.conf:
  file.managed:
    - source: salt://nginx/files/mysite.conf.jinja
    - template: jinja
    - user: root
    - group: root
    - mode: 644

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
