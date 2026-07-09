{% set path = data.get('path') or data.get('files', [''])[0] %}
{% set change = data.get('change', '') %}
{% set minion_id = data.get('id', '') %}
{% set tag = tag %}

{% if path %}
  {% if 'salt/job' in tag %}
ignore_salt_internal_event:
  test.configurable_test_state:
    - tgt: {{ minion_id }}
    - kwarg:
        name: "Ignore Salt internal event"
        changes: False
        result: True

  {% else %}

  {# Giai đoạn 1: Bỏ qua tuyệt đối các file tạm của text editor để tránh nhiễu và loop #}
  {% if '.swp' in path or '.swx' in path or path.endswith('~') or '.save' in path or '/.' in path or '.dpkg-' in path % or '.tmp' in path or '.bak' in path or '.cache' in path}
ignore_transient_editor_noise:
  test.configurable_test_state:
    - tgt: {{ minion_id }}
    - kwarg:
        name: "Bỏ qua nhiễu Editor: {{ path }}"
        changes: False
        result: True

  {% else %}

  {# Giai đoạn 2: Bất kỳ biến động thực tế nào (sửa, xóa, tạo mới) đều kích hoạt State tổng để Tự chữa lành #}
  {% if change == 'delete_self' %}
force_full_rebuild:
  local.state.apply:
    - tgt: {{ minion_id }}
    - arg:
      - nginx
    - kwarg:
        queue: True
        saltenv: main
        pillarenv: main

   {% else %}
trigger_nginx_gitops_healing:
  local.state.apply:
    - tgt: {{ minion_id }}
    - arg:
      - nginx
    - kwarg:
        queue: True
        saltenv: main
        pillarenv: main
      {% endif %}
    {% endif %}  
  {% endif %}
{% endif %}