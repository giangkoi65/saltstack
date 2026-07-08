# ==============================================================================
# 1. KHÔI PHỤC TOÀN VẸN TUYỆT ĐỐI BẰNG ĐỐI CHIẾU MD5 (STRICT INTEGRITY CHECK)
# ==============================================================================
repair_nginx_core_files:
  cmd.run:
    - name: |
        echo "🛑 Khóa tiến trình restart của APT..."
        echo "exit 101" > /usr/sbin/policy-rc.d
        chmod +x /usr/sbin/policy-rc.d

        PKGS=$(dpkg -l '*nginx*' | grep '^ii' | awk '{print $2}')
        DRIFTED_FILES=""

        if [ -n "$PKGS" ]; then
          echo "🔍 Khởi động máy quét MD5 đối chiếu cơ sở dữ liệu DPKG..."
          
          # Quét tất cả file thuộc package Nginx đăng ký trong hệ thống để tìm nội dung bị sửa đổi hoặc mất (ATTRIB, CLOSE_WRITE, DELETE)
          for pkg in $PKGS; do
            MD5_SUMS_FILE="/var/lib/dpkg/info/${pkg}.md5sums"
            if [ -f "$MD5_SUMS_FILE" ]; then
              while read -r target_md5 target_file; do
                # Chỉ tập trung bảo vệ khu vực /etc/nginx
                if [[ "$target_file" == etc/nginx/* ]]; then
                  full_path="/$target_file"
                  
                  # Loại trừ các file vhost động hoặc file do Salt quản lý trực tiếp
                  if [[ "$full_path" == "/etc/nginx/nginx.conf" || "$full_path" == "/etc/nginx/sites-enabled/"* || "$full_path" == "/etc/nginx/sites-available/mysite.conf" ]]; then
                    continue
                  fi

                  # Trường hợp 1: File bị xóa hoặc mất (DELETE, MOVED_FROM)
                  if [ ! -f "$full_path" ]; then
                    echo "⚠️ [DRIFT-DETECT] File bị mất: $full_path"
                    DRIFTED_FILES="$DRIFTED_FILES $full_path"
                  else
                    # Trường hợp 2: File bị thay đổi nội dung (CLOSE_WRITE, MOVED_TO)
                    current_md5=$(md5sum "$full_path" | awk '{print $1}')
                    if [ "$current_md5" != "$target_md5" ]; then
                      echo "⚠️ [DRIFT-DETECT] File bị thay đổi nội dung: $full_path"
                      DRIFTED_FILES="$DRIFTED_FILES $full_path"
                    fi
                  fi
                fi
              done < "$MD5_SUMS_FILE"
            fi
          done

          # Giải quyết triệt để ATTRIB (Sai lệch quyền sở hữu / Chmod / Chown)
          # Đảm bảo toàn bộ cấu hình thuộc về root:root để hacker không thể chèn mã độc
          find /etc/nginx -not -user root -o -not -group root | while read -r bad_perm_file; do
             echo "⚠️ [DRIFT-DETECT] Sai lệch quyền hạn (ATTRIB): $bad_perm_file"
             chown root:root "$bad_perm_file"
          done
          
          # Triển khai vá lỗi và hoàn nguyên bằng Reinstall
          if [ -n "$DRIFTED_FILES" ]; then
            echo "🧹 Tiến hành dọn dẹp các thành phần lỗi: $DRIFTED_FILES"
            echo "$DRIFTED_FILES" | xargs rm -f
            
            echo "📦 Cài bù hoàn nguyên file sạch từ Package gốc..."
            apt-get install --reinstall -o Dpkg::Options::="--force-confmiss" -y $PKGS
          else
            echo "✅ Toàn bộ cấu hình hệ thống core sạch sẽ, khớp MD5 gốc!"
          fi
        fi

        echo "🔓 Mở khóa policy-rc.d..."
        rm -f /usr/sbin/policy-rc.d
    - onlyif: |
        # Kịch bản check thông minh để trigger lệnh chạy
        PKGS=$(dpkg -l '*nginx*' | grep '^ii' | awk '{print $2}')
        for pkg in $PKGS; do
          MD5_SUMS_FILE="/var/lib/dpkg/info/${pkg}.md5sums"
          if [ -f "$MD5_SUMS_FILE" ]; then
            while read -r target_md5 target_file; do
              if [[ "$target_file" == etc/nginx/* ]]; then
                full_path="/$target_file"
                if [[ "$full_path" == "/etc/nginx/nginx.conf" || "$full_path" == "/etc/nginx/sites-enabled/"* || "$full_path" == "/etc/nginx/sites-available/mysite.conf" ]]; then
                  continue
                fi
                if [ ! -f "$full_path" ]; then exit 0; fi
                current_md5=$(md5sum "$full_path" | awk '{print $1}')
                if [ "$current_md5" != "$target_md5" ]; then exit 0; fi
              fi
            done < "$MD5_SUMS_FILE"
          fi
        done
        # Check thêm quyền sở hữu (ATTRIB)
        if [ $(find /etc/nginx -not -user root -o -not -group root | wc -l) -gt 0 ]; then exit 0; fi
        exit 1
    - order: 1

# ==============================================================================
# 2. KHÓA CHẶT THƯ MỤC CẤU HÌNH VÀ DIỆT FILE LẠ (DÙNG CLEAN: TRUE KHÔN NGOAN)
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
    - clean: True
    - require:
      - file: manage_nginx_root_dir

/etc/nginx/modules-enabled:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - clean: True
    - require:
      - file: manage_nginx_root_dir

/etc/nginx/sites-available:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - clean: True 
    - exclude_pat:
        - '.*default$'
        - '.*mysite\.conf$'
    - require:
      - file: manage_nginx_root_dir

/etc/nginx/sites-enabled:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - clean: True 
    - exclude_pat:
        - '.*mysite\.conf$'
    - require:
      - file: manage_nginx_root_dir

nginx_package:
  pkg.installed:
    - name: nginx
    - require:
      - cmd: repair_nginx_core_files

# ==============================================================================
# 3. QUẢN LÝ FILE TRỤC CỐT (ĐẢM BẢO SỬA LÀ GHI ĐÈ NGAY)
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
# 4. ỨNG PHÓ SỰ KIỆN: QUÉT SẠCH THƯ MỤC RÁC THỪA (VÍ DỤ: HACKER TẠO THƯ MỤC MỚI)
# ==============================================================================
purge_untracked_nginx_root_files:
  cmd.run:
    - name: |
        echo "🔍 Đang rà quét và quét sạch mọi thành phần lạ tại /etc/nginx..."
        PKG_FILES=$(dpkg -L nginx nginx-common nginx-core 2>/dev/null)
        
        # Tạo danh sách trắng tuyệt đối cho toàn bộ cấu trúc tree /etc/nginx/
        WHITELIST=$(cat << EOF
        /etc/nginx
        /etc/nginx/nginx.conf
        /etc/nginx/sites-available/mysite.conf
        /etc/nginx/sites-enabled/mysite.conf
        EOF
        )
        ALL_WHITELIST=$(echo -e "${PKG_FILES}\n${WHITELIST}" | sort -u)

        # Sử dụng find để quét tất cả file và thư mục (gồm cả thư mục lạ hacker tạo ra)
        find /etc/nginx -mindepth 1 | sort -r | while read -r item; do
          # Bỏ qua các thư mục con đang được Salt quản lý trực tiếp bằng cơ chế clean: True
          if [[ "$item" == "/etc/nginx/conf.d"* || "$item" == "/etc/nginx/modules-enabled"* || "$item" == "/etc/nginx/sites-available"* || "$item" == "/etc/nginx/sites-enabled"* ]]; then
            continue
          fi
          
          # Nếu không nằm trong Whitelist -> Tiêu diệt triệt để
          if ! echo "$ALL_WHITELIST" | grep -qxF "$item"; then
            echo "🗑️ [ANTI-DRIFT] Xóa thành phần lạ: $item"
            rm -rf "$item"
          fi
        done
    - require:
      - cmd: repair_nginx_core_files
      - file: /etc/nginx/nginx.conf
    - order: 6

# ==============================================================================
# 5. KHỞI ĐỘNG DỊCH VỤ VÀ WATCHER BEACONS
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
    - sig: /usr/sbin/nginx
    - watch:
        - file: /etc/nginx/nginx.conf
        - file: /etc/nginx/sites-available/mysite.conf
        - file: /etc/nginx/sites-enabled/mysite.conf

refresh_beacons_watcher:
  cmd.run:
    - name: salt-call saltutil.refresh_beacons
    - order: last
    - onchanges:
      - cmd: repair_nginx_core_files
      - file: manage_nginx_root_dir
