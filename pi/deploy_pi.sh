#!/bin/bash

# Cryonith LLC Raspberry Pi Deployment Script
# Deploy organized infrastructure to Raspberry Pi

set -e

echo "🍓 Starting Cryonith Pi Deployment..."

# Configuration
PI_USER=${PI_USER:-pi}
PI_HOST=${PI_HOST:-raspberrypi.local}
INSTALL_DIR=${INSTALL_DIR:-/opt/cryonith}
PYTHON_VERSION=${PYTHON_VERSION:-3.9}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running on Pi
check_pi_environment() {
    if [[ -f /proc/cpuinfo ]] && grep -q "Raspberry Pi" /proc/cpuinfo; then
        print_success "Running on Raspberry Pi"
        return 0
    elif [[ -f /proc/device-tree/model ]] && grep -q "Raspberry Pi" /proc/device-tree/model; then
        print_success "Running on Raspberry Pi"
        return 0
    else
        print_warning "Not running on Raspberry Pi - continuing anyway"
        return 1
    fi
}

# System update and package installation
update_system() {
    print_status "Updating system packages..."
    
    sudo apt update -y
    sudo apt upgrade -y
    
    # Install essential packages
    sudo apt install -y \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        git \
        curl \
        wget \
        htop \
        iotop \
        nginx \
        docker.io \
        docker-compose \
        build-essential \
        libssl-dev \
        libffi-dev \
        pkg-config \
        cmake \
        sqlite3 \
        redis-server \
        supervisor
    
    # Add user to docker group
    sudo usermod -aG docker $USER
    
    # Enable services
    sudo systemctl enable docker
    sudo systemctl start docker
    sudo systemctl enable redis-server
    sudo systemctl start redis-server
    sudo systemctl enable nginx
    sudo systemctl start nginx
    
    print_success "System updated and packages installed"
}

# Create application structure
create_app_structure() {
    print_status "Creating application structure..."
    
    # Create main directory
    sudo mkdir -p $INSTALL_DIR
    sudo chown -R $USER:$USER $INSTALL_DIR
    
    # Create subdirectories
    mkdir -p $INSTALL_DIR/{backend,frontend,logs,data,config,scripts}
    mkdir -p $INSTALL_DIR/data/{sqlite,redis,uploads}
    mkdir -p $INSTALL_DIR/logs/{app,nginx,system}
    
    print_success "Application structure created"
}

# Setup Python environment
setup_python_env() {
    print_status "Setting up Python environment..."
    
    cd $INSTALL_DIR
    
    # Create virtual environment
    python3 -m venv venv
    source venv/bin/activate
    
    # Upgrade pip
    pip install --upgrade pip
    
    # Install basic dependencies
    pip install \
        flask \
        flask-cors \
        flask-socketio \
        gunicorn \
        requests \
        pandas \
        numpy \
        sqlite3 \
        redis \
        python-dotenv \
        pyyaml \
        cryptography \
        pytz \
        python-dateutil
    
    # Install Pi-specific packages
    pip install \
        RPi.GPIO \
        gpiozero \
        adafruit-circuitpython-dht \
        w1thermsensor
    
    print_success "Python environment configured"
}

# Create main application
create_main_app() {
    print_status "Creating main application..."
    
    cat > $INSTALL_DIR/backend/app.py << 'EOF'
#!/usr/bin/env python3
"""
Cryonith Trading Platform - Pi Edition
Optimized for Raspberry Pi with local data storage
"""

import os
import json
import sqlite3
import datetime
from flask import Flask, jsonify, request
from flask_cors import CORS
import redis
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/opt/cryonith/logs/app/app.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# Initialize Redis connection
try:
    redis_client = redis.Redis(host='localhost', port=6379, db=0)
    redis_client.ping()
    logger.info("Redis connected successfully")
except Exception as e:
    logger.error(f"Redis connection failed: {e}")
    redis_client = None

# Initialize SQLite database
def init_db():
    conn = sqlite3.connect('/opt/cryonith/data/sqlite/trading.db')
    cursor = conn.cursor()
    
    # Create tables
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS trades (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            symbol TEXT NOT NULL,
            action TEXT NOT NULL,
            quantity REAL NOT NULL,
            price REAL NOT NULL,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS portfolio (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            symbol TEXT NOT NULL,
            quantity REAL NOT NULL,
            avg_price REAL NOT NULL,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS system_metrics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            metric_name TEXT NOT NULL,
            metric_value REAL NOT NULL,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    conn.commit()
    conn.close()
    logger.info("Database initialized successfully")

# Initialize database
init_db()

@app.route('/')
def home():
    return jsonify({
        "message": "Cryonith Trading Platform - Pi Edition",
        "status": "running",
        "timestamp": datetime.datetime.utcnow().isoformat(),
        "version": "1.0.0-pi",
        "platform": "raspberry_pi"
    })

@app.route('/health')
def health():
    # Check system health
    health_status = {
        "status": "healthy",
        "timestamp": datetime.datetime.utcnow().isoformat(),
        "components": {
            "database": "healthy",
            "redis": "healthy" if redis_client else "unavailable",
            "filesystem": "healthy"
        }
    }
    
    # Check database connection
    try:
        conn = sqlite3.connect('/opt/cryonith/data/sqlite/trading.db')
        conn.close()
    except Exception as e:
        health_status["components"]["database"] = "unhealthy"
        health_status["status"] = "degraded"
    
    return jsonify(health_status)

@app.route('/api/system/info')
def system_info():
    """Get Pi system information"""
    try:
        # Get system information
        with open('/proc/cpuinfo', 'r') as f:
            cpuinfo = f.read()
        
        with open('/proc/meminfo', 'r') as f:
            meminfo = f.read()
        
        # Extract Pi model
        pi_model = "Unknown"
        for line in cpuinfo.split('\n'):
            if 'Model' in line:
                pi_model = line.split(':')[1].strip()
                break
        
        # Extract memory info
        total_mem = 0
        free_mem = 0
        for line in meminfo.split('\n'):
            if 'MemTotal' in line:
                total_mem = int(line.split()[1])
            elif 'MemFree' in line:
                free_mem = int(line.split()[1])
        
        return jsonify({
            "pi_model": pi_model,
            "memory": {
                "total_kb": total_mem,
                "free_kb": free_mem,
                "used_percent": round((total_mem - free_mem) / total_mem * 100, 2)
            },
            "timestamp": datetime.datetime.utcnow().isoformat()
        })
    except Exception as e:
        logger.error(f"Error getting system info: {e}")
        return jsonify({"error": "Unable to get system info"}), 500

@app.route('/api/trades', methods=['GET', 'POST'])
def trades():
    """Handle trade operations"""
    if request.method == 'GET':
        # Get recent trades
        conn = sqlite3.connect('/opt/cryonith/data/sqlite/trading.db')
        cursor = conn.cursor()
        cursor.execute('SELECT * FROM trades ORDER BY timestamp DESC LIMIT 50')
        trades = cursor.fetchall()
        conn.close()
        
        return jsonify({
            "trades": trades,
            "count": len(trades)
        })
    
    elif request.method == 'POST':
        # Add new trade
        data = request.json
        required_fields = ['symbol', 'action', 'quantity', 'price']
        
        if not all(field in data for field in required_fields):
            return jsonify({"error": "Missing required fields"}), 400
        
        conn = sqlite3.connect('/opt/cryonith/data/sqlite/trading.db')
        cursor = conn.cursor()
        cursor.execute('''
            INSERT INTO trades (symbol, action, quantity, price)
            VALUES (?, ?, ?, ?)
        ''', (data['symbol'], data['action'], data['quantity'], data['price']))
        conn.commit()
        conn.close()
        
        logger.info(f"New trade recorded: {data}")
        return jsonify({"message": "Trade recorded successfully"}), 201

@app.route('/api/portfolio')
def portfolio():
    """Get current portfolio"""
    conn = sqlite3.connect('/opt/cryonith/data/sqlite/trading.db')
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM portfolio')
    portfolio = cursor.fetchall()
    conn.close()
    
    return jsonify({
        "portfolio": portfolio,
        "count": len(portfolio)
    })

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    logger.info(f"Starting Cryonith Pi server on port {port}")
    app.run(host='0.0.0.0', port=port, debug=False)
EOF

    chmod +x $INSTALL_DIR/backend/app.py
    print_success "Main application created"
}

# Configure Nginx
configure_nginx() {
    print_status "Configuring Nginx..."
    
    # Create Nginx configuration
    sudo tee /etc/nginx/sites-available/cryonith << 'EOF'
server {
    listen 80;
    server_name _;
    
    # Logs
    access_log /opt/cryonith/logs/nginx/access.log;
    error_log /opt/cryonith/logs/nginx/error.log;
    
    # API proxy
    location /api {
        proxy_pass http://localhost:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # Health check
    location /health {
        proxy_pass http://localhost:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # Static files
    location /static {
        alias /opt/cryonith/frontend/static;
        expires 1y;
        add_header Cache-Control "public, immutable";
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

    # Enable the site
    sudo ln -sf /etc/nginx/sites-available/cryonith /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    
    # Create log directories
    sudo mkdir -p /opt/cryonith/logs/nginx
    sudo chown -R www-data:www-data /opt/cryonith/logs/nginx
    
    # Test and reload Nginx
    sudo nginx -t
    sudo systemctl reload nginx
    
    print_success "Nginx configured"
}

# Create systemd service
create_systemd_service() {
    print_status "Creating systemd service..."
    
    sudo tee /etc/systemd/system/cryonith-pi.service << EOF
[Unit]
Description=Cryonith Trading Platform (Pi Edition)
After=network.target redis.service
Requires=redis.service

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$INSTALL_DIR
Environment=PATH=$INSTALL_DIR/venv/bin
ExecStart=$INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/backend/app.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=cryonith-pi

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable cryonith-pi
    
    print_success "Systemd service created"
}

# Create monitoring and maintenance scripts
create_scripts() {
    print_status "Creating monitoring scripts..."
    
    # System monitor script
    cat > $INSTALL_DIR/scripts/monitor.sh << 'EOF'
#!/bin/bash
# Cryonith Pi System Monitor

echo "🍓 Cryonith Pi System Monitor"
echo "============================="
echo "Date: $(date)"
echo ""

# System info
echo "🔧 System Information:"
echo "  Model: $(cat /proc/device-tree/model 2>/dev/null || echo 'Unknown')"
echo "  Uptime: $(uptime -p)"
echo "  Load: $(uptime | awk -F'load average:' '{print $2}')"
echo ""

# Temperature
if command -v vcgencmd &> /dev/null; then
    temp=$(vcgencmd measure_temp | cut -d'=' -f2)
    echo "🌡️  Temperature: $temp"
else
    echo "🌡️  Temperature: Not available"
fi
echo ""

# Memory
echo "💾 Memory Usage:"
free -h
echo ""

# Disk usage
echo "💿 Disk Usage:"
df -h /
echo ""

# Services
echo "🔧 Service Status:"
systemctl is-active cryonith-pi --quiet && echo "✅ Cryonith Pi: Running" || echo "❌ Cryonith Pi: Not Running"
systemctl is-active nginx --quiet && echo "✅ Nginx: Running" || echo "❌ Nginx: Not Running"
systemctl is-active redis --quiet && echo "✅ Redis: Running" || echo "❌ Redis: Not Running"
echo ""

# Network
echo "🌐 Network Status:"
if ping -c 1 8.8.8.8 &> /dev/null; then
    echo "✅ Internet: Connected"
else
    echo "❌ Internet: Disconnected"
fi

# Local IP
local_ip=$(hostname -I | awk '{print $1}')
echo "🏠 Local IP: $local_ip"
echo ""

# API Health Check
echo "🔍 API Health Check:"
if curl -s http://localhost:5000/health >/dev/null 2>&1; then
    echo "✅ API: Healthy"
else
    echo "❌ API: Unhealthy"
fi
echo ""

echo "✅ Monitor complete!"
EOF

    chmod +x $INSTALL_DIR/scripts/monitor.sh
    
    # Maintenance script
    cat > $INSTALL_DIR/scripts/maintenance.sh << 'EOF'
#!/bin/bash
# Cryonith Pi Maintenance Script

echo "🔧 Starting Cryonith Pi Maintenance..."

# Update system
echo "📦 Updating system packages..."
sudo apt update -y && sudo apt upgrade -y

# Clean logs
echo "🗑️  Cleaning old logs..."
find /opt/cryonith/logs -name "*.log" -type f -mtime +7 -delete
sudo journalctl --vacuum-time=7d

# Update Python packages
echo "🐍 Updating Python packages..."
source /opt/cryonith/venv/bin/activate
pip install --upgrade pip
pip list --outdated --format=freeze | grep -v '^\-e' | cut -d = -f 1 | xargs -n1 pip install -U

# Restart services
echo "♻️  Restarting services..."
sudo systemctl restart cryonith-pi
sudo systemctl restart nginx

# System health check
echo "🔍 Running health check..."
/opt/cryonith/scripts/monitor.sh

echo "✅ Maintenance complete!"
EOF

    chmod +x $INSTALL_DIR/scripts/maintenance.sh
    
    # Backup script
    cat > $INSTALL_DIR/scripts/backup.sh << 'EOF'
#!/bin/bash
# Cryonith Pi Backup Script

BACKUP_DIR="/opt/cryonith/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/cryonith_backup_$DATE.tar.gz"

echo "💾 Starting Cryonith Pi Backup..."

# Create backup directory
mkdir -p $BACKUP_DIR

# Create backup
tar -czf $BACKUP_FILE \
    --exclude='/opt/cryonith/venv' \
    --exclude='/opt/cryonith/logs' \
    --exclude='/opt/cryonith/backups' \
    /opt/cryonith/

echo "📦 Backup created: $BACKUP_FILE"

# Clean old backups (keep last 5)
cd $BACKUP_DIR
ls -t cryonith_backup_*.tar.gz | tail -n +6 | xargs -r rm --

echo "✅ Backup complete!"
EOF

    chmod +x $INSTALL_DIR/scripts/backup.sh
    
    print_success "Monitoring scripts created"
}

# Setup cron jobs
setup_cron() {
    print_status "Setting up cron jobs..."
    
    # Add cron jobs
    (crontab -l 2>/dev/null; echo "0 2 * * 0 /opt/cryonith/scripts/maintenance.sh >> /opt/cryonith/logs/maintenance.log 2>&1") | crontab -
    (crontab -l 2>/dev/null; echo "0 1 * * * /opt/cryonith/scripts/backup.sh >> /opt/cryonith/logs/backup.log 2>&1") | crontab -
    
    print_success "Cron jobs configured"
}

# Main deployment function
main() {
    print_status "🚀 Starting Cryonith Pi deployment..."
    
    # Check if running on Pi
    check_pi_environment
    
    # Update system
    update_system
    
    # Create application structure
    create_app_structure
    
    # Setup Python environment
    setup_python_env
    
    # Create main application
    create_main_app
    
    # Configure Nginx
    configure_nginx
    
    # Create systemd service
    create_systemd_service
    
    # Create monitoring scripts
    create_scripts
    
    # Setup cron jobs
    setup_cron
    
    # Start the service
    print_status "Starting Cryonith Pi service..."
    sudo systemctl start cryonith-pi
    
    # Wait for startup
    sleep 5
    
    # Run initial health check
    print_status "Running health check..."
    $INSTALL_DIR/scripts/monitor.sh
    
    # Final summary
    print_success "🎉 Cryonith Pi Deployment Complete!"
    echo ""
    echo "📊 Deployment Summary:"
    echo "  • Installation Directory: $INSTALL_DIR"
    echo "  • Python Environment: $INSTALL_DIR/venv"
    echo "  • Database: SQLite at $INSTALL_DIR/data/sqlite/trading.db"
    echo "  • Logs: $INSTALL_DIR/logs/"
    echo ""
    echo "🔗 Access URLs:"
    local_ip=$(hostname -I | awk '{print $1}')
    echo "  • Local: http://localhost"
    echo "  • Network: http://$local_ip"
    echo "  • API: http://$local_ip/api"
    echo "  • Health: http://$local_ip/health"
    echo ""
    echo "🛠️  Management Commands:"
    echo "  • Status: sudo systemctl status cryonith-pi"
    echo "  • Restart: sudo systemctl restart cryonith-pi"
    echo "  • Monitor: $INSTALL_DIR/scripts/monitor.sh"
    echo "  • Maintenance: $INSTALL_DIR/scripts/maintenance.sh"
    echo "  • Backup: $INSTALL_DIR/scripts/backup.sh"
    echo ""
    echo "✅ Cryonith Pi is ready for trading!"
}

# Run main function
main "$@" 