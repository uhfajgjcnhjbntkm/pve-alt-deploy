# Proxmox Alt Workstation Deployer

Automated deployment of Alt Workstation VMs in Proxmox VE using images from Yandex Disk.

## Features

- Automated VM creation and configuration
- Download from Yandex Disk with checksum verification
- Cloud-init support
- Flexible configuration
- Caching for faster redeployment

## Quick Start

1. Clone the repository:
```bash
git clone https://github.com/yourusername/pve-alt-deploy.git
cd pve-alt-deploy
./setup-pve-node.sh
./deploy-alt-vm.sh
