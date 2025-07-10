#!/bin/bash
# Fix Tailscale networking issues
echo "🔧 Fixing Tailscale networking configuration..."

# Fix IPv6 forwarding
echo "📡 Enabling IPv6 forwarding..."
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Fix UDP GRO forwarding on eth0
echo "⚡ Configuring UDP GRO forwarding..."
sudo ethtool -K eth0 rx-udp-gro-forwarding on 2>/dev/null || echo "UDP GRO forwarding already optimal or not supported"

# Restart Tailscale with better configuration
echo "🔄 Restarting Tailscale..."
sudo tailscale down
sleep 2
sudo tailscale up --accept-routes --advertise-routes=192.168.2.0/24 --accept-dns=false

echo "✅ Tailscale networking fixes applied"
echo "🧪 Testing connection..."
sudo tailscale status
