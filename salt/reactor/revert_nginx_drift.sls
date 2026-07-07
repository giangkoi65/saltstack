# Kiểm tra nếu có biến 'change' trong dữ liệu sự kiện
{% if 'change' in data %}

  # Ép kiểu về string và viết thường để check chuỗi con chính xác 100%
  {% set change_str = data['change'] | string | lower %}

  # Kiểm tra nếu chuỗi chứa bất kỳ hành động thay đổi cấu hình nào
  {% if 'delete' in change_str or 'create' in change_str or 'moved' in change_str or 'write' in change_str %}

trigger_nginx_state_recovery:
  local.state.apply:
    - tgt: {{ data['id'] }}
    - arg:
      - nginx
    - kwarg:
        saltenv: main
        pillarenv: main
        queue: True

  {% endif %}
{% endif %}
