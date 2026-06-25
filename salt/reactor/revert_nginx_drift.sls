{% if 'change' in data or data['mask'] in ['IN_MODIFY', 'IN_CLOSE_WRITE'] %}
revert_unauthorized_nginx_drift:
  local.state.apply:
    - tgt: {{ data['id'] }}
    - arg:
      - nginx
    - kwarg:
        saltenv: main
        pillarenv: main
        queue: True
{% endif %}
