#!/bin/bash

# Simple Docker Setup for Cryonith LLC
# Version: 1.0 (Get Docker working first)

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

log "🚀 Starting Simple Docker Setup for Cryonith LLC"

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root. Run as pi user with sudo privileges."
fi

# Step 1: System Update
log "📦 Step 1: Updating system..."
sudo apt update -y || error "Failed to update"
sudo apt upgrade -y || error "Failed to upgrade" 

# Step 2: Install Prerequisites
log "🔧 Step 2: Installing prerequisites..."
sudo apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release || error "Failed to install prerequisites"

# Step 3: Add Docker's official GPG key
log "🔑 Step 3: Adding Docker GPG key..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg || error "Failed to add Docker GPG key"

# Step 4: Add Docker repository
log "📦 Step 4: Adding Docker repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null || error "Failed to add Docker repository"

# Step 5: Update package index
log "🔄 Step 5: Updating package index..."
sudo apt update -y || error "Failed to update after adding Docker repo"

# Step 6: Install Docker Engine
log "🐳 Step 6: Installing Docker Engine..."
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || error "Failed to install Docker"

# Step 7: Add user to docker group
log "👤 Step 7: Adding user to docker group..."
sudo usermod -aG docker $USER || error "Failed to add user to docker group"

# Step 8: Start and enable Docker
log "🚀 Step 8: Starting Docker service..."
sudo systemctl start docker || error "Failed to start Docker"
sudo systemctl enable docker || error "Failed to enable Docker"

# Step 9: Install Docker Compose (standalone)
log "🔧 Step 9: Installing Docker Compose..."
COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose || error "Failed to download Docker Compose"
sudo chmod +x /usr/local/bin/docker-compose || error "Failed to make Docker Compose executable"

# Step 10: Test Docker installation
log "🧪 Step 10: Testing Docker installation..."
sudo docker run hello-world || error "Docker test failed"

# Step 11: Test Docker Compose
log "🧪 Step 11: Testing Docker Compose..."
docker-compose --version || error "Docker Compose test failed"

# Step 12: Create a simple test service
log "📋 Step 12: Creating test service..."
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
echo "<h1>Cryonith LLC Test API - Docker Working!</h1>" > app/index.html

# Step 13: Test the service
log "🧪 Step 13: Testing the service..."
newgrp docker << 'EOFNEWGRP'
cd ~/cryonith-test
docker-compose up -d
sleep 5
docker-compose ps
EOFNEWGRP

log "✅ Docker setup complete!"
echo ""
echo "================================================================"
echo "  Docker Setup Complete for Cryonith LLC"
echo "================================================================"
echo ""
echo "Test API running at: http://$(hostname -I | awk '{print $1}'):8000"
echo ""
echo "Next steps:"
echo "1. Reboot the Pi: sudo reboot"
echo "2. SSH back in and test: docker --version"
echo "3. Test service: cd ~/cryonith-test && docker-compose ps"
echo ""
echo "If this works, we can proceed with the full enhanced setup."
echo "================================================================" 