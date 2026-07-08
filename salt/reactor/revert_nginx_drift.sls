# Kiểm tra nếu Event có chứa dữ liệu thay đổi file thực tế
{% if data and 'change' in data %}
  {% set triggered = false %}
  
  # Chuẩn hóa dữ liệu: Biến đổi thành List để luôn lặp qua được dù 'change' là một chuỗi đơn hay danh sách
  {% set changes = [data['change']] if data['change'] is string else data['change'] %}
  
  {% for change in changes %}
    {% set c = change | lower %}
    
    # 🛑 BỘ LỌC CHỐNG KÍCH HOẠT KÉP (ANTI DOUBLE-TRIGGER)
    # Nếu là sự kiện 'delete_self' nhưng đường dẫn KHÔNG PHẢI thư mục gốc, ta bỏ qua 
    # vì sự kiện 'delete' từ thư mục cha sẽ xử lý chính xác hơn.
    {% if c == 'delete_self' and data['path'] not in ['/etc/nginx', '/var/www/mysite'] %}
      # Bỏ qua sự kiện trùng lặp này
      
    # 🎯 BẮT BÀI HACKER
    {% elif 'delete' in c or 'moved' in c or 'write' in c or 'attrib' in c %}
      {% set triggered = true %}
    {% endif %}
  {% endfor %}

  # Nếu phát hiện bất kỳ dấu vết drift hoặc phá hoại nào, kích hoạt hồi phục ngay lập tức
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
