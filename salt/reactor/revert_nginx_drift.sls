{% set path = data.get('path', '') %}
{% set change = data.get('change', '') %}
{% set minion_id = data.get('id', '') %}

{% if path %}
# Danh sách các file cốt lõi được định nghĩa cứng trong GitOps
{% set managed_files = [
    '/etc/nginx/nginx.conf', 
    '/etc/nginx/sites-available/mysite.conf', 
    '/etc/nginx/sites-enabled/mysite.conf',
    '/var/www/mysite/index.html'
] %}

{% if path in managed_files and change not in ['IN_DELETE'] %}
# KHỐI 1: Nếu file GitOps chuẩn bị đụng vào -> Ép Master dùng saltenv=main để ghi đè lại file đó
revert_specific_managed_file:
  local.state.sls_id:
    - tgt: {{ minion_id }}
    - arg:
      - {{ path }}
      - nginx
    - kwarg:
        saltenv: main
        pillarenv: main

{% elif change in ['IN_CLOSE_WRITE', 'IN_MOVED_TO'] %}
# KHỐI 2: Nếu có kẻ tạo FILE LẠ -> Tiêu diệt ngay lập tức
destroy_rogue_file:
  local.file.remove:
    - tgt: {{ minion_id }}
    - arg:
      - {{ path }}

{% elif change in ['IN_DELETE', 'IN_ATTRIB'] and path not in managed_files %}
# KHỐI 2.5: Chặn phản xạ lặp lại - Nếu là sự kiện xóa file lạ do Khối 2 thực hiện -> Bỏ qua hoàn toàn
ignore_automated_cleanup_events:
  test.configurable_test_state:
    - tgt: {{ minion_id }}
    - kwarg:
        name: "Chặn vòng lặp phản xạ cho file: {{ path }}"
        changes: False
        result: True

{% else %}
# KHỐI 3: Nếu bị xóa mất file hệ thống hoặc đổi quyền (ATTRIB) -> Chạy State tổng lực với saltenv=main để vá
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