{% if 'change' in data and data['change'] == 'IN_CLOSE_WRITE' %}

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
