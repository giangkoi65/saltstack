# ==============================================================================
# 1. PHẪU THUẬT PHỤC HỒI FILE HỆ THỐNG GỐC (Bypass APT Reinstall hoàn toàn)
# ==============================================================================
repair_nginx_core_files:
  cmd.run:
    - name: |
        echo "🔍 Phát hiện sai lệch file hệ thống core. Tiến hành trích xuất vá lỗi..."
        # Lấy file deb gốc từ bộ nhớ cache hoặc tải nhanh về nếu bị xóa mất
        PKG_DEB=$(ls -1 /var/cache/apt/archives/nginx-common_*.deb 2>/dev/null | head -n 1)
        if [ -z "$PKG_DEB" ]; then
          apt-get download nginx-common >/dev/null 2>&1
          PKG_DEB=$(ls -1 nginx-common_*.deb | head -n 1)
        fi
        
        # Danh sách các file hệ thống cần bảo vệ nghiêm ngặt
        CORE_FILES=("etc/nginx/mime.types" "etc/nginx/fastcgi_params" "etc/nginx/uwsgi_params")
        
        for file_rel in "${CORE_FILES[@]}"; do
          full_path="/$file_rel"
          # Nếu file bị xóa hoặc bị chỉnh sửa nội dung
          if [ ! -f "$full_path" ] || [ "$(chown root:root $full_path)" ]; then
            echo "🩹 Đang vá khẩn cấp: $full_path"
            dpkg-deb --fsys-tarfile "$PKG_DEB" | tar -xOf - "./$file_rel" > "$full_path"
            chown root:root "$full_path"
            chmod 644 "$full_path"
          fi
        done
        
        # Dọn file vừa tải nếu có
        rm -f nginx-common_*.deb
    - onlyif: |
        # Chỉ chạy khi thực sự có file core hệ thống bị biến mất hoặc sai quyền root
        [ ! -f /etc/nginx/mime.types ] || [ ! -f /etc/nginx/fastcgi_params ] || [ $(find /etc/nginx -maxdepth 1 -not -user root -o -not -group root | wc -l) -gt 0 ]
    - order: 1

# ==============================================================================
# 2. KHÓA CHẶT THƯ MỤC VÀ DIỆT FILE LẠ
# ==============================================================================
manage_nginx_root_dir:
  file.directory:
    - name: /etc/nginx
    - user: root
    - group: root
    - mode: 755

/etc/nginx/conf.d:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - clean: True

/etc/nginx/sites-enabled:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - clean: True
    - exclude_pat:
        - '.*mysite\.conf$'

# ==============================================================================
# 3. QUẢN LÝ FILE CONFIG TRỤC CỐT (Đẩy trực tiếp từ GitFS)
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
# 4. CHỐNG ĐỨT GÃY DỊCH VỤ - ZERO DOWNTIME RELOAD SERVICE
# ==============================================================================
nginx_running_service:
  service.running:
    - name: nginx
    - enable: True
    - reload: True # 🔥 ĐIỀU KIỆN TIÊN QUYẾT: Dùng SIGHUP (Reload) thay vì Restart
    - watch:
      - cmd: repair_nginx_core_files
      - file: /etc/nginx/nginx.conf
      - file: /etc/nginx/sites-available/mysite.conf
      - file: /etc/nginx/sites-enabled/mysite.conf