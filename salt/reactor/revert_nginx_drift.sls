# Kiểm tra nếu Event có chứa dữ liệu thay đổi file thực tế
{% if data and 'change' in data %}
  {% set triggered = false %}

  {% set changes = [] %}
  {% if data['change'] is string %}
    {% set changes = [data['change'] | lower] %}
  {% elif data['change'] is iterable %}
    {% for item in data['change'] %}
      {% do changes.append(item | string | lower) %}
    {% endfor %}
  {% endif %}

  {% for c in changes %}
    {% if 'write' in c or 'create' in c or 'delete' in c or 'moved' in c %}
      {% set triggered = true %}
    {% endif %}
  {% endfor %}

  {# ❗ debounce nhẹ thay vì filter quá mạnh #}
  {% set lock_file = '/tmp/nginx_reactor.lock' %}
  {% set now = salt['cmd.run']('date +%s') | int %}
  {% set last = salt['file.file_exists'](lock_file) and salt['cmd.run']('cat ' ~ lock_file) | int or 0 %}

  {% if triggered and (now - last) > 3 %}

trigger_nginx_state_recovery:
  local.state.apply:
    - tgt: {{ data['id'] }}
    - arg:
      - nginx
    - kwarg:
        saltenv: main
        pillarenv: main
        queue: False

update_lock:
  local.cmd.run:
    - tgt: {{ data['id'] }}
    - arg:
      - "echo {{ now }} > {{ lock_file }}"

  {% endif %}
{% endif %}