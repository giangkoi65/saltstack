{% set path = data.get('path', '') %}
{% set change = data.get('change', '') %}
{% set minion_id = data.get('id', '') %}

{% if path %}
  {# Giai đoạn 1: Bỏ qua tuyệt đối các file tạm của text editor để tránh nhiễu và loop #}
  {% if '.swp' in path or '.swx' in path or path.endswith('~') or '.save' in path or '/.' in path or '.dpkg-' in path %}
ignore_transient_editor_noise:
  test.configurable_test_state:
    - tgt: {{ minion_id }}
    - kwarg:
        name: "Bỏ qua nhiễu Editor: {{ path }}"
        changes: False
        result: True

  {# Giai đoạn 2: Bất kỳ biến động thực tế nào (sửa, xóa, tạo mới) đều kích hoạt State tổng để Tự chữa lành #}
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