# Kiểm tra nếu Event có chứa dữ liệu thay đổi file thực tế
{% if data and 'change' in data and 'path' in data %}

  {# =========================
     2. Normalize change list
     ========================= #}
  {% set changes = [] %}
  {% if data['change'] is string %}
    {% set changes = [data['change'] | lower] %}
  {% elif data['change'] is iterable %}
    {% for item in data['change'] %}
      {% do changes.append(item | string | lower) %}
    {% endfor %}
  {% endif %}

  {# =========================
     3. Filter ONLY meaningful events
     ========================= #}
  {% set valid = false %}
  {% for c in changes %}
    {% if 'close_write' in c or 'moved_to' in c or 'delete' in c %}
      {% set valid = true %}
    {% endif %}
  {% endfor %}

  {# =========================
     4. Ignore noise files
     ========================= #}
  {% set path = data['path'] %}
  {% set noise = false %}

  {% if '.swp' in path or '~' in path or '.tmp' in path %}
    {% set noise = true %}
  {% endif %}

  {# =========================
     5. Debounce (anti spam)
     ========================= #}
  {% set lock_file = '/tmp/nginx_reactor.lock' %}
  {% set now = salt['cmd.run']('date +%s') | int %}
  {% set last = salt['file.file_exists'](lock_file) and salt['cmd.run']('cat ' ~ lock_file) | int or 0 %}

  {% set allow = (now - last) > 5 %}

  {# =========================
     6. FINAL decision
     ========================= #}
  {% if valid and not noise and allow %}

trigger_nginx_state_recovery:
  local.state.apply:
    - tgt: {{ data['id'] }}
    - arg:
      - nginx
    - kwarg:
        saltenv: main
        pillarenv: main
        queue: False   # ❗ QUAN TRỌNG: tránh queue spam

update_reactor_lock:
  local.cmd.run:
    - tgt: {{ data['id'] }}
    - arg:
      - "echo {{ now }} > {{ lock_file }}"

  {% endif %}
{% endif %}