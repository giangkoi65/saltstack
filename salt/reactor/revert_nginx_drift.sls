{% if 'change' in data and data['change'] == 'IN_CLOSE_WRITE' %}

# ==============================================================================
# BƯỚC 1: KHÔI PHỤC CHÍNH XÁC FILE BỊ SỬA
# ==============================================================================
{% if data['path'] == '/etc/nginx/nginx.conf' %}
revert_nginx_conf:
  local.cp.get_file:
    - tgt: {{ data['id'] }}
    - arg:
      - salt://nginx/files/nginx.conf
      - /etc/nginx/nginx.conf

{% elif data['path'] == '/etc/nginx/sites-available/mysite.conf' %}
revert_mysite_conf:
  local.cp.get_file:
    - tgt: {{ data['id'] }}
    - arg:
      - salt://nginx/files/mysite.conf.jinja
      - /etc/nginx/sites-available/mysite.conf
    - kwarg:
        template: jinja

{% elif data['path'] == '/var/www/mysite/index.html' %}
revert_index_html:
  local.cp.get_file:
    - tgt: {{ data['id'] }}
    - arg:
      - salt://nginx/files/index.html
      - /var/www/mysite/index.html
{% endif %}

# ==============================================================================
# BƯỚC 2: RELOAD NGINX ĐỂ ÁP DỤNG
# ==============================================================================
reload_nginx_safely:
  local.service.reload:
    - tgt: {{ data['id'] }}
    - arg:
      - nginx

{% endif %}
