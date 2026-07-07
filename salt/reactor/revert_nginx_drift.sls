# Kiểm tra nếu có biến 'change' trong dữ liệu sự kiện
{% if 'change' in data %}

  # Chuyển tất cả về chữ viết thường để tránh lệch pha giữa các phiên bản Salt/OS
  {% set change_type = data['change'] | lower %}

  # Kiểm tra nếu chuỗi chứa các từ khóa phá hoại/thay đổi cấu hình
  {% if 'delete' in change_type or 'create' in change_type or 'moved' in change_type or 'write' in change_type %}

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
