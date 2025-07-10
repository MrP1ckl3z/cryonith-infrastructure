#!/bin/bash
# Force Tailscale to try direct connections
echo "Trying to establish direct connection..."
sudo tailscale down
sleep 2
sudo tailscale up --accept-routes --advertise-routes=192.168.2.0/24
echo "Tailscale restarted with route advertisement"
echo "Checking status..."
sudo tailscale status
