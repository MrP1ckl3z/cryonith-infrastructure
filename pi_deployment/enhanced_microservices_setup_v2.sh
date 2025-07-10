#!/bin/bash

# Enhanced Microservices Setup v2 - With Better Error Handling
# For Cryonith LLC Raspberry Pi Trading Infrastructure
# Version: 2.0 (Improved)

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root. Run as pi user with sudo privileges."
fi

# Generate unique identifiers for IP protection
NODE_ID=$(openssl rand -hex 4)
CLUSTER_NAME="compute-node-${NODE_ID}"
DOCKER_NETWORK="mesh-${NODE_ID}"

log "🚀 Starting Cryonith LLC Enhanced Pi Setup v2"
log "📊 Node ID: ${NODE_ID}"
log "🌐 Cluster: ${CLUSTER_NAME}"
log "🔗 Network: ${DOCKER_NETWORK}"

# Step 1: System Update
log "📦 Step 1: Updating system packages..."
sudo apt update -y || error "Failed to update package lists"
sudo apt upgrade -y || error "Failed to upgrade packages"

# Step 2: Install Essential Packages
log "🔧 Step 2: Installing essential packages..."
PACKAGES=(
    "openssh-server"
    "tmux"
    "fail2ban"
    "ufw"
    "python3"
    "python3-pip"
    "python3-venv"
    "git"
    "curl"
    "wget"
    "htop"
    "vim"
    "net-tools"
    "ca-certificates"
    "gnupg"
    "lsb-release"
)

for package in "${PACKAGES[@]}"; do
    log "Installing ${package}..."
    sudo apt install -y "$package" || warning "Failed to install $package, continuing..."
done

# Step 3: Install Docker
log "🐳 Step 3: Installing Docker..."
# Remove old versions
sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Add Docker's official GPG key
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg || error "Failed to add Docker GPG key"

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null || error "Failed to add Docker repository"

# Update package lists
sudo apt update -y || error "Failed to update after adding Docker repo"

# Install Docker Engine
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || error "Failed to install Docker"

# Add user to docker group
sudo usermod -aG docker $USER || error "Failed to add user to docker group"

# Start and enable Docker
sudo systemctl start docker || error "Failed to start Docker"
sudo systemctl enable docker || error "Failed to enable Docker"

# Test Docker installation
log "🧪 Testing Docker installation..."
sudo docker run hello-world || error "Docker test failed"

# Step 4: Install Docker Compose (standalone)
log "🔧 Step 4: Installing Docker Compose..."
COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose || error "Failed to download Docker Compose"
sudo chmod +x /usr/local/bin/docker-compose || error "Failed to make Docker Compose executable"

# Test Docker Compose
docker-compose --version || error "Docker Compose installation failed"

# Step 5: Install Poetry
log "📚 Step 5: Installing Poetry..."
curl -sSL https://install.python-poetry.org | python3 - || error "Failed to install Poetry"
export PATH="$HOME/.local/bin:$PATH"
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

# Step 6: Configure Security
log "🔒 Step 6: Configuring security..."

# Configure UFW
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 8000:8010/tcp  # API services
sudo ufw --force enable

# Configure fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Step 7: Create Project Structure
log "📁 Step 7: Creating project structure..."
mkdir -p ~/cryonith-${NODE_ID}/{config,services,data,logs}
cd ~/cryonith-${NODE_ID}

# Step 8: Create Docker Compose Configuration
log "🐳 Step 8: Creating Docker services..."
cat > docker-compose.yml << EOF
version: '3.8'

networks:
  ${DOCKER_NETWORK}:
    driver: bridge

services:
  api-gateway:
    image: nginx:alpine
    container_name: gateway-${NODE_ID}
    ports:
      - "8000:80"
    volumes:
      - ./config/nginx.conf:/etc/nginx/nginx.conf
    networks:
      - ${DOCKER_NETWORK}
    restart: unless-stopped

  core-api:
    image: python:3.11-slim
    container_name: core-${NODE_ID}
    working_dir: /app
    volumes:
      - ./services/core:/app
      - ./data:/app/data
    ports:
      - "8001:8001"
    networks:
      - ${DOCKER_NETWORK}
    command: ["python", "-m", "flask", "run", "--host=0.0.0.0", "--port=8001"]
    restart: unless-stopped

  agent-orchestrator:
    image: python:3.11-slim
    container_name: orchestrator-${NODE_ID}
    working_dir: /app
    volumes:
      - ./services/orchestrator:/app
      - ./data:/app/data
    ports:
      - "8002:8002"
    networks:
      - ${DOCKER_NETWORK}
    command: ["python", "orchestrator.py"]
    restart: unless-stopped

  trading-agent:
    image: python:3.11-slim
    container_name: trader-${NODE_ID}
    working_dir: /app
    volumes:
      - ./services/trading:/app
      - ./data:/app/data
    ports:
      - "8003:8003"
    networks:
      - ${DOCKER_NETWORK}
    command: ["python", "trading_agent.py"]
    restart: unless-stopped

  risk-agent:
    image: python:3.11-slim
    container_name: risk-${NODE_ID}
    working_dir: /app
    volumes:
      - ./services/risk:/app
      - ./data:/app/data
    ports:
      - "8004:8004"
    networks:
      - ${DOCKER_NETWORK}
    command: ["python", "risk_agent.py"]
    restart: unless-stopped

  data-agent:
    image: python:3.11-slim
    container_name: data-${NODE_ID}
    working_dir: /app
    volumes:
      - ./services/data:/app
      - ./data:/app/data
    ports:
      - "8005:8005"
    networks:
      - ${DOCKER_NETWORK}
    command: ["python", "data_agent.py"]
    restart: unless-stopped

  monitoring:
    image: python:3.11-slim
    container_name: monitor-${NODE_ID}
    working_dir: /app
    volumes:
      - ./services/monitoring:/app
      - ./data:/app/data
      - ./logs:/app/logs
    ports:
      - "8006:8006"
    networks:
      - ${DOCKER_NETWORK}
    command: ["python", "monitoring.py"]
    restart: unless-stopped
EOF

# Step 9: Create Service Templates
log "🤖 Step 9: Creating service templates..."

# Create directories
mkdir -p services/{core,orchestrator,trading,risk,data,monitoring}

# Core API Service
cat > services/core/app.py << 'EOF'
from flask import Flask, jsonify, request
import json
import os
from datetime import datetime

app = Flask(__name__)

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'service': 'core-api'
    })

@app.route('/api/status', methods=['GET'])
def get_status():
    return jsonify({
        'node_id': os.environ.get('NODE_ID', 'unknown'),
        'services': ['core', 'trading', 'risk', 'data', 'monitoring'],
        'uptime': 'active'
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8001, debug=True)
EOF

# Create requirements.txt for each service
for service in core orchestrator trading risk data monitoring; do
    cat > services/${service}/requirements.txt << 'EOF'
flask
requests
python-dotenv
pandas
numpy
aiohttp
asyncio
websockets
EOF
done

# Trading Agent
cat > services/trading/trading_agent.py << 'EOF'
import asyncio
import json
import logging
from datetime import datetime
import aiohttp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class TradingAgent:
    def __init__(self):
        self.active_trades = []
        self.strategies = ['momentum', 'mean_reversion', 'arbitrage']
        
    async def analyze_market(self):
        """Analyze market conditions"""
        logger.info("Analyzing market conditions...")
        # Simulated analysis
        return {
            'timestamp': datetime.now().isoformat(),
            'signal': 'hold',
            'confidence': 0.7,
            'strategy': 'momentum'
        }
    
    async def execute_strategy(self):
        """Execute trading strategy"""
        while True:
            try:
                analysis = await self.analyze_market()
                logger.info(f"Market analysis: {analysis}")
                await asyncio.sleep(30)  # Analysis every 30 seconds
            except Exception as e:
                logger.error(f"Error in strategy execution: {e}")
                await asyncio.sleep(5)

if __name__ == '__main__':
    agent = TradingAgent()
    asyncio.run(agent.execute_strategy())
EOF

# Risk Agent
cat > services/risk/risk_agent.py << 'EOF'
import asyncio
import json
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class RiskAgent:
    def __init__(self):
        self.risk_threshold = 0.05  # 5% risk threshold
        self.portfolio_value = 10000.0
        
    async def assess_risk(self):
        """Assess portfolio risk"""
        logger.info("Assessing portfolio risk...")
        return {
            'timestamp': datetime.now().isoformat(),
            'portfolio_value': self.portfolio_value,
            'risk_level': 'low',
            'max_drawdown': 0.02,
            'recommendations': ['maintain_position']
        }
    
    async def monitor_risk(self):
        """Monitor risk continuously"""
        while True:
            try:
                risk_assessment = await self.assess_risk()
                logger.info(f"Risk assessment: {risk_assessment}")
                await asyncio.sleep(60)  # Risk check every minute
            except Exception as e:
                logger.error(f"Error in risk monitoring: {e}")
                await asyncio.sleep(10)

if __name__ == '__main__':
    agent = RiskAgent()
    asyncio.run(agent.monitor_risk())
EOF

# Data Agent
cat > services/data/data_agent.py << 'EOF'
import asyncio
import json
import logging
from datetime import datetime
import aiohttp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class DataAgent:
    def __init__(self):
        self.data_sources = ['alpha_vantage', 'yahoo_finance', 'coinbase']
        self.collected_data = []
        
    async def collect_market_data(self):
        """Collect market data from various sources"""
        logger.info("Collecting market data...")
        # Simulated data collection
        data = {
            'timestamp': datetime.now().isoformat(),
            'symbol': 'BTC-USD',
            'price': 45000.0,
            'volume': 1000000,
            'source': 'simulated'
        }
        self.collected_data.append(data)
        return data
    
    async def data_pipeline(self):
        """Run data collection pipeline"""
        while True:
            try:
                data = await self.collect_market_data()
                logger.info(f"Collected data: {data}")
                await asyncio.sleep(15)  # Data collection every 15 seconds
            except Exception as e:
                logger.error(f"Error in data collection: {e}")
                await asyncio.sleep(5)

if __name__ == '__main__':
    agent = DataAgent()
    asyncio.run(agent.data_pipeline())
EOF

# Monitoring Service
cat > services/monitoring/monitoring.py << 'EOF'
import asyncio
import json
import logging
from datetime import datetime
import aiohttp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class MonitoringAgent:
    def __init__(self):
        self.services = ['core', 'trading', 'risk', 'data']
        self.health_status = {}
        
    async def check_service_health(self, service, port):
        """Check health of a service"""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(f'http://{service}:{port}/health') as response:
                    if response.status == 200:
                        return {'status': 'healthy', 'service': service}
                    else:
                        return {'status': 'unhealthy', 'service': service}
        except Exception as e:
            logger.error(f"Health check failed for {service}: {e}")
            return {'status': 'down', 'service': service}
    
    async def monitor_system(self):
        """Monitor system health"""
        while True:
            try:
                logger.info("Performing system health check...")
                # Simulate health checks
                for service in self.services:
                    self.health_status[service] = 'healthy'
                
                logger.info(f"System status: {self.health_status}")
                await asyncio.sleep(120)  # Health check every 2 minutes
            except Exception as e:
                logger.error(f"Error in system monitoring: {e}")
                await asyncio.sleep(30)

if __name__ == '__main__':
    monitor = MonitoringAgent()
    asyncio.run(monitor.monitor_system())
EOF

# Step 10: Create Nginx Configuration
log "🌐 Step 10: Creating Nginx configuration..."
mkdir -p config
cat > config/nginx.conf << EOF
events {
    worker_connections 1024;
}

http {
    upstream backend {
        server core-${NODE_ID}:8001;
    }
    
    server {
        listen 80;
        server_name localhost;
        
        location / {
            proxy_pass http://backend;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }
        
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
}
EOF

# Step 11: Create Management Scripts
log "📋 Step 11: Creating management scripts..."

cat > start_services.sh << 'EOF'
#!/bin/bash
echo "🚀 Starting Cryonith services..."
docker-compose up -d
echo "✅ Services started. Use 'docker-compose ps' to check status."
EOF

cat > stop_services.sh << 'EOF'
#!/bin/bash
echo "🛑 Stopping Cryonith services..."
docker-compose down
echo "✅ Services stopped."
EOF

cat > check_status.sh << 'EOF'
#!/bin/bash
echo "📊 Cryonith System Status"
echo "========================"
echo "Docker Services:"
docker-compose ps
echo ""
echo "System Resources:"
free -h
echo ""
echo "Network Status:"
netstat -tulnp | grep -E ":(8000|8001|8002|8003|8004|8005|8006)"
EOF

chmod +x start_services.sh stop_services.sh check_status.sh

# Step 12: Create systemd service for auto-start
log "🔧 Step 12: Creating systemd service..."
sudo tee /etc/systemd/system/cryonith-${NODE_ID}.service > /dev/null << EOF
[Unit]
Description=Cryonith Trading Infrastructure
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/home/pi/cryonith-${NODE_ID}
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
User=pi
Group=pi

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable cryonith-${NODE_ID}

# Step 13: Test Installation
log "🧪 Step 13: Testing installation..."
newgrp docker << EOFNEWGRP
cd ~/cryonith-${NODE_ID}
docker-compose up -d
sleep 10
docker-compose ps
EOFNEWGRP

# Step 14: Final Setup
log "📝 Step 14: Final setup..."

# Create info file
cat > ~/cryonith-${NODE_ID}/INFO.txt << EOF
Cryonith LLC Trading Infrastructure
==================================

Node ID: ${NODE_ID}
Cluster: ${CLUSTER_NAME}
Network: ${DOCKER_NETWORK}
Setup Date: $(date)

Services:
- API Gateway: http://$(hostname -I | awk '{print $1}'):8000
- Core API: http://$(hostname -I | awk '{print $1}'):8001
- Trading Agent: Port 8003
- Risk Agent: Port 8004
- Data Agent: Port 8005
- Monitoring: Port 8006

Management Commands:
- Start services: ./start_services.sh
- Stop services: ./stop_services.sh
- Check status: ./check_status.sh
- View logs: docker-compose logs -f [service_name]

System Service:
- Status: sudo systemctl status cryonith-${NODE_ID}
- Start: sudo systemctl start cryonith-${NODE_ID}
- Stop: sudo systemctl stop cryonith-${NODE_ID}
EOF

# Display completion message
log "🎉 Setup Complete!"
echo ""
echo "================================================================"
echo "  Cryonith LLC Enhanced Trading Infrastructure Setup Complete"
echo "================================================================"
echo ""
echo "Node ID: ${NODE_ID}"
echo "Cluster: ${CLUSTER_NAME}"
echo "Project Directory: ~/cryonith-${NODE_ID}"
echo ""
echo "Services Available:"
echo "  - API Gateway: http://$(hostname -I | awk '{print $1}'):8000"
echo "  - Core API: http://$(hostname -I | awk '{print $1}'):8001"
echo "  - Trading Agent: Port 8003"
echo "  - Risk Agent: Port 8004"
echo "  - Data Agent: Port 8005"
echo "  - Monitoring: Port 8006"
echo ""
echo "Next Steps:"
echo "1. Reboot the Pi: sudo reboot"
echo "2. SSH back in and check: cd ~/cryonith-${NODE_ID} && ./check_status.sh"
echo "3. View service logs: docker-compose logs -f"
echo ""
echo "🔐 Security: UFW firewall enabled, fail2ban active"
echo "📁 All files saved in: ~/cryonith-${NODE_ID}/"
echo "================================================================" 