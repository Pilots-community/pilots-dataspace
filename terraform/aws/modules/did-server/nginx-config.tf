# nginx.conf is delivered via Secrets Manager + an entrypoint wrapper that
# writes it to /etc/nginx/conf.d/default.conf at container start. Same
# pattern as the EDC service configs — keeps the image stock.
resource "aws_secretsmanager_secret" "nginx_conf" {
  name                    = "${var.name_prefix}-did-server-nginx-conf"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "nginx_conf" {
  secret_id     = aws_secretsmanager_secret.nginx_conf.id
  secret_string = <<-NGINX
    server {
        listen 9876;
        server_name _;

        location = /issuer/did.json {
            root /usr/share/nginx/html;
            default_type application/json;
            add_header Access-Control-Allow-Origin *;
        }
    }
  NGINX
}
