#!/bin/bash

# PVE Alt Workstation Deployment Script
# GitHub: https://github.com/yourusername/pve-alt-deploy

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Configuration
CONFIG_FILE="$(dirname "$0")/config/alt-workstation.conf"
TEMPLATES_DIR="$(dirname "$0")/templates"
CACHE_DIR="/var/cache/pve-alt-deploy"

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        # Default configuration
        VM_ID="100"
        VM_NAME="alt-workstation"
        VM_MEMORY="4096"
        VM_CORES="2"
        VM_DISK_SIZE="32G"
        VM_BRIDGE="vmbr0"
        VM_STORAGE="local-lvm"
        ALT_IMAGE_URL="https://disk.yandex.ru/d/your_alt_image_path/alt-workstation.qcow2"
        ALT_IMAGE_CHECKSUM="https://mega.nz/file/XwAWELqT#kv2_OysAz3NcfXmuBXhqHes0UmZzABkRYCCC2nqtVMg"
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if running on Proxmox
    if [[ ! -f /etc/pve/version ]]; then
        error "This script must be run on a Proxmox VE host"
    fi
    
    # Check required tools
    command -v qm >/dev/null 2>&1 || error "qm command not found"
    command -v wget >/dev/null 2>&1 || error "wget not installed"
    command -v curl >/dev/null 2>&1 || error "curl not installed"
    
    # Create cache directory
    mkdir -p "$CACHE_DIR"
}

# Download image from Yandex Disk
download_image() {
    local image_name="alt-workstation.qcow2"
    local cache_path="$CACHE_DIR/$image_name"
    
    if [[ -f "$cache_path" ]]; then
        log "Using cached image: $cache_path"
        echo "$cache_path"
        return 0
    fi
    
    log "Downloading Alt Workstation image from Yandex Disk..."
    
    # Method 1: Direct download (if public link)
    if wget -O "$cache_path" "$ALT_IMAGE_URL"; then
        log "Image downloaded successfully"
        echo "$cache_path"
        return 0
    fi
    
    # Method 2: Using yandex-disk CLI (alternative)
    warn "Direct download failed, trying alternative methods..."
    
    # Method 3: Using curl with token (if available)
    if [[ -n "$YANDEX_OAUTH_TOKEN" ]]; then
        log "Trying authenticated download..."
        if download_with_oauth "$cache_path"; then
            echo "$cache_path"
            return 0
        fi
    fi
    
    error "Failed to download image from Yandex Disk"
}

# Download using OAuth token
download_with_oauth() {
    local output_path="$1"
    
    # Get download link using Yandex Disk API
    local download_url=$(curl -s -H "Authorization: OAuth $YANDEX_OAUTH_TOKEN" \
        "https://cloud-api.yandex.net/v1/disk/resources/download?path=alt-workstation.qcow2" | \
        grep -o '"href":"[^"]*' | cut -d'"' -f4)
    
    if [[ -n "$download_url" ]]; then
        curl -L -o "$output_path" "$download_url"
        return $?
    fi
    
    return 1
}

# Verify image checksum
verify_image() {
    local image_path="$1"
    
    if [[ -n "$ALT_IMAGE_CHECKSUM" ]]; then
        log "Verifying image checksum..."
        
        local checksum_file="$CACHE_DIR/alt-workstation.sha256"
        wget -O "$checksum_file" "$ALT_IMAGE_CHECKSUM" 2>/dev/null || {
            warn "Checksum verification skipped - cannot download checksum file"
            return 0
        }
        
        local expected_checksum=$(cat "$checksum_file")
        local actual_checksum=$(sha256sum "$image_path" | cut -d' ' -f1)
        
        if [[ "$expected_checksum" == "$actual_checksum" ]]; then
            log "Checksum verification passed"
        else
            error "Checksum verification failed"
        fi
    else
        warn "Checksum verification skipped - no checksum URL provided"
    fi
}

# Create VM
create_vm() {
    local vm_id="$1"
    local vm_name="$2"
    local image_path="$3"
    
    log "Creating VM $vm_id ($vm_name)"
    
    # Check if VM already exists
    if qm list | grep -q " $vm_id "; then
        error "VM $vm_id already exists"
    fi
    
    # Create VM
    qm create "$vm_id" \
        --name "$vm_name" \
        --memory "$VM_MEMORY" \
        --cores "$VM_CORES" \
        --net0 "virtio,bridge=$VM_BRIDGE" \
        --scsihw "virtio-scsi-pci" \
        --bootdisk "scsi0" \
        --ostype "l26" \
        --description "Alt Workstation deployed via script"
    
    # Import disk
    log "Importing disk image..."
    qm importdisk "$vm_id" "$image_path" "$VM_STORAGE"
    
    # Attach disk
    qm set "$vm_id" --scsi0 "$VM_STORAGE:vm-${vm_id}-disk-0"
    
    # Resize disk if needed
    if [[ -n "$VM_DISK_SIZE" ]]; then
        log "Resizing disk to $VM_DISK_SIZE"
        qm resize "$vm_id" scsi0 "$VM_DISK_SIZE"
    fi
    
    # Configure display
    qm set "$vm_id" --vga "std" --serial0 "socket" --serial1 "socket"
    
    # Enable QEMU guest agent
    qm set "$vm_id" --agent 1
    
    # Configure boot order
    qm set "$vm_id" --boot "order=scsi0"
    
    log "VM $vm_id created successfully"
}

# Configure cloud-init (if available)
configure_cloud_init() {
    local vm_id="$1"
    
    if [[ -f "$TEMPLATES_DIR/cloud-init.yaml" ]]; then
        log "Configuring cloud-init..."
        
        qm set "$vm_id" --ide2 "$VM_STORAGE:cloudinit"
        qm set "$vm_id" --cipassword "alt@123"  # Change this!
        qm set "$vm_id" --ciuser "alt"
        
        # You can add more cloud-init settings here
    else
        warn "Cloud-init configuration skipped - template not found"
    fi
}

# Start VM
start_vm() {
    local vm_id="$1"
    
    log "Starting VM $vm_id"
    qm start "$vm_id"
    
    # Wait for VM to start
    local max_wait=60
    local count=0
    
    while [[ $count -lt $max_wait ]]; do
        if qm status "$vm_id" | grep -q "running"; then
            log "VM $vm_id is now running"
            
            # Get VM IP (if QEMU agent is installed in the image)
            local vm_ip=$(qm guest exec "$vm_id" -- ip route get 1 2>/dev/null | grep -oP 'src \K\S+' | head -1)
            if [[ -n "$vm_ip" ]]; then
                log "VM IP address: $vm_ip"
            fi
            
            return 0
        fi
        sleep 2
        ((count++))
    done
    
    warn "VM started but may not be fully ready yet"
}

# Main deployment function
deploy_alt_workstation() {
    local custom_vm_id="$1"
    local custom_vm_name="$2"
    
    load_config
    
    # Use custom values if provided
    [[ -n "$custom_vm_id" ]] && VM_ID="$custom_vm_id"
    [[ -n "$custom_vm_name" ]] && VM_NAME="$custom_vm_name"
    
    log "Starting Alt Workstation deployment"
    log "VM ID: $VM_ID"
    log "VM Name: $VM_NAME"
    log "Memory: $VM_MEMORY"
    log "Cores: $VM_CORES"
    
    check_prerequisites
    
    local image_path=$(download_image)
    verify_image "$image_path"
    
    create_vm "$VM_ID" "$VM_NAME" "$image_path"
    configure_cloud_init "$VM_ID"
    start_vm "$VM_ID"
    
    log "Alt Workstation deployment completed successfully!"
    log "VM Console: https://$(hostname):8006/?console=kvm&novnc=1&vmid=$VM_ID"
}

# Help function
show_help() {
    cat << EOF
Alt Workstation Proxmox Deployer

Usage: $0 [OPTIONS]

Options:
  -i, --id ID          VM ID (default: 100)
  -n, --name NAME      VM Name (default: alt-workstation)
  -c, --config FILE    Config file path
  --download-only      Download image only, don't create VM
  --setup-node         Setup Proxmox node requirements
  -h, --help          Show this help

Examples:
  $0                                # Deploy with default settings
  $0 -i 200 -n "alt-dev"           # Deploy with custom ID and name
  $0 --download-only               # Download image only
  $0 --setup-node                  # Setup Proxmox node

Configuration:
  Edit config/alt-workstation.conf to change default settings
  Set YANDEX_OAUTH_TOKEN environment variable for private links

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--id)
            VM_ID_CUSTOM="$2"
            shift 2
            ;;
        -n|--name)
            VM_NAME_CUSTOM="$2"
            shift 2
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --download-only)
            load_config
            download_image
            exit 0
            ;;
        --setup-node)
            exec "$(dirname "$0")/setup-pve-node.sh"
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Main execution
deploy_alt_workstation "$VM_ID_CUSTOM" "$VM_NAME_CUSTOM"
