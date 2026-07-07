{% if 'change' in data %}

  {% if data['change'] in ['close_write', 'moved_to', 'create', 'delete'] %}

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
