{% if 'change' in data %}

  {% if data['change'] in ['IN_CLOSE_WRITE', 'IN_MOVED_TO', 'IN_CREATE', 'IN_DELETE'] %}

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
