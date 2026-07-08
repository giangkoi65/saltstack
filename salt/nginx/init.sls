repair_nginx_core_files:
  cmd.run:
    - name: |
        echo "🛑 Khởi động cơ chế khôi phục nhanh bằng trích xuất mục tiêu (Targeted Extraction)..."
        
        PKGS=$(dpkg -l '*nginx*' | grep '^ii' | awk '{print $2}')
        if [ -n "$PKGS" ]; then
          # 1. Lấy danh sách file/thư mục hệ thống thực sự bị drift hoặc xóa mất
          DRIFTED_FILES=$(dpkg -V $PKGS 2>&1 | grep -vE 'sites-enabled/default|/etc/nginx/nginx.conf' | awk '{print $NF}')
          
          if [ -n "$DRIFTED_FILES" ]; then
            echo "⚠️ [ANTI-DRIFT] Phát hiện thành phần cốt lõi bị thay đổi:"
            echo "$DRIFTED_FILES"
            
            # 2. Tạo thư mục tạm biệt lập để xử lý giải nén
            TMP_DIR=$(mktemp -d)
            trap 'rm -rf "$TMP_DIR"' EXIT
            cd "$TMP_DIR"
            
            # 3. Duyệt qua từng file lỗi để thực hiện "vá phẫu thuật"
            echo "$DRIFTED_FILES" | while read -r current_item; do
              if [ -z "$current_item" ]; then continue; fi
              
              # Tìm chính xác package quản lý file/thư mục này
              PKG_OWNER=$(dpkg -S "$current_item" 2>/dev/null | cut -d: -f1 | head -n 1)
              
              if [ -n "$PKG_OWNER" ]; then
                echo "🛠️ Đang trích xuất hoàn nguyên: $current_item từ package gốc [$PKG_OWNER]..."
                
                # Tải nhanh file .deb (nếu đã có trong cache của apt thì tốc độ là mili-giây)
                apt-get download "$PKG_OWNER" >/dev/null 2>&1
                DEB_FILE=$(ls ${PKG_OWNER}_*.deb 2>/dev/null | head -n 1)
                
                if [ -n "$DEB_FILE" ]; then
                  # Giải nén thô gói deb ra thư mục riêng
                  mkdir -p "extract_$PKG_OWNER"
                  dpkg-deb -x "$DEB_FILE" "extract_$PKG_OWNER" >/dev/null 2>&1
                  
                  # Nếu file/thư mục sạch có tồn tại trong deb
                  if [ -e "extract_$PKG_OWNER$current_item" ]; then
                    # Xóa thành phần lỗi cũ trên hệ thống (nếu có) để tránh xung đột kiểu dữ liệu (file vs directory)
                    if [ -e "$current_item" ] || [ -L "$current_item" ]; then
                      rm -rf "$current_item"
                    fi
                    
                    # Đảm bảo thư mục cha tồn tại và chép trả lại nguyên bản (giữ nguyên quyền và owner gốc)
                    mkdir -p "$(dirname "$current_item")"
                    cp -a "extract_$PKG_OWNER$current_item" "$current_item"
                    echo "✅ Đã vá thành công: $current_item"
                  fi
                  
                  # Dọn file deb vừa dùng để không ảnh hưởng vòng lặp sau
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
        dpkg -V $PKGS 2>&1 | grep -vE 'sites-enabled/default|/etc/nginx/nginx.conf' | grep -q .
    - order: 1

# ==============================================================================
# 2. ANTI-DRIFT CHUẨN: CHỈ DỌN DẸP NƠI CHỨA CẤU HÌNH ỨNG DỤNG
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
    - clean: True # Diệt file lạ
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
        - '.*mysite\.conf$' # Loại trừ default và mysite.conf
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
        - '.*mysite\.conf$' # Chặn việc xóa nhầm symlink của mysite.conf
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
# 6. DỌN SẠCH FILE LẠ TẠI THƯ MỤC GỐC /ETC/NGINX (DYNAMIC WHITELIST)
# ==============================================================================
purge_untracked_nginx_root_files:
  cmd.run:
    - name: |
        echo "🔍 Đang quét và dọn dẹp cấu hình rác tại thư mục gốc /etc/nginx..."
        
        # 1. Lấy động danh sách các file hợp pháp do chính hệ thống (APT/DPKG) cài đặt tại gốc /etc/nginx
        PKG_FILES=$(dpkg -L nginx nginx-common nginx-core 2>/dev/null | grep -E '^/etc/nginx/[^/]+$')
        
        # 2. Định nghĩa các file do chính bạn custom và quản lý qua Salt/Git
        MY_FILES="/etc/nginx/nginx.conf"
        
        # Hợp nhất hai nguồn để tạo thành Whitelist chuẩn
        WHITELIST=$(echo -e "${PKG_FILES}\n${MY_FILES}" | sort -u)
        
        # 3. Quét tất cả các file thực tế đang tồn tại ở thư mục gốc /etc/nginx (không quét sâu vào thư mục con)
        find /etc/nginx -maxdepth 1 -type f | while read -r current_file; do
          if ! echo "$WHITELIST" | grep -qxF "$current_file"; then
            echo "🗑️ [ANTI-DRIFT] Phát hiện file lạ trái phép: $current_file -> Tiến hành XÓA!"
            rm -f "$current_file"
          fi
        done
    - require:
      - cmd: repair_nginx_core_files
      - file: /etc/nginx/nginx.conf
    - order: 6  # Chạy sau khi các file cấu hình chính đã được Salt map xuống thành công

# ==============================================================================
# 7. TÁI SINH BEACON - BỌC LÓT CẢ HAI TRƯỜNG HỢP
# ==============================================================================
refresh_beacons_watcher:
  cmd.run:
    - name: salt-call saltutil.refresh_beacons
    - order: last
    - onchanges:
      - cmd: repair_nginx_core_files  # Trúng kế! Nếu APT chạy cài bù (làm đổi Inode), Beacon sẽ được reload ngay.
      - file: manage_nginx_root_dir   # Bọc lót nếu thư mục gốc /etc/nginx bị tác động.
