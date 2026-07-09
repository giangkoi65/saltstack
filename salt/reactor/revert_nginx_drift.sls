{% set path = data.get('path', '') %}
{% set change = data.get('change', '') %}
{% set minion_id = data.get('id', '') %}

{% if path %}
# Danh sách các file cốt lõi được định nghĩa cứng trong GitOps
{% set managed_files = [
    '/etc/nginx/nginx.conf', 
    '/etc/nginx/sites-available/mysite.conf', 
    '/etc/nginx/sites-enabled/mysite.conf'
] %}

{% if path in managed_files %}
# KHỐI 1: Nếu file GitOps bị đụng vào -> Áp dụng ĐÚNG duy nhất State ID của file đó
revert_specific_managed_file:
  local.state.sls_id:
    - tgt: {{ minion_id }}
    - arg:
      - {{ path }}
      - nginx

{% elif change in ['IN_CLOSE_WRITE', 'IN_MOVED_TO'] and not path.endswith(('.conf', '.jinja', '.bak')) %}
# KHỐI 2: Nếu có kẻ tạo FILE LẠ/THƯ MỤC LẠ trực tiếp trong /etc/nginx -> Xóa sổ ngay lập tức!
destroy_rogue_file:
  local.file.remove:
    - tgt: {{ minion_id }}
    - arg:
      - {{ path }}

{% else %}
# KHỐI 3: Nếu bị xóa mất file hệ thống hoặc đổi quyền (ATTRIB) -> Chạy State tối ưu để vá lại
trigger_optimized_nginx_repair:
  local.state.apply:
    - tgt: {{ minion_id }}
    - arg:
      - nginx
    - kwarg:
        queue: True
{% endif %}
{% endif %}