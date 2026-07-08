# salt/reactor/revert_nginx_drift.sls

{% if data and 'change' in data %}
  {% set c = data['change'] | lower %}
  {% set path = data['path'] %}
  {% set triggered = false %}

  # 1. BỎ QUA CÁC SỰ KIỆN HỆ THỐNG KHÔNG NGUY HIỂM
  {% if 'ignored' in c %}
    # Bỏ qua sự kiện IN_IGNORED (khi watcher tự hủy do thư mục gốc bị xóa tạm thời)

  # 2. BỘ LỌC CHỐNG KÍCH HOẠT KÉP (ANTI DOUBLE-TRIGGER)
  # Nếu hacker xóa thư mục con (ví dụ: /etc/nginx/conf.d), c sẽ chứa 'delete_self'.
  # Ta bỏ qua nó nếu nó KHÔNG PHẢI là 2 thư mục gốc lớn cần bảo vệ.
  {% elif 'delete_self' in c and path not in ['/etc/nginx', '/var/www/mysite'] %}
    # Bỏ qua để chờ sự kiện 'IN_DELETE' từ thư mục cha xử lý chuẩn hơn

  # 3. 🎯 BẮT BÀI HACKER
  # Nếu chuỗi sự kiện chứa bất kỳ hành vi phá hoại nào: xóa, sửa, ghi, đổi quyền
  {% elif 'delete' in c or 'moved' in c or 'write' in c or 'attrib' in c %}
    {% set triggered = true %}
  {% endif %}

  # KÍCH HOẠT HỒI PHỤC KHI ĐỦ ĐIỀU KIỆN
  {% if triggered %}
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
