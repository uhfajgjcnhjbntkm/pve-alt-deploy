#!/bin/bash

# Setup Proxmox node for Alt Workstation deployment

set -e

echo "Setting up Proxmox node for Alt Workstation deployment..."

# Install required packages
apt update
apt install -y wget curl jq sudo

# Create cache directory
mkdir -p /var/cache/pve-alt-deploy
chmod 755 /var/cache/pve-alt-deploy

# Check available storage
echo "Available storage:"
pvesm status

# Check network bridges
echo "Network bridges:"
cat /etc/network/interfaces | grep -A5 vmbr

echo "Proxmox node setup completed!"
echo "Please ensure you have:"
echo "1. Sufficient storage space"
echo "2. Network bridge configured"
echo "3. Internet connectivity for downloads"
