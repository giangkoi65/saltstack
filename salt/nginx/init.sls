# ==============================================================================
# 1. PHẪU THUẬT HOÀN NGUYÊN FILE HỆ THỐNG (TARGETED EXTRACTION)
# ==============================================================================
repair_nginx_core_files:
  cmd.run:
    - name: |
        echo "🛑 Khởi động cơ chế khôi phục nhanh bằng trích xuất mục tiêu..."
        
        PKGS=$(dpkg -l '*nginx*' | grep '^ii' | awk '{print $2}')
        if [ -n "$PKGS" ]; then
          # 🔥 CẢI TIẾN: Thêm sites-available/default vào bộ lọc loại trừ để tránh xung đột
          DRIFTED_FILES=$(dpkg -V $PKGS 2>&1 | grep -vE 'sites-enabled/default|sites-available/default|/etc/nginx/nginx.conf' | awk '{print $NF}')
          
          if [ -n "$DRIFTED_FILES" ]; then
            echo "⚠️ [ANTI-DRIFT] Phát hiện thành phần cốt lõi bị thay đổi: $DRIFTED_FILES"
            
            TMP_DIR=$(mktemp -d)
            trap 'rm -rf "$TMP_DIR"' EXIT
            cd "$TMP_DIR"
            
            echo "$DRIFTED_FILES" | while read -r current_item; do
              if [ -z "$current_item" ]; then continue; fi
              
              PKG_OWNER=$(dpkg -S "$current_item" 2>/dev/null | cut -d: -f1 | head -n 1)
              if [ -n "$PKG_OWNER" ]; then
                echo "🛠️ Đang trích xuất hoàn nguyên: $current_item từ package gốc [$PKG_OWNER]..."
                apt-get download "$PKG_OWNER" >/dev/null 2>&1
                DEB_FILE=$(ls ${PKG_OWNER}_*.deb 2>/dev/null | head -n 1)
                
                if [ -n "$DEB_FILE" ]; then
                  mkdir -p "extract_$PKG_OWNER"
                  dpkg-deb -x "$DEB_FILE" "extract_$PKG_OWNER" >/dev/null 2>&1
                  
                  if [ -e "extract_$PKG_OWNER$current_item" ]; then
                    if [ -e "$current_item" ] || [ -L "$current_item" ]; then rm -rf "$current_item"; fi
                    mkdir -p "$(dirname "$current_item")"
                    cp -a "extract_$PKG_OWNER$current_item" "$current_item"
                    echo "✅ Đã vá thành công: $current_item"
                  fi
                  rm -f "$DEB_FILE"
                fi
              fi
            done
            echo "✨ Toàn bộ file core đã được đưa về trạng thái nguyên bản sạch sẽ!"
          else
            echo "✅ Cấu hình core sạch sẽ, không phát hiện drift. Bỏ qua!"
          fi
        fi
    - onlyif: |
        PKGS=$(dpkg -l '*nginx*' | grep '^ii' | awk '{print $2}')
        # 🔥 ĐỒNG BỘ: Bộ lọc onlyif cũng phải loại trừ sites-available/default
        dpkg -V $PKGS 2>&1 | grep -vE 'sites-enabled/default|sites-available/default|/etc/nginx/nginx.conf' | grep -q .
    - order: 1

# ==============================================================================
# 2. ĐẢM BẢO CẤU TRÚC THƯ MỤC CỐT LÕI (LOẠI BỎ CLEAN=TRUE)
# ==============================================================================
manage_nginx_root_dir:
  file.directory:
    - name: /etc/nginx
    - user: root
    - group: root
    - mode: 755
    - require:
      - cmd: repair_nginx_core_files

/etc/nginx/conf.d:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - require:
      - file: manage_nginx_root_dir

/etc/nginx/modules-enabled:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - require:
      - file: manage_nginx_root_dir

/etc/nginx/sites-available:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - require:
      - file: manage_nginx_root_dir

/etc/nginx/sites-enabled:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - require:
      - file: manage_nginx_root_dir

nginx_package:
  pkg.installed:
    - name: nginx
    - require:
      - cmd: repair_nginx_core_files

# ==============================================================================
# 3. QUẢN LÝ CONFIG TRỤC CỐT DƯỚI DẠNG TEMPLATE JINJA
# ==============================================================================
/etc/nginx/nginx.conf:
  file.managed:
    - source: salt://nginx/files/nginx.conf.jinja
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - require:
      - pkg: nginx_package
      - file: manage_nginx_root_dir

# ==============================================================================
# 4. QUẢN LÝ APP/SITE CONFIGURATION
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
# 5. ĐIỀU KHIỂN TIẾN TRÌNH DỊCH VỤ
# ==============================================================================
nginx_service:
  service.running:
    - name: nginx
    - enable: True
    - sig: /usr/sbin/nginx
    - watch:
        - file: /etc/nginx/nginx.conf
        - file: /etc/nginx/sites-available/mysite.conf
        - file: /etc/nginx/sites-enabled/mysite.conf

# ==============================================================================
# 6. UNIFIED DYNAMIC PURGE - QUÉT SẠCH TOÀN DIỆN FILE LẠ BẰNG WHITELIST BASH
# ==============================================================================
purge_untracked_nginx_files:
  cmd.run:
    - name: |
        echo "🔍 Đang tiến hành dọn dẹp cấu hình rác Nginx toàn diện..."
        
        # --- THƯ MỤC GỐC /etc/nginx ---
        PKG_FILES=$(dpkg -L nginx nginx-common nginx-core 2>/dev/null | grep -E '^/etc/nginx/[^/]+$')
        MY_FILES="/etc/nginx/nginx.conf"
        WHITELIST_ROOT=$(echo -e "${PKG_FILES}\n${MY_FILES}" | sort -u)
        
        find /etc/nginx -maxdepth 1 -type f | while read -r current_file; do
          if ! echo "$WHITELIST_ROOT" | grep -qxF "$current_file"; then
            echo "🗑️ [ANTI-DRIFT] Xóa file lạ tại thư mục gốc: $current_file"
            rm -f "$current_file"
          fi
        done

        # --- THƯ MỤC sites-available ---
        # Chỉ cho phép file 'default' sạch của hệ thống và 'mysite.conf' của GitOps
        find /etc/nginx/sites-available -maxdepth 1 -type f | while read -r current_file; do
          bname=$(basename "$current_file")
          if [ "$bname" != "default" ] && [ "$bname" != "mysite.conf" ]; then
            echo "🗑️ [ANTI-DRIFT] Xóa file vhost lạ: $current_file"
            rm -f "$current_file"
          fi
        done

        # --- THƯ MỤC sites-enabled ---
        # Chỉ cho phép duy nhất symlink 'mysite.conf' hoạt động
        find /etc/nginx/sites-enabled -maxdepth 1 -type l -o -type f | while read -r current_file; do
          bname=$(basename "$current_file")
          if [ "$bname" != "mysite.conf" ]; then
            echo "🗑️ [ANTI-DRIFT] Xóa symlink/file kích hoạt trái phép: $current_file"
            rm -f "$current_file"
          fi
        done
    - require:
      - file: /etc/nginx/nginx.conf
      - file: /etc/nginx/sites-enabled/mysite.conf
    - order: 6

# ==============================================================================
# 7. TÁI SINH BEACON
# ==============================================================================
refresh_beacons_watcher:
  cmd.run:
    - name: salt-call saltutil.refresh_beacons
    - order: last
    - onchanges:
      - cmd: repair_nginx_core_files
      - file: manage_nginx_root_dir
