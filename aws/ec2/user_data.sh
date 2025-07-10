#!/bin/bash

# Cryonith LLC EC2 User Data Script
# Automatically configure EC2 instance for trading platform

# Redirect output to log file
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "🚀 Starting Cryonith EC2 Instance Setup..."

# Update system
yum update -y

# Install essential packages
yum install -y git python3 python3-pip docker nginx

# Install Node.js for potential frontend needs
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
yum install -y nodejs

# Start and enable Docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Start and enable Nginx
systemctl start nginx
systemctl enable nginx

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create application directory
mkdir -p /opt/cryonith
cd /opt/cryonith

# Clone the repository (placeholder - will be updated with actual repo)
# git clone https://github.com/your-username/cryonith-production.git .

# For now, create basic structure
mkdir -p {backend,frontend,logs,data}

# Create Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies (basic set)
pip install --upgrade pip
pip install flask flask-cors gunicorn boto3 requests pandas numpy

# Create basic Flask app for health check
cat > backend/app.py << 'EOF'
#!/usr/bin/env python3

from flask import Flask, jsonify
from flask_cors import CORS
import os
import datetime

app = Flask(__name__)
CORS(app)

@app.route('/')
def home():
    return jsonify({
        "message": "Cryonith Trading Platform",
        "status": "running",
        "timestamp": datetime.datetime.utcnow().isoformat(),
        "version": "1.0.0"
    })

@app.route('/health')
def health():
    return jsonify({
        "status": "healthy",
        "timestamp": datetime.datetime.utcnow().isoformat(),
        "uptime": "running"
    })

@app.route('/api/status')
def api_status():
    return jsonify({
        "api": "cryonith-trading",
        "status": "active",
        "endpoints": [
            "/",
            "/health",
            "/api/status"
        ],
        "timestamp": datetime.datetime.utcnow().isoformat()
    })

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False)
EOF

# Create Gunicorn config
cat > backend/gunicorn.conf.py << 'EOF'
bind = "0.0.0.0:5000"
workers = 4
worker_class = "sync"
worker_connections = 1000
max_requests = 1000
max_requests_jitter = 100
timeout = 30
keepalive = 2
preload_app = True
EOF

# Create systemd service for the app
cat > /etc/systemd/system/cryonith-api.service << 'EOF'
[Unit]
Description=Cryonith Trading Platform API
After=network.target

[Service]
Type=notify
User=ec2-user
Group=ec2-user
WorkingDirectory=/opt/cryonith
Environment=PATH=/opt/cryonith/venv/bin
ExecStart=/opt/cryonith/venv/bin/gunicorn --config backend/gunicorn.conf.py backend.app:app
ExecReload=/bin/kill -s HUP $MAINPID
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Configure Nginx
cat > /etc/nginx/conf.d/cryonith.conf << 'EOF'
server {
    listen 80;
    server_name _;
    
    # API proxy
    location /api {
        proxy_pass http://localhost:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # Health check
    location /health {
        proxy_pass http://localhost:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # Root
    location / {
        proxy_pass http://localhost:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

# Set proper permissions
chown -R ec2-user:ec2-user /opt/cryonith
chmod +x /opt/cryonith/backend/app.py

# Enable and start services
systemctl daemon-reload
systemctl enable cryonith-api
systemctl start cryonith-api
systemctl restart nginx

# Create log rotation
cat > /etc/logrotate.d/cryonith << 'EOF'
/opt/cryonith/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 ec2-user ec2-user
    postrotate
        systemctl reload cryonith-api
    endscript
}
EOF

# Install monitoring tools
yum install -y htop iotop

# Create monitoring script
cat > /opt/cryonith/monitor.sh << 'EOF'
#!/bin/bash
# Simple monitoring script

echo "=== Cryonith System Status ==="
echo "Date: $(date)"
echo "Uptime: $(uptime)"
echo ""
echo "=== Service Status ==="
systemctl status cryonith-api --no-pager
echo ""
systemctl status nginx --no-pager
echo ""
echo "=== Resource Usage ==="
free -h
echo ""
df -h
echo ""
echo "=== Network Connections ==="
netstat -tlnp | grep -E ':(80|443|5000)'
echo ""
echo "=== Recent Logs ==="
tail -20 /var/log/user-data.log
EOF

chmod +x /opt/cryonith/monitor.sh

# Create startup script
cat > /opt/cryonith/startup.sh << 'EOF'
#!/bin/bash
# Startup script for Cryonith platform

echo "Starting Cryonith Trading Platform..."

# Activate virtual environment
source /opt/cryonith/venv/bin/activate

# Start services
systemctl start cryonith-api
systemctl start nginx

# Wait for services to start
sleep 5

# Check services
systemctl status cryonith-api
systemctl status nginx

# Test endpoints
curl -s http://localhost:5000/health | python3 -m json.tool

echo "Cryonith Platform is ready!"
EOF

chmod +x /opt/cryonith/startup.sh

# Run startup script
/opt/cryonith/startup.sh

# Create status check script
cat > /opt/cryonith/status.sh << 'EOF'
#!/bin/bash
# Status check script

echo "🔍 Cryonith System Status Check"
echo "==============================="
echo ""

# Check services
echo "📊 Service Status:"
systemctl is-active cryonith-api --quiet && echo "✅ Cryonith API: Running" || echo "❌ Cryonith API: Not Running"
systemctl is-active nginx --quiet && echo "✅ Nginx: Running" || echo "❌ Nginx: Not Running"
systemctl is-active docker --quiet && echo "✅ Docker: Running" || echo "❌ Docker: Not Running"
echo ""

# Check ports
echo "🔌 Port Status:"
netstat -tlnp | grep -q ':80 ' && echo "✅ Port 80: Open" || echo "❌ Port 80: Closed"
netstat -tlnp | grep -q ':5000 ' && echo "✅ Port 5000: Open" || echo "❌ Port 5000: Closed"
echo ""

# Check API endpoints
echo "🌐 API Endpoints:"
if curl -s http://localhost:5000/health >/dev/null 2>&1; then
    echo "✅ Health endpoint: Responsive"
else
    echo "❌ Health endpoint: Not responsive"
fi

if curl -s http://localhost/health >/dev/null 2>&1; then
    echo "✅ Nginx proxy: Working"
else
    echo "❌ Nginx proxy: Not working"
fi
echo ""

# System resources
echo "💾 System Resources:"
echo "CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)% used"
echo "Memory: $(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')"
echo "Disk: $(df -h / | awk 'NR==2{print $5}')"
echo ""

# Show public IP
echo "🌍 Public IP: $(curl -s http://checkip.amazonaws.com/)"
echo ""

echo "✅ Status check complete!"
EOF

chmod +x /opt/cryonith/status.sh

# Final status check
echo "🏁 Final Setup Status Check:"
/opt/cryonith/status.sh

echo "✅ Cryonith EC2 Setup Complete!"
echo "📝 Setup completed at: $(date)"
echo "🔗 Access the platform at: http://$(curl -s http://checkip.amazonaws.com/)" 