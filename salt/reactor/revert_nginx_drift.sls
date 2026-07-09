{% set path = data.get('path', '') %}
{% set change = data.get('change', '') %}
{% set minion_id = data.get('id', '') %}

{% if path %}
  {# Giai đoạn 1: Bỏ qua các file tạm của text editor nhằm chống nghẽn và loop sự kiện #}
  {% if '.swp' in path or '.swx' in path or path.endswith('~') or '.save' in path or '/.' in path %}
ignore_transient_editor_noise:
  test.configurable_test_state:
    - tgt: {{ minion_id }}
    - kwarg:
        name: "Bỏ qua file tạm: {{ path }}"
        changes: False
        result: True

  {% else %}
    {# Danh sách các cấu hình sống còn trong GitOps #}
    {% set managed_files = [
        '/etc/nginx/nginx.conf', 
        '/etc/nginx/sites-available/mysite.conf', 
        '/etc/nginx/sites-enabled/mysite.conf',
        '/var/www/mysite/index.html'
    ] %}

    {% if path in managed_files and change not in ['IN_DELETE'] %}
{# KHỐI 1: Nếu cấu hình chính bị sửa đổi -> Ép ghi đè cục bộ ngay lập tức bằng sls_id #}
revert_specific_managed_file:
  local.state.sls_id:
    - tgt: {{ minion_id }}
    - arg:
      - {{ path }}
      - nginx
    - kwarg:
        saltenv: main
        pillarenv: main

    {% elif change in ['IN_CLOSE_WRITE', 'IN_MOVED_TO', 'IN_CREATE'] %}
{# KHỐI 2: Xử lý file lạ, thư mục lạ sinh ra do touch, mkdir, mv bậy bạ vào đây #}
destroy_rogue_file_or_dir:
  local.file.remove:
    - tgt: {{ minion_id }}
    - arg:
      - {{ path }}

    {% elif change in ['IN_DELETE', 'IN_ATTRIB'] and path not in managed_files %}
{# KHỐI 3: Chặn phản xạ lặp lại từ chính lệnh xóa của Khối 2 #}
ignore_automated_cleanup_events:
  test.configurable_test_state:
    - tgt: {{ minion_id }}
    - kwarg:
        name: "Chặn vòng lặp phản xạ cho lệnh xóa file: {{ path }}"
        changes: False
        result: True

    {% else %}
{# KHỐI 4: Nếu mất hẳn cấu hình hệ thống (rm), đổi quyền bừa bãi (chmod) -> Chạy state tổng để vá #}
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