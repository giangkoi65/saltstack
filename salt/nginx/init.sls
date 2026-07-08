# ==============================================================================
# 1. PHÁT HIỆN SỰ CỐ (SỬA/XÓA/MV CẢ FILE THƯỜNG & CONFFILES) VÀ CÀI LẠI SẠCH TỪ APT
# ==============================================================================
repair_nginx_core_files:
  cmd.run:
    - name: |
        echo "🛑 Khóa tiến trình restart của APT..."
        echo "exit 101" > /usr/sbin/policy-rc.d
        chmod +x /usr/sbin/policy-rc.d

        PKGS=$(dpkg -l '*nginx*' | grep '^ii' | awk '{print $2}')
        
        echo "⚠️ Phát hiện cấu hình hệ thống bị can thiệp trái phép!"
        echo "🧹 Tiến hành dọn dẹp và ép buộc tái cài đặt sạch từ APT Repository..."
        
        # --force-confnew: Ghi đè cấu hình gốc của package lên các file đã bị sửa đổi
        # --force-confmiss: Cài bù lại hoàn toàn các cấu hình hệ thống đã bị xóa hoặc di chuyển (mv)
        apt-get install --reinstall -o Dpkg::Options::="--force-confnew" -o Dpkg::Options::="--force-confmiss" -y $PKGS

        echo "🔓 Mở khóa policy-rc.d..."
        rm -f /usr/sbin/policy-rc.d
    - onlyif: |
        # Kịch bản quét kép: Đảm bảo phát hiện mọi biến động mà không cần file backup độc lập

        # Bước A: Kiểm tra các file thông thường qua tệp tin .md5sums
        PKGS=$(dpkg -l '*nginx*' | grep '^ii' | awk '{print $2}')
        for pkg in $PKGS; do
          MD5_SUMS_FILE="/var/lib/dpkg/info/${pkg}.md5sums"
          if [ -f "$MD5_SUMS_FILE" ]; then
            while read -r target_md5 target_file; do
              if [[ "$target_file" == etc/nginx/* ]]; then
                full_path="/$target_file"
                if [[ "$full_path" == "/etc/nginx/nginx.conf" || "$full_path" == "/etc/nginx/sites-available/mysite.conf" || "$full_path" == "/etc/nginx/sites-enabled/"* || "$full_path" == "/etc/nginx/sites-available/default" ]]; then
                  continue
                fi
                if [ ! -f "$full_path" ]; then exit 0; fi
                current_md5=$(md5sum "$full_path" | awk '{print $1}')
                if [ "$current_md5" != "$target_md5" ]; then exit 0; fi
              fi
            done < "$MD5_SUMS_FILE"
          fi
        done

        # Bước B: Kiểm tra nghiêm ngặt nhóm Conffiles (mime.types, fastcgi_params...) bằng DB gốc của DPKG
        awk '/^Package: .*nginx.*/ {p=1; next} /^Package:/ {p=0} p && /^Conffiles:/ {c=1; next} c && /^ / {print $1, $2} c && !/^ / {c=0}' /var/lib/dpkg/status | while read -r file expected_md5; do
          if [[ "$file" == "/etc/nginx/nginx.conf" || "$file" == "/etc/nginx/sites-available/mysite.conf" || "$file" == "/etc/nginx/sites-enabled/"* || "$file" == "/etc/nginx/sites-available/default" ]]; then
            continue
          fi
          if [ ! -f "$file" ]; then exit 0; fi
          current_md5=$(md5sum "$file" | awk '{print $1}')
          if [ "$current_md5" != "$expected_md5" ]; then exit 0; fi
        done

        # Bước C: Kiểm tra quyền hạn sở hữu (ATTRIB)
        if [ $(find /etc/nginx -not -user root -o -not -group root | wc -l) -gt 0 ]; then exit 0; fi

        exit 1
    - shell: /bin/bash
    - order: 1

# ==============================================================================
# 2. KHÓA CHẶT THƯ MỤC CẤU HÌNH VÀ DIỆT FILE LẠ
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
    - clean: False
    - require:
      - file: manage_nginx_root_dir

/etc/nginx/sites-available:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - clean: True 
    - exclude_pat: '.*(default|mysite\.conf)$'
    - require:
      - file: manage_nginx_root_dir

/etc/nginx/sites-enabled:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - clean: True 
    - exclude_pat: '.*mysite\.conf$'
    - require:
      - file: manage_nginx_root_dir

nginx_package:
  pkg.installed:
    - name: nginx
    - require:
      - cmd:
