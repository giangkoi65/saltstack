{% if 'change' in data and data['change'] == 'IN_CLOSE_WRITE' %}

trigger_nginx_deduplicated_recovery:
  runner.dedup_drift.check_and_apply:
    - minion_id: {{ data['id'] }}
    - state_name: nginx

{% endif %}
