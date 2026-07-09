# ==============================================================================
# 1. ĐẢM BẢO GÓI NGINX LUÔN ĐƯỢC CÀI ĐẶT
# ==============================================================================
install_nginx_packages:
  pkg.installed:
    - name: nginx
    - order: 1

# ==============================================================================
# 2. SIÊU LÁ CHẮN DYNAMIC ANTI-DRIFT (CHỐNG SỬA/XÓA/THÊM FILE LẠ)
# ==============================================================================
repair_and_purge_nginx_drift:
  cmd.run:
    - name: |
        echo "🔍 Bắt đầu quét kiểm tra tính toàn vẹn của toàn bộ /etc/nginx..."
        PKG_DEB=$(ls -1 /var/cache/apt/archives/nginx-common_*.deb 2>/dev/null | head -n 1)
        if [ -z "$PKG_DEB" ]; then
          apt-get download nginx-common >/dev/null 2>&1
          PKG_DEB=$(ls -1 nginx-common_*.deb | head -n 1)
        fi

        CORE_FILES=(
          "etc/nginx/fastcgi.conf" "etc/nginx/fastcgi_params" "etc/nginx/koi-utf" 
          "etc/nginx/koi-win" "etc/nginx/mime.types" "etc/nginx/proxy_params" 
          "etc/nginx/scgi_params" "etc/nginx/uwsgi_params" "etc/nginx/win-utf"
          "etc/nginx/snippets/fastcgi-php.conf" "etc/nginx/snippets/snakeoil.conf"
        )
        
        for file_rel in "${CORE_FILES[@]}"; do
          full_path="/$file_rel"
          if [ ! -f "$full_path" ] || [ "$(stat -c '%U:%G' $full_path)" != "root:root" ]; then
            echo "🩹 [REPAIR] Vá khẩn cấp file hệ thống: $full_path"
            dpkg-deb --fsys-tarfile "$PKG_DEB" | tar -xOf - "./$file_rel" > "$full_path" 2>/dev/null || true
            chown root:root "$full_path"
            chmod 644 "$full_path"
          fi
        done

        dpkg-deb --fsys-tarfile "$PKG_DEB" | tar -xC / ./etc/nginx/modules-available/ 2>/dev/null || true

        if [ -f /var/lib/dpkg/info/nginx-common.postinst ]; then
          echo "🔄 [REPAIR] Đang tái tạo các liên kết module hệ thống..."
          /var/lib/dpkg/info/nginx-common.postinst configure >/dev/null 2>&1 || true
        fi

        WHITELIST=$(dpkg -L nginx-common nginx-core nginx 2>/dev/null | grep '^/etc/nginx')
        WHITELIST+=$'\n'"/etc/nginx/sites-available/mysite.conf"
        WHITELIST+=$'\n'"/etc/nginx/sites-enabled/mysite.conf"
        WHITELIST+=$'\n'"/etc/nginx/sites-available/default"

        find /etc/nginx -type f -o -type l | while read -r file; do
          if [[ "$file" =~ \.dpkg- ]]; then continue; fi
          if [[ "$file" =~ /etc/nginx/modules-enabled/ ]] && [ -L "$file" ]; then continue; fi
          if ! echo "$WHITELIST" | grep -qxF "$file"; then
            echo "🔥 [SECURITY] Phát hiện và tiêu diệt file/symlink trái phép: $file"
            rm -f "$file"
          fi
        done

        find /etc/nginx -mindepth 1 -type d -empty ! -path "/etc/nginx/conf.d" -delete
        rm -f nginx-common_*.deb
    - shell: /bin/bash
    - order: 2
    - require:
      - pkg: install_nginx_packages

# ==============================================================================
# 3. ĐẢM BẢO QUYỀN VÀ TRẠNG THÁI CÁC THƯ MỤC TRỤC CỐT
# ==============================================================================
/etc/nginx:
  file.directory:
    - user: root
    - group: root
    - mode: 755

/etc/nginx/conf.d:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

/etc/nginx/modules-enabled:
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

# ==============================================================================
# 3.5. QUẢN LÝ THƯ MỤC WEB APP VÀ ASSETS (VÁ LỖI BEACON CHẾT ẨN)
# ==============================================================================
/var/www/mysite:
  file.directory:
    - user: www-data
    - group: www-data
    - mode: 755
    - makedirs: True

/var/www/mysite/index.html:
  file.managed:
    - source: salt://nginx/files/index.html
    - user: www-data
    - group: www-data
    - mode: 644
    - require:
      - file: /var/www/mysite

# ==============================================================================
# 4. QUẢN LÝ FILE CONFIG TRỤC CỐT CỦA APP
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
# 5. KIỂM TRA CÚ PHÁP & RE-LOAD KHÔNG DOWNTIME
# ==============================================================================
check_nginx_config_syntax:
  cmd.run:
    - name: nginx -t
    - onchanges:
      - file: /etc/nginx/nginx.conf
      - file: /etc/nginx/sites-available/mysite.conf
      - file: /etc/nginx/sites-enabled/mysite.conf

nginx_running_service:
  service.running:
    - name: nginx
    - enable: True
    - reload: True
    - require:
      - cmd: check_nginx_config_syntax
    - watch:
      - file: /etc/nginx/nginx.conf
      - file: /etc/nginx/sites-available/mysite.conf
      - file: /etc/nginx/sites-enabled/mysite.conf