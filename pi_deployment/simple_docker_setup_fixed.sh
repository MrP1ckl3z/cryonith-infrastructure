#!/bin/bash

# Simple Docker Setup for Cryonith LLC - Fixed for Ubuntu
# Version: 1.1 (Fixed Ubuntu compatibility)

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

log "🚀 Starting Simple Docker Setup for Cryonith LLC (Fixed)"

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root. Run as pi user with sudo privileges."
fi

# Detect OS and set appropriate release
log "🔍 Detecting OS..."
OS_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
OS_CODENAME=$(lsb_release -cs)

echo "Detected OS: $OS_ID $OS_CODENAME"

# Map unsupported releases to supported ones
case $OS_CODENAME in
    "plucky"|"oracular")
        DOCKER_RELEASE="noble"  # Use Ubuntu Noble (24.04 LTS)
        warning "Using Ubuntu Noble repository for Docker (your release '$OS_CODENAME' not yet supported)"
        ;;
    "noble"|"jammy"|"focal")
        DOCKER_RELEASE="$OS_CODENAME"
        ;;
    *)
        DOCKER_RELEASE="noble"  # Default to Noble
        warning "Unknown release '$OS_CODENAME', defaulting to Ubuntu Noble"
        ;;
esac

log "Using Docker release: $DOCKER_RELEASE"

# Step 1: Clean up any existing Docker repository
log "🧹 Step 1: Cleaning up existing repositories..."
sudo rm -f /etc/apt/sources.list.d/docker.list
sudo rm -f /etc/apt/keyrings/docker.gpg

# Step 2: System Update
log "📦 Step 2: Updating system..."
sudo apt update -y || error "Failed to update"

# Step 3: Install Prerequisites
log "🔧 Step 3: Installing prerequisites..."
sudo apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release || error "Failed to install prerequisites"

# Step 4: Add Docker's official GPG key
log "🔑 Step 4: Adding Docker GPG key..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg || error "Failed to add Docker GPG key"

# Step 5: Add Docker repository (using Ubuntu, not Debian)
log "📦 Step 5: Adding Docker repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $DOCKER_RELEASE stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null || error "Failed to add Docker repository"

# Step 6: Update package index
log "🔄 Step 6: Updating package index..."
sudo apt update -y || error "Failed to update after adding Docker repo"

# Step 7: Install Docker Engine
log "🐳 Step 7: Installing Docker Engine..."
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || error "Failed to install Docker"

# Step 8: Add user to docker group
log "👤 Step 8: Adding user to docker group..."
sudo usermod -aG docker $USER || error "Failed to add user to docker group"

# Step 9: Start and enable Docker
log "🚀 Step 9: Starting Docker service..."
sudo systemctl start docker || error "Failed to start Docker"
sudo systemctl enable docker || error "Failed to enable Docker"

# Step 10: Test Docker installation
log "🧪 Step 10: Testing Docker installation..."
sudo docker run hello-world || error "Docker test failed"

# Step 11: Install Docker Compose (standalone) - fallback if plugin didn't work
log "🔧 Step 11: Installing Docker Compose standalone..."
if ! command -v docker-compose &> /dev/null; then
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
    sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose || error "Failed to download Docker Compose"
    sudo chmod +x /usr/local/bin/docker-compose || error "Failed to make Docker Compose executable"
else
    log "Docker Compose plugin already installed"
fi

# Step 12: Test Docker Compose
log "🧪 Step 12: Testing Docker Compose..."
if command -v docker-compose &> /dev/null; then
    docker-compose --version || error "Docker Compose test failed"
else
    # Try plugin version
    docker compose version || error "Docker Compose plugin test failed"
fi

# Step 13: Create a simple test service
log "📋 Step 13: Creating test service..."
mkdir -p ~/cryonith-test
cd ~/cryonith-test

cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  test-api:
    image: python:3.11-slim
    container_name: cryonith-test-api
    ports:
      - "8000:8000"
    working_dir: /app
    volumes:
      - ./app:/app
    command: ["python", "-m", "http.server", "8000"]
    restart: unless-stopped
EOF

mkdir -p app
cat > app/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Cryonith LLC Test</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 50px; text-align: center; }
        h1 { color: #2c3e50; }
        .status { background: #2ecc71; color: white; padding: 20px; border-radius: 10px; }
    </style>
</head>
<body>
    <h1>🚀 Cryonith LLC</h1>
    <div class="status">
        <h2>✅ Docker Working Successfully!</h2>
        <p>Trading Infrastructure Ready</p>
    </div>
</body>
</html>
EOF

# Step 14: Test the service with proper group handling
log "🧪 Step 14: Testing the service..."
# Need to handle group membership properly
if groups | grep -q docker; then
    log "User already in docker group, starting service..."
    docker-compose up -d || docker compose up -d
    sleep 5
    docker-compose ps || docker compose ps
else
    log "User not in docker group yet, using sudo..."
    sudo docker-compose up -d || sudo docker compose up -d
    sleep 5
    sudo docker-compose ps || sudo docker compose ps
fi

# Step 15: Show connection info
log "🌐 Step 15: Service information..."
IP_ADDRESS=$(hostname -I | awk '{print $1}')
echo ""
echo "================================================================"
echo "  🎉 Docker Setup Complete for Cryonith LLC"
echo "================================================================"
echo ""
echo "✅ Docker Engine: $(docker --version)"
echo "✅ Docker Compose: $(docker-compose --version 2>/dev/null || docker compose version)"
echo ""
echo "🌐 Test Service: http://$IP_ADDRESS:8000"
echo "📁 Project Directory: ~/cryonith-test"
echo ""
echo "🔧 Commands:"
echo "  View containers: docker ps"
echo "  Stop service: docker-compose down"
echo "  Start service: docker-compose up -d"
echo "  View logs: docker-compose logs"
echo ""
echo "⚠️  IMPORTANT: You may need to log out and back in for docker group to take effect"
echo "   Or run: newgrp docker"
echo ""
echo "🎯 Next Steps:"
echo "1. Test the web interface: curl http://$IP_ADDRESS:8000"
echo "2. If working, proceed with enhanced microservices setup"
echo "================================================================"

log "✅ Setup complete! Docker is ready for Cryonith LLC trading infrastructure." 