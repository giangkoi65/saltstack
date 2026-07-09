# ==============================================================================
# 1. ĐẢM BẢO GÓI NGINX LUÔN ĐƯỢC CÀI ĐẶT
# ==============================================================================
install_nginx_packages:
  pkg.installed:
    - name: nginx
    - order: 1

# ==============================================================================
# 2. SIÊU LÁ CHẮN DYNAMIC ANTI-DRIFT (CẬP NHẬT: PHỤC HỒI ĐỘNG SYMLINK MODULES)
# ==============================================================================
repair_and_purge_nginx_drift:
  cmd.run:
    - name: |
        echo "🔍 Kiểm tra tính toàn vẹn và nội dung của /etc/nginx..."
        CORE_FILES=(
          "etc/nginx/fastcgi.conf" "etc/nginx/fastcgi_params" "etc/nginx/koi-utf" 
          "etc/nginx/koi-win" "etc/nginx/mime.types" "etc/nginx/proxy_params" 
          "etc/nginx/scgi_params" "etc/nginx/uwsgi_params" "etc/nginx/win-utf"
          "etc/nginx/snippets/fastcgi-php.conf" "etc/nginx/snippets/snakeoil.conf"
        )
        
        NEED_REPAIR=0
        for file_rel in "${CORE_FILES[@]}"; do
          full_path="/$file_rel"
          if [ ! -f "$full_path" ] || [ "$(stat -c '%U:%G' $full_path)" != "root:root" ]; then
            NEED_REPAIR=1
            break
          fi
          
          if [ -f /var/lib/dpkg/info/nginx-common.md5sums ]; then
            EXPECTED_MD5=$(grep -E "^[0-9a-f]{32}  $file_rel$" /var/lib/dpkg/info/nginx-common.md5sums | awk '{print $1}')
            if [ -n "$EXPECTED_MD5" ]; then
              CURRENT_MD5=$(md5sum "$full_path" | awk '{print $1}')
              if [ "$CURRENT_MD5" != "$EXPECTED_MD5" ]; then
                echo "⚠️ [DRIFT DETECTED] File bị thay đổi nội dung: $full_path"
                NEED_REPAIR=1
                break
              fi
            fi
          fi
        done

        # KIỂM TRA BỔ SUNG: Nếu thư mục modules-enabled trống rỗng, ép buộc kích hoạt khôi phục
        if [ -d /etc/nginx/modules-enabled ] && [ -z "$(ls -A /etc/nginx/modules-enabled 2>/dev/null)" ]; then
          echo "⚠️ [DRIFT DETECTED] Thư mục modules-enabled bị trống, cần nạp lại symlink."
          NEED_REPAIR=1
        fi

        if [ $NEED_REPAIR -eq 1 ]; then
          echo "🩹 [REPAIR] Tiến hành khôi phục lại toàn bộ file hệ thống từ gói gốc..."
          PKG_DEB=$(ls -1 /var/cache/apt/archives/nginx-common_*.deb 2>/dev/null | head -n 1)
          if [ -z "$PKG_DEB" ]; then
            apt-get download nginx-common >/dev/null 2>&1
            PKG_DEB=$(ls -1 nginx-common_*.deb | head -n 1)
          fi
          
          for file_rel in "${CORE_FILES[@]}"; do
            full_path="/$file_rel"
            mkdir -p "$(dirname "$full_path")"
            dpkg-deb --fsys-tarfile "$PKG_DEB" | tar -xOf - "./$file_rel" > "$full_path" 2>/dev/null || true
            chown root:root "$full_path"
            chmod 644 "$full_path"
          done
          
          mkdir -p /etc/nginx/modules-available
          dpkg-deb --fsys-tarfile "$PKG_DEB" | tar -xC / ./etc/nginx/modules-available/ 2>/dev/null || true
          
          if [ -f /var/lib/dpkg/info/nginx-common.postinst ]; then
            /var/lib/dpkg/info/nginx-common.postinst configure >/dev/null 2>&1 || true
          fi

          # 🔥 CƠ CHẾ KHÔI PHỤC MODULE: Tìm tất cả các gói module đã cài và ép tái tạo lại symlink gốc
          dpkg -l | grep -E '^ii  libnginx-mod-' | awk '{print $2}' | while read -r pkg; do
            if [ -f "/var/lib/dpkg/info/$pkg.postinst" ]; then
              echo "🔗 [MODULE REPAIR] Đang tái tạo cấu hình liên kết cho: $pkg"
              /var/lib/dpkg/info/$pkg.postinst configure >/dev/null 2>&1 || true
            fi
          done
          
          rm -f nginx-common_*.deb
        else
          echo "✅ Tất cả các file hệ thống đều toàn vẹn."
        fi

        # Dọn dẹp file lạ bừa bãi không nằm trong whitelist
        WHITELIST=$(dpkg -L nginx-common nginx-core nginx 2>/dev/null | grep '^/etc/nginx')
        WHITELIST+=$'\n'"/etc/nginx/sites-available/mysite.conf"
        WHITELIST+=$'\n'"/etc/nginx/sites-enabled/mysite.conf"

        find /etc/nginx -type f -o -type l | while read -r file; do
          if [[ "$file" == *.dpkg-* ]]; then continue; fi
          
          # 🔥 SỬA ĐỔI: Sử dụng String Prefix Matching bảo vệ tuyệt đối nội dung bên trong modules-enabled
          if [[ "$file" == "/etc/nginx/modules-enabled/"* ]]; then continue; fi
          
          if ! echo "$WHITELIST" | grep -qxF "$file"; then
            echo "🔥 [SECURITY] Tiêu diệt file trái phép: $file"
            rm -f "$file"
          fi
        done

        # Loại trừ các thư mục rỗng trục cốt không được xóa
        find /etc/nginx -mindepth 1 -type d -empty \
          ! -path "/etc/nginx/conf.d" \
          ! -path "/etc/nginx/sites-available" \
          ! -path "/etc/nginx/sites-enabled" \
          ! -path "/etc/nginx/modules-available" \
          ! -path "/etc/nginx/modules-enabled" \
          ! -path "/etc/nginx/snippets" -delete
    - shell: /bin/bash
    - order: 2
    - require:
      - pkg: install_nginx_packages

# ==============================================================================
# 3. QUẢN LÝ ĐỒNG BỘ TOÀN BỘ THƯ MỤC TRỤC CỐT (ĐÃ KHỚP ĐỦ THEO TREE)
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

/etc/nginx/snippets:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

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

/etc/nginx/modules-available:
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

# VÁ ĐIỂM MÙ 2: Xóa triệt để file cấu hình mặc định không dùng tới để dọn sạch hệ thống
/etc/nginx/sites-available/default:
  file.absent

# ==============================================================================
# 4. QUẢN LÝ FILE CONFIG TRỤC CỐT CỦA CƠ SỞ DỮ LIỆU GITOPS
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
      - file: /etc/nginx/sites-available/mysite.conf
      - file: /etc/nginx/sites-enabled

# ==============================================================================
# 5. KIỂM TRA CÚ PHÁP & RE-LOAD AN TOÀN CHO NGƯỜI DÙNG WEB
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