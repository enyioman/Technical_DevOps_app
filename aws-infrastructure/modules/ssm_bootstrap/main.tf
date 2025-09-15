variable "project"            { type = string }
variable "region"             { type = string }
variable "asg_name"           { type = string }
variable "app_repo_url"       { type = string }
variable "app_branch"         { type = string }
variable "allowed_hosts"      { type = string }  
variable "secret_name"        { type = string } 
variable "static_bucket_name" { type = string }

# Django WSGI module
variable "wsgi_module" {
  type    = string
  default = "mysite.wsgi:application"
}

resource "aws_ssm_document" "bootstrap_django" {
  name          = "${var.project}-bootstrap-django"
  document_type = "Command"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Bootstrap Django behind Nginx/Gunicorn on ASG instances (AL2/AL2023)"
    parameters = {
      AppRepoUrl   = { type = "String" }
      AppBranch    = { type = "String" }
      AllowedHosts = { type = "String" }
      SecretName   = { type = "String" }
      StaticBucket = { type = "String" }
      Region       = { type = "String" }
      Project     = { type = "String" }
      WsgiModule   = { type = "String" }
    }
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "bootstrap"
      inputs = {
        runCommand = [
<<-BASH
set -euxo pipefail

REGION="{{ Region }}"
APP_DIR=/opt/app
APP_REPO_URL="{{ AppRepoUrl }}"
APP_BRANCH="{{ AppBranch }}"
ALLOWED_HOSTS="{{ AllowedHosts }}"
SECRET_NAME="{{ SecretName }}"
STATIC_BUCKET="{{ StaticBucket }}"
WSGI_MODULE="{{ WsgiModule }}"

# --- Packages (detect AL2023 vs AL2) ---
if command -v dnf >/dev/null 2>&1; then
  # Amazon Linux 2023
  dnf install -y nginx git jq nmap-ncat python3.11 python3.11-pip
  PY=python3.11
else
  # Amazon Linux 2
  yum makecache fast || true
  amazon-linux-extras install -y nginx1 || yum install -y nginx
  yum install -y git jq nmap-ncat || true
  # Prefer python3.8 (Django 4.2+ needs >=3.8)
  amazon-linux-extras enable python3.8 || true
  yum clean metadata || true
  yum install -y python3.8 || yum install -y python38 || yum install -y python3
  PY=$(command -v python3.8 || command -v python38 || command -v python3)
fi

# --- Nginx config: healthz + proxy to 127.0.0.1:8000 ---
rm -f /etc/nginx/conf.d/*.conf || true

mkdir -p /etc/nginx/conf.d
cat >/etc/nginx/nginx.conf <<'CONF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events { worker_connections 1024; }

http {
  include /etc/nginx/mime.types;
  default_type text/html;
  access_log /var/log/nginx/access.log combined;
  sendfile on;
  keepalive_timeout 65;
  include /etc/nginx/conf.d/*.conf;
}
CONF

cat >/etc/nginx/conf.d/app.conf <<'CONF'
server {
  listen 80 default_server;
  server_name _;
  # Simple health endpoint for ALB
  location = /healthz { default_type text/plain; return 200 "ok\n"; }

  # Proxy everything else to Gunicorn
  location / {
    proxy_pass         http://127.0.0.1:8000;
    # Force loopback host so Django never hits DisallowedHost
    proxy_set_header   Host 127.0.0.1;
    proxy_set_header   X-Real-IP $remote_addr;
    proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header   X-Forwarded-Proto $scheme;
    proxy_read_timeout 60s;
  }
}
CONF

# Prevent static welcome page from hijacking /
rm -f /usr/share/nginx/html/index.html || true

systemctl enable --now nginx
systemctl reload nginx || true

# --- App code ---
if [ ! -d "$APP_DIR/.git" ]; then
  git clone -b "$APP_BRANCH" "$APP_REPO_URL" "$APP_DIR"
else
  cd "$APP_DIR" && git fetch && git checkout "$APP_BRANCH" && git pull
fi
cd "$APP_DIR"

# --- Python venv + deps ---
$PY -m venv "$APP_DIR/venv"
source "$APP_DIR/venv/bin/activate"
pip install --upgrade pip
pip install -r requirements.txt gunicorn boto3 django-storages

cat >/opt/app/mysite/settings_local.py <<'PY'
from .settings import *
import os
ALLOWED_HOSTS = [h.strip() for h in os.getenv("ALLOWED_HOSTS","").split(",") if h.strip()] or ["localhost","127.0.0.1"]
PY

# --- DB secrets (Secrets Manager JSON: {username,password,host,port,dbname}) ---
SECRET_JSON=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$SECRET_NAME" --query SecretString --output text || echo '{}')
DB_NAME=$(echo "$SECRET_JSON" | jq -r '.dbname // empty')
DB_USER=$(echo "$SECRET_JSON" | jq -r '.username // empty')
DB_PASS=$(echo "$SECRET_JSON" | jq -r '.password // empty')
DB_HOST=$(echo "$SECRET_JSON" | jq -r '.host // empty')
DB_PORT=$(echo "$SECRET_JSON" | jq -r '.port // "5432"')

# --- Gunicorn service (uses venv) ---
cat >/etc/sysconfig/gunicorn <<EOF
DJANGO_SETTINGS_MODULE=mysite.settings_local
ALLOWED_HOSTS=$ALLOWED_HOSTS
AWS_DEFAULT_REGION=$REGION
AWS_STORAGE_BUCKET_NAME=$STATIC_BUCKET
RDS_DB_NAME=$DB_NAME
RDS_USERNAME=$DB_USER
RDS_PASSWORD=$DB_PASS
RDS_HOSTNAME=$DB_HOST
RDS_PORT=$DB_PORT
EOF

# Django log files
mkdir -p /var/log/gunicorn
chmod 755 /var/log/gunicorn

# Gunicorn service (uses venv + env file)
cat >/etc/systemd/system/gunicorn.service <<UNIT
[Unit]
Description=Gunicorn for Django
After=network-online.target nginx.service
Wants=network-online.target

[Service]
WorkingDirectory=$APP_DIR
EnvironmentFile=-/etc/sysconfig/gunicorn
ExecStartPre=/usr/bin/env bash -lc '$APP_DIR/venv/bin/python manage.py migrate --noinput || true'
ExecStart=$APP_DIR/venv/bin/gunicorn $WSGI_MODULE --bind 127.0.0.1:8000 --workers 3 --timeout 60 \
  --access-logfile /var/log/gunicorn/access.log \
  --error-logfile /var/log/gunicorn/error.log
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now gunicorn

# --- Static (non-fatal) ---
$APP_DIR/venv/bin/python manage.py collectstatic --noinput || true

# ---------------- CloudWatch Agent: install, configure, start ----------------
# --- CloudWatch Agent: config + start ---
CFG_ROOT=/opt/aws/amazon-cloudwatch-agent/etc
LOG_PREFIX="/$PROJECT"

mkdir -p "$CFG_ROOT" "$CFG_ROOT/amazon-cloudwatch-agent.d" /opt/aws/amazon-cloudwatch-agent/logs

# Write JSON with Terraform-safe $${aws:*} (escaped) and a placeholder for LOG_PREFIX.
# Single-quoted heredoc prevents Bash from expanding $${...}.
cat >"$CFG_ROOT/amazon-cloudwatch-agent.json" <<'JSON'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root",
    "logfile": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
  },
  "metrics": {
    "append_dimensions": {
      "AutoScalingGroupName": "$${aws:AutoScalingGroupName}",
      "InstanceId": "$${aws:InstanceId}"
    },
    "metrics_collected": {
      "cpu": { "resources": ["*"], "measurement": ["usage_user","usage_system","usage_idle"], "totalcpu": true, "append_dimensions": {} },
      "mem": { "measurement": ["used_percent","available"] },
      "disk": { "resources": ["*"], "measurement": ["used_percent"] }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "__LOG_PREFIX__/nginx/access",
            "log_stream_name": "{instance_id}",
            "retention_in_days": -1
          },
          {
            "file_path": "/var/log/nginx/error.log",
            "log_group_name": "__LOG_PREFIX__/nginx/error",
            "log_stream_name": "{instance_id}",
            "retention_in_days": -1
          },
          {
            "file_path": "/var/log/gunicorn/access.log",
            "log_group_name": "__LOG_PREFIX__/gunicorn",
            "log_stream_name": "{instance_id}",
            "retention_in_days": -1
          },
          {
            "file_path": "/var/log/gunicorn/error.log",
            "log_group_name": "__LOG_PREFIX__/gunicorn",
            "log_stream_name": "{instance_id}",
            "retention_in_days": -1
          }
        ]
      }
    }
  }
}
JSON

# Replace placeholder with actual prefix (Bash expansion is allowed here)
sed -i "s|__LOG_PREFIX__|$LOG_PREFIX|g" "$CFG_ROOT/amazon-cloudwatch-agent.json"

# Start agent using the file config
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -c file:$CFG_ROOT/amazon-cloudwatch-agent.json -s


# --- Smoke: ensure healthz works locally ---
curl -sfI http://127.0.0.1/healthz
BASH
        ]
      }
    }]
  })
}

resource "aws_ssm_association" "bootstrap_on_asg" {
  name = aws_ssm_document.bootstrap_django.name

  targets {
    key    = "tag:aws:autoscaling:groupName"
    values = [var.asg_name]
  }

  # run every 30m
  schedule_expression         = "rate(30 minutes)"
  apply_only_at_cron_interval = false
  max_concurrency             = "100%"
  max_errors                  = "1"
  compliance_severity         = "CRITICAL"

  parameters = {
    AppRepoUrl   = var.app_repo_url
    AppBranch    = var.app_branch
    AllowedHosts = var.allowed_hosts
    SecretName   = var.secret_name
    StaticBucket = var.static_bucket_name
    Region       = var.region
    Project      = var.project
    WsgiModule   = var.wsgi_module
  }
}
