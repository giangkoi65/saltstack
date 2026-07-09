{% set path = data.get('path', '') %}
{% set change = data.get('change', '') %}
{% set minion_id = data.get('id', '') %}

{% if path %}
  {# LỌC NHIỄU: Nếu KHÔNG PHẢI file tạm (.swp, .swx, ~, .save) và KHÔNG PHẢI file ẩn (bắt đầu bằng dấu chấm) thì mới xử lý #}
  {% if '.swp' not in path and '.swx' not in path and not path.endswith('~') and '.save' not in path and not path.split('/')[-1].startswith('.') %}
    
    {% set managed_files = [
        '/etc/nginx/nginx.conf', 
        '/etc/nginx/sites-available/mysite.conf', 
        '/etc/nginx/sites-enabled/mysite.conf',
        '/var/www/mysite/index.html'
    ] %}

    {% if path in managed_files and 'DELETE' not in change %}
{# TRƯỜNG HỢP A: Sửa đổi file cấu hình chính -> Ép ghi đè cục bộ ngay lập tức bằng sls_id #}
revert_specific_managed_file:
  local.state.sls_id:
    - tgt: {{ minion_id }}
    - arg:
      - {{ path }}
      - nginx
    - kwarg:
        saltenv: main
        pillarenv: main

    {% elif 'CREATE' in change or 'CLOSE_WRITE' in change or 'MOVED_TO' in change %}
{# TRƯỜNG HỢP B: Có kẻ tạo file lạ hoặc cấu hình lạ (touch, mkdir, mv bậy vào) -> Tiêu diệt #}
destroy_rogue_file_or_dir:
  local.file.remove:
    - tgt: {{ minion_id }}
    - arg:
      - {{ path }}

    {% else %}
{# TRƯỜNG HỢP C: Mọi hành vi XÓA (rm, rmdir) hoặc thay đổi thuộc tính hệ thống (chmod/chown) #}
{# Chạy state.apply tổng lực để dọn dẹp và khôi phục lại cấu hình chuẩn chỉ trong 0.1 giây #}
trigger_optimized_nginx_repair:
  local.state.apply:
    - tgt: {{ minion_id }}
    - arg:
      - nginx
    - kwarg:
        queue: True
        saltenv: main
        pillarenv: main
    {% endif %}
    
  {% endif %}
{% endif %}