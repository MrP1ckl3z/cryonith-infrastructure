#!/bin/bash

# Cryonith Backend Deployment Script
# Deploy cryonith-backend APIs to AWS/Pi infrastructure

set -e

echo "🔧 Starting Cryonith Backend Deployment..."

# Configuration
BACKEND_REPO=${BACKEND_REPO:-"https://github.com/MrP1ckl3z/cryonith-backend.git"}
DEPLOY_DIR=${DEPLOY_DIR:-"/opt/cryonith-backend"}
BACKEND_PORT=${BACKEND_PORT:-8000}
API_PORT=${API_PORT:-5000}

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

# Clone or update backend repository
deploy_backend_code() {
    print_status "Deploying backend code..."
    
    if [ -d "$DEPLOY_DIR" ]; then
        print_status "Updating existing backend..."
        cd "$DEPLOY_DIR"
        git pull origin main
    else
        print_status "Cloning backend repository..."
        git clone "$BACKEND_REPO" "$DEPLOY_DIR"
        cd "$DEPLOY_DIR"
    fi
    
    print_success "Backend code deployed"
}

# Setup backend environment
setup_backend_environment() {
    print_status "Setting up backend environment..."
    
    cd "$DEPLOY_DIR"
    
    # Check if it's a Python backend
    if [ -f "requirements.txt" ]; then
        print_status "Detected Python backend"
        
        # Create virtual environment
        python3 -m venv venv
        source venv/bin/activate
        
        # Install dependencies
        pip install --upgrade pip
        pip install -r requirements.txt
        
        # Install additional dependencies for production
        pip install gunicorn supervisor prometheus-client
        
    elif [ -f "package.json" ]; then
        print_status "Detected Node.js backend"
        
        # Install Node.js dependencies
        npm install
        npm install -g pm2
        
    elif [ -f "go.mod" ]; then
        print_status "Detected Go backend"
        
        # Build Go application
        go mod download
        go build -o backend-server
        
    else
        print_warning "Unknown backend type, manual setup may be required"
    fi
    
    print_success "Backend environment configured"
}

# Create backend configuration
create_backend_config() {
    print_status "Creating backend configuration..."
    
    cd "$DEPLOY_DIR"
    
    # Create environment configuration
    cat > .env.production << EOF
# Cryonith Backend Production Configuration
NODE_ENV=production
PORT=$BACKEND_PORT
API_PORT=$API_PORT

# Database Configuration
DATABASE_URL=sqlite:///data/trading.db
REDIS_URL=redis://localhost:6379

# API Keys (to be filled)
ALPHA_VANTAGE_API_KEY=your_key_here
POLYGON_API_KEY=your_key_here
FINNHUB_API_KEY=your_key_here

# Security
JWT_SECRET=your_jwt_secret_here
API_KEY=your_api_key_here

# Monitoring
PROMETHEUS_ENABLED=true
PROMETHEUS_PORT=9090

# Logging
LOG_LEVEL=info
LOG_FILE=/var/log/cryonith-backend.log
EOF
    
    print_success "Backend configuration created"
}

# Create systemd service for backend
create_backend_service() {
    print_status "Creating backend service..."
    
    # Detect backend type and create appropriate service
    if [ -f "$DEPLOY_DIR/requirements.txt" ]; then
        # Python backend service
        sudo tee /etc/systemd/system/cryonith-backend.service << EOF
[Unit]
Description=Cryonith Backend API Server
After=network.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=$DEPLOY_DIR
Environment=PATH=$DEPLOY_DIR/venv/bin
EnvironmentFile=$DEPLOY_DIR/.env.production
ExecStart=$DEPLOY_DIR/venv/bin/gunicorn --config gunicorn.conf.py app:app
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

        # Create Gunicorn config
        cat > "$DEPLOY_DIR/gunicorn.conf.py" << EOF
bind = "0.0.0.0:$BACKEND_PORT"
workers = 4
worker_class = "sync"
worker_connections = 1000
timeout = 30
keepalive = 2
max_requests = 1000
max_requests_jitter = 50
preload_app = True
EOF
        
    elif [ -f "$DEPLOY_DIR/package.json" ]; then
        # Node.js backend service
        sudo tee /etc/systemd/system/cryonith-backend.service << EOF
[Unit]
Description=Cryonith Backend API Server (Node.js)
After=network.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=$DEPLOY_DIR
EnvironmentFile=$DEPLOY_DIR/.env.production
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    fi
    
    # Enable and start service
    sudo systemctl daemon-reload
    sudo systemctl enable cryonith-backend
    sudo systemctl start cryonith-backend
    
    print_success "Backend service created and started"
}

# Configure Nginx for backend
configure_nginx_backend() {
    print_status "Configuring Nginx for backend..."
    
    sudo tee /etc/nginx/sites-available/cryonith-backend << EOF
server {
    listen 80;
    server_name _;
    
    # Backend API proxy
    location /api/ {
        proxy_pass http://localhost:$BACKEND_PORT/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # Health check
    location /health {
        proxy_pass http://localhost:$BACKEND_PORT/health;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Metrics endpoint
    location /metrics {
        proxy_pass http://localhost:$BACKEND_PORT/metrics;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    
    # Enable the site
    sudo ln -sf /etc/nginx/sites-available/cryonith-backend /etc/nginx/sites-enabled/
    
    # Test and reload Nginx
    sudo nginx -t
    sudo systemctl reload nginx
    
    print_success "Nginx configured for backend"
}

# Health check
backend_health_check() {
    print_status "Running backend health check..."
    
    # Wait for service to start
    sleep 10
    
    # Check if backend is responding
    if curl -s "http://localhost:$BACKEND_PORT/health" > /dev/null 2>&1; then
        print_success "Backend is healthy and responding"
    else
        print_warning "Backend health check failed - may need manual intervention"
    fi
    
    # Check service status
    if systemctl is-active --quiet cryonith-backend; then
        print_success "Backend service is running"
    else
        print_error "Backend service is not running"
        systemctl status cryonith-backend
    fi
}

# Main deployment function
main() {
    print_status "🚀 Starting Cryonith Backend Deployment..."
    
    # Ensure we're running as root or with sudo
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root or with sudo"
        exit 1
    fi
    
    deploy_backend_code
    setup_backend_environment
    create_backend_config
    create_backend_service
    configure_nginx_backend
    backend_health_check
    
    # Final summary
    print_success "🎉 Backend Deployment Complete!"
    echo ""
    echo "📊 Deployment Summary:"
    echo "  • Backend Repository: $BACKEND_REPO"
    echo "  • Installation Directory: $DEPLOY_DIR"
    echo "  • Backend Port: $BACKEND_PORT"
    echo "  • API Port: $API_PORT"
    echo ""
    echo "🔗 Access URLs:"
    echo "  • Backend API: http://localhost/api/"
    echo "  • Health Check: http://localhost/health"
    echo "  • Metrics: http://localhost/metrics"
    echo ""
    echo "🛠️  Management Commands:"
    echo "  • Status: sudo systemctl status cryonith-backend"
    echo "  • Restart: sudo systemctl restart cryonith-backend"
    echo "  • Logs: sudo journalctl -u cryonith-backend -f"
    echo ""
    echo "✅ Cryonith Backend is ready for production!"
}

# Run main function
main "$@" 