trigger_nginx_state_recovery:
  local.state.apply:
    - tgt: {{ data['id'] }}
    - arg:
        - nginx
    - kwarg:
        saltenv: main
        pillarenv: main
        queue: True