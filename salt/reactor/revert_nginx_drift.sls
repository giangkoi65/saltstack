# Kiểm tra nếu Event có chứa dữ liệu thay đổi file thực tế
{% if data and 'change' in data %}
  {% set triggered = false %}
  
  {% if data['change'] is string %}
    {% set change_str = data['change'] | lower %}
    {% if 'delete' in change_str or 'create' in change_str or 'moved' in change_str or 'write' in change_str %}
      {% set triggered = true %}
    {% endif %}
  {% elif data['change'] is iterable %}
    {% for item in data['change'] %}
      {% set item_str = item | string | lower %}
      {% if 'delete' in item_str or 'create' in item_str or 'moved' in item_str or 'write' in item_str %}
        {% set triggered = true %}
      {% endif %}
    {% endfor %}
  {% endif %}

  {% if triggered %}
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