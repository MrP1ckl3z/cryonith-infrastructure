#!/bin/bash

# Tailscale Complete Removal and Reinstall Script
# For Cryonith LLC Pi Setup
# Version: 1.0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root. Run as pi user with sudo privileges."
fi

log "🔧 Starting Tailscale Complete Removal and Reinstall"

# Step 1: Stop Tailscale service
log "🛑 Step 1: Stopping Tailscale service..."
sudo systemctl stop tailscaled 2>/dev/null || warning "Tailscale service not running"
sudo systemctl disable tailscaled 2>/dev/null || warning "Tailscale service not enabled"

# Step 2: Remove Tailscale completely
log "🗑️ Step 2: Removing Tailscale completely..."
sudo apt remove --purge -y tailscale 2>/dev/null || warning "Tailscale package not found"
sudo rm -rf /var/lib/tailscale 2>/dev/null || true
sudo rm -rf /etc/tailscale 2>/dev/null || true
sudo rm -f /etc/systemd/system/tailscaled.service 2>/dev/null || true
sudo rm -f /usr/bin/tailscale 2>/dev/null || true
sudo rm -f /usr/sbin/tailscaled 2>/dev/null || true

# Step 3: Remove Tailscale repository
log "📦 Step 3: Removing old Tailscale repository..."
sudo rm -f /etc/apt/sources.list.d/tailscale.list 2>/dev/null || true
sudo rm -f /usr/share/keyrings/tailscale-archive-keyring.gpg 2>/dev/null || true

# Step 4: Clean up network interfaces
log "🌐 Step 4: Cleaning up network interfaces..."
sudo ip link delete tailscale0 2>/dev/null || warning "No tailscale0 interface to remove"

# Step 5: Fix UFW Firewall for Tailscale
log "🔒 Step 5: Configuring UFW firewall for Tailscale..."

# Reset UFW to ensure clean state
sudo ufw --force reset

# Set default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (essential)
sudo ufw allow ssh

# Allow Docker services
sudo ufw allow 8000:8010/tcp comment 'Docker services'

# Allow Tailscale traffic
sudo ufw allow 41641/udp comment 'Tailscale'
sudo ufw allow in on tailscale0 comment 'Tailscale interface'
sudo ufw allow out on tailscale0 comment 'Tailscale interface'

# Allow Tailscale subnet (100.x.x.x)
sudo ufw allow from 100.0.0.0/8 comment 'Tailscale subnet'

# Enable UFW
sudo ufw --force enable

log "🔒 UFW configured for Tailscale"

# Step 6: Update system
log "📦 Step 6: Updating system..."
sudo apt update -y

# Step 7: Install Tailscale fresh
log "📥 Step 7: Installing Tailscale fresh..."

# Add Tailscale's package signing key and repository
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list

# Update package lists
sudo apt update -y

# Install Tailscale
sudo apt install -y tailscale

# Step 8: Start Tailscale service
log "🚀 Step 8: Starting Tailscale service..."
sudo systemctl enable tailscaled
sudo systemctl start tailscaled

# Wait for service to start
sleep 5

# Step 9: Check service status
log "🔍 Step 9: Checking Tailscale service status..."
if sudo systemctl is-active --quiet tailscaled; then
    log "✅ Tailscale service is running"
else
    error "❌ Tailscale service failed to start"
fi

# Step 10: Show connection instructions
log "📋 Step 10: Tailscale connection instructions..."

echo ""
echo "================================================================"
echo "  🎉 Tailscale Reinstalled Successfully"
echo "================================================================"
echo ""
echo "🔧 NEXT STEPS:"
echo ""
echo "1. Connect to Tailscale (run this command):"
echo "   sudo tailscale up --auth-key=YOUR_AUTH_KEY"
echo ""
echo "2. Or connect interactively:"
echo "   sudo tailscale up"
echo ""
echo "3. Check status:"
echo "   sudo tailscale status"
echo ""
echo "4. Get your Tailscale IP:"
echo "   tailscale ip -4"
echo ""
echo "🔒 FIREWALL CONFIGURED:"
echo "   - UFW allows Tailscale traffic on port 41641/udp"
echo "   - Tailscale subnet (100.x.x.x/8) allowed"
echo "   - Tailscale interface (tailscale0) allowed"
echo "   - SSH and Docker services still accessible"
echo ""
echo "🌐 FIREWALL STATUS:"
sudo ufw status numbered
echo ""
echo "================================================================"

# Step 11: Optional - Show auth key reminder
echo ""
echo "💡 If you have your Tailscale auth key, you can run:"
echo "   sudo tailscale up --auth-key=tskey-auth-kS2swUPBeb11CNTRL-yTismgkWN6MBiRKGLyhF7Me7yNnKdpZn"
echo ""
echo "Otherwise, run 'sudo tailscale up' and follow the URL to authenticate."
echo ""

log "✅ Tailscale setup complete! Ready for authentication." 