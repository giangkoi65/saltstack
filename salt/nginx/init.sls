# ==============================================================================
# 1. PHẪU THUẬT PHỤC HỒI FILE HỆ THỐNG GỐC
# ==============================================================================
repair_nginx_core_files:
  cmd.run:
    - name: |
        echo "🔍 Phát hiện sai lệch file hệ thống core. Tiến hành trích xuất vá lỗi..."
        PKG_DEB=$(ls -1 /var/cache/apt/archives/nginx-common_*.deb 2>/dev/null | head -n 1)
        if [ -z "$PKG_DEB" ]; then
          apt-get download nginx-common >/dev/null 2>&1
          PKG_DEB=$(ls -1 nginx-common_*.deb | head -n 1)
        fi
        
        CORE_FILES=("etc/nginx/mime.types" "etc/nginx/fastcgi_params" "etc/nginx/uwsgi_params")
        for file_rel in "${CORE_FILES[@]}"; do
          full_path="/$file_rel"
          if [ ! -f "$full_path" ] || [ "$(chown root:root $full_path)" ]; then
            dpkg-deb --fsys-tarfile "$PKG_DEB" | tar -xOf - "./$file_rel" > "$full_path"
            chown root:root "$full_path"
            chmod 644 "$full_path"
          fi
        done
        rm -f nginx-common_*.deb
    - onlyif: |
        [ ! -f /etc/nginx/mime.types ] || [ ! -f /etc/nginx/fastcgi_params ] || [ $(find /etc/nginx -maxdepth 1 -not -user root -o -not -group root | wc -l) -gt 0 ]
    - order: 1

# ==============================================================================
# 2. KHÓA CHẶT VÀ ĐẢM BẢO ĐỦ THƯ MỤC CẤU TRÚC NGINX
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

# 🔥 BỔ SUNG: Tránh lỗi "No such file or directory" của modules-enabled khi khởi động
/etc/nginx/modules-enabled:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - clean: True

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
    - clean: True
    - exclude_pat:
        - 'mysite.conf' # 🔥 SỬA: Salt dùng relative name để match trong clean, viết thế này sẽ không bị xóa nhầm

# ==============================================================================
# 3. QUẢN LÝ FILE CONFIG TRỤC CỐT
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
      - file: /etc/nginx/sites-enabled
      - file: /etc/nginx/sites-available/mysite.conf

# ==============================================================================
# 4. KIỂM TRA CÚ PHÁP & RE-LOAD ZERO DOWNTIME
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