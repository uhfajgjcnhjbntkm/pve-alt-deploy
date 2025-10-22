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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config/alt-workstation.conf"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"
CACHE_DIR="/var/cache/pve-alt-deploy"

# Remote Proxmox settings
PVE_HOST=""  # Set this to your Proxmox host IP
PVE_USER="root"
PVE_SSH_KEY="${HOME}/.ssh/id_rsa"

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        log "Configuration loaded from: $CONFIG_FILE"
    else
        # Default configuration
        VM_ID="100"
        VM_NAME="alt-workstation"
        VM_MEMORY="4096"
        VM_CORES="2"
        VM_DISK_SIZE="32G"
        VM_BRIDGE="vmbr0"
        VM_STORAGE="local-lvm"
        ALT_IMAGE_URL="https://mega.nz/file/H1YXCCJQ#1gK8XMUOVYkfWKj2Rbloocyve7cq1d2_ahXIao7IiK8"
        ALT_IMAGE_CHECKSUM="https://mega.nz/file/XwAWELqT#kv2_OysAz3NcfXmuBXhqHes0UmZzABkRYCCC2nqtVMg"
        warn "Using default configuration - config file not found: $CONFIG_FILE"
    fi
}

# Check if running on Proxmox
is_proxmox_host() {
    if [[ -f /etc/pve/version ]] || command -v pvesh >/dev/null 2>&1 || command -v qm >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    if is_proxmox_host; then
        log "Running on Proxmox host"
        PVE_MODE="local"
    elif [[ -n "$PVE_HOST" ]] && ssh -o ConnectTimeout=5 -i "$PVE_SSH_KEY" "${PVE_USER}@${PVE_HOST}" "exit" 2>/dev/null; then
        log "Connected to remote Proxmox host: $PVE_HOST"
        PVE_MODE="remote"
    else
        error "Not running on Proxmox host and no remote host configured."
        echo "Please either:"
        echo "1. Run this script directly on a Proxmox node, OR"
        echo "2. Set PVE_HOST in the script and configure SSH access, OR" 
        echo "3. Use the --remote flag with host specification"
        echo ""
        echo "For remote usage:"
        echo "  - Set PVE_HOST in the script configuration"
        echo "  - Configure SSH key authentication"
        echo "  - Or use: $0 --remote user@proxmox-host"
        exit 1
    fi
    
    # Check required tools
    if [[ "$PVE_MODE" == "local" ]]; then
        command -v qm >/dev/null 2>&1 || error "qm command not found"
        command -v wget >/dev/null 2>&1 || error "wget not installed"
        command -v curl >/dev/null 2>&1 || error "curl not installed"
    else
        ssh -i "$PVE_SSH_KEY" "${PVE_USER}@${PVE_HOST}" "command -v qm >/dev/null 2>&1" || error "qm not found on remote host"
    fi
    
    # Create cache directory
    if [[ "$PVE_MODE" == "local" ]]; then
        mkdir -p "$CACHE_DIR"
    else
        ssh -i "$PVE_SSH_KEY" "${PVE_USER}@${PVE_HOST}" "mkdir -p $CACHE_DIR"
    fi
}

# Execute command based on mode
pve_exec() {
    local command="$1"
    
    if [[ "$PVE_MODE" == "local" ]]; then
        eval "$command"
    else
        ssh -i "$PVE_SSH_KEY" "${PVE_USER}@${PVE_HOST}" "$command"
    fi
}

# File transfer based on mode
pve_transfer() {
    local local_file="$1"
    local remote_file="$2"
    
    if [[ "$PVE_MODE" == "local" ]]; then
        cp "$local_file" "$remote_file"
    else
        scp -i "$PVE_SSH_KEY" "$local_file" "${PVE_USER}@${PVE_HOST}:${remote_file}"
    fi
}

# Download image from Yandex Disk
download_image() {
    local image_name="alt-workstation.qcow2"
    
    if [[ "$PVE_MODE" == "local" ]]; then
        local cache_path="$CACHE_DIR/$image_name"
    else
        local cache_path="$CACHE_DIR/$image_name"
    fi
    
    # Check if image already exists in cache
    if pve_exec "[[ -f \"$cache_path\" ]]"; then
        log "Using cached image: $cache_path"
        echo "$cache_path"
        return 0
    fi
    
    log "Downloading Alt Workstation image from Yandex Disk..."
    
    # Create temp directory for download
    local temp_dir=$(pve_exec "mktemp -d")
    
    # Download using different methods
    if pve_exec "wget -O \"$temp_dir/$image_name\" \"$ALT_IMAGE_URL\""; then
        pve_exec "mv \"$temp_dir/$image_name\" \"$cache_path\""
        pve_exec "rm -rf \"$temp_dir\""
        log "Image downloaded successfully to: $cache_path"
        echo "$cache_path"
        return 0
    else
        pve_exec "rm -rf \"$temp_dir\""
        error "Failed to download image from Yandex Disk"
    fi
}

# Verify image checksum
verify_image() {
    local image_path="$1"
    
    if [[ -n "$ALT_IMAGE_CHECKSUM" ]]; then
        log "Verifying image checksum..."
        
        local temp_dir=$(pve_exec "mktemp -d")
        local checksum_file="$temp_dir/alt-workstation.sha256"
        
        if pve_exec "wget -O \"$checksum_file\" \"$ALT_IMAGE_CHECKSUM\" 2>/dev/null"; then
            local expected_checksum=$(pve_exec "cat \"$checksum_file\"")
            local actual_checksum=$(pve_exec "sha256sum \"$image_path\" | cut -d' ' -f1")
            
            if [[ "$expected_checksum" == "$actual_checksum" ]]; then
                log "Checksum verification passed"
            else
                error "Checksum verification failed"
            fi
        else
            warn "Checksum verification skipped - cannot download checksum file"
        fi
        
        pve_exec "rm -rf \"$temp_dir\""
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
    if pve_exec "qm list | grep -q \" $vm_id \""; then
        error "VM $vm_id already exists"
    fi
    
    # Create VM
    pve_exec "qm create \"$vm_id\" \
        --name \"$vm_name\" \
        --memory \"$VM_MEMORY\" \
        --cores \"$VM_CORES\" \
        --net0 \"virtio,bridge=$VM_BRIDGE\" \
        --scsihw \"virtio-scsi-pci\" \
        --bootdisk \"scsi0\" \
        --ostype \"l26\" \
        --description \"Alt Workstation deployed via script\""
    
    # Import disk
    log "Importing disk image..."
    pve_exec "qm importdisk \"$vm_id\" \"$image_path\" \"$VM_STORAGE\""
    
    # Attach disk
    pve_exec "qm set \"$vm_id\" --scsi0 \"$VM_STORAGE:vm-${vm_id}-disk-0\""
    
    # Resize disk if needed
    if [[ -n "$VM_DISK_SIZE" ]]; then
        log "Resizing disk to $VM_DISK_SIZE"
        pve_exec "qm resize \"$vm_id\" scsi0 \"$VM_DISK_SIZE\""
    fi
    
    # Configure display
    pve_exec "qm set \"$vm_id\" --vga \"std\" --serial0 \"socket\" --serial1 \"socket\""
    
    # Enable QEMU guest agent
    pve_exec "qm set \"$vm_id\" --agent 1"
    
    # Configure boot order
    pve_exec "qm set \"$vm_id\" --boot \"order=scsi0\""
    
    log "VM $vm_id created successfully"
}

# Configure cloud-init
configure_cloud_init() {
    local vm_id="$1"
    
    if [[ -f "$TEMPLATES_DIR/cloud-init.yaml" ]]; then
        log "Configuring cloud-init..."
        
        pve_exec "qm set \"$vm_id\" --ide2 \"$VM_STORAGE:cloudinit\""
        pve_exec "qm set \"$vm_id\" --cipassword \"${CLOUD_INIT_PASSWORD:-alt@123}\""
        pve_exec "qm set \"$vm_id\" --ciuser \"${CLOUD_INIT_USER:-alt}\""
        
        # Transfer cloud-init config if exists
        if [[ -f "$TEMPLATES_DIR/cloud-init.yaml" ]]; then
            local temp_file=$(pve_exec "mktemp")
            pve_transfer "$TEMPLATES_DIR/cloud-init.yaml" "$temp_file"
            pve_exec "qm set \"$vm_id\" --cicustom \"user=$temp_file\""
        fi
        
    else
        warn "Cloud-init configuration skipped - template not found"
    fi
}

# Start VM
start_vm() {
    local vm_id="$1"
    
    log "Starting VM $vm_id"
    pve_exec "qm start \"$vm_id\""
    
    # Wait for VM to start
    local max_wait=60
    local count=0
    
    while [[ $count -lt $max_wait ]]; do
        if pve_exec "qm status \"$vm_id\" | grep -q \"running\""; then
            log "VM $vm_id is now running"
            
            # Try to get VM IP (if QEMU agent is installed)
            local vm_ip=$(pve_exec "qm guest exec \"$vm_id\" -- ip route get 1 2>/dev/null | grep -oP 'src \\K\\S+' | head -1" 2>/dev/null || true)
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

# Setup SSH access to remote Proxmox
setup_ssh_access() {
    local remote_host="$1"
    
    log "Setting up SSH access to $remote_host"
    
    # Generate SSH key if not exists
    if [[ ! -f ~/.ssh/id_rsa ]]; then
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -q
    fi
    
    # Copy public key to remote host
    ssh-copy-id -i ~/.ssh/id_rsa.pub "$remote_host" || {
        error "Failed to setup SSH access. Please manually configure:"
        echo "ssh-copy-id $remote_host"
        exit 1
    }
    
    log "SSH access configured successfully"
}

# Main deployment function
deploy_alt_workstation() {
    local custom_vm_id="$1"
    local custom_vm_name="$2"
    local remote_host="$3"
    
    # Handle remote host specification
    if [[ -n "$remote_host" ]]; then
        PVE_HOST="$remote_host"
        PVE_USER="${remote_host%@*}"
        [[ "$PVE_USER" == "$remote_host" ]] && PVE_USER="root"
        PVE_HOST="${remote_host#*@}"
        setup_ssh_access "$PVE_USER@$PVE_HOST"
    fi
    
    load_config
    
    # Use custom values if provided
    [[ -n "$custom_vm_id" ]] && VM_ID="$custom_vm_id"
    [[ -n "$custom_vm_name" ]] && VM_NAME="$custom_vm_name"
    
    log "Starting Alt Workstation deployment"
    log "Mode: $PVE_MODE"
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
    
    if [[ "$PVE_MODE" == "local" ]]; then
        local pve_host=$(hostname)
    else
        local pve_host="$PVE_HOST"
    fi
    
    log "VM Console: https://${pve_host}:8006/?console=kvm&novnc=1&vmid=$VM_ID"
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
  --remote HOST        Deploy to remote Proxmox host (user@host)
  --download-only      Download image only, don't create VM
  --setup-node         Setup Proxmox node requirements
  -h, --help          Show this help

Examples:
  $0                                # Deploy with default settings (local)
  $0 -i 200 -n "alt-dev"           # Deploy with custom ID and name
  $0 --remote root@192.168.1.10    # Deploy to remote Proxmox host
  $0 --download-only               # Download image only
  $0 --setup-node                  # Setup Proxmox node

Local Deployment:
  Run directly on Proxmox node

Remote Deployment:
  1. Set up SSH key authentication
  2. Use --remote flag or set PVE_HOST in script
  3. Ensure remote host has internet access

Configuration:
  Edit config/alt-workstation.conf to change default settings

EOF
}

# Parse arguments
PVE_MODE=""
VM_ID_CUSTOM=""
VM_NAME_CUSTOM=""
REMOTE_HOST=""

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
        --remote)
            REMOTE_HOST="$2"
            shift 2
            ;;
        --download-only)
            load_config
            check_prerequisites
            download_image
            exit 0
            ;;
        --setup-node)
            exec "${SCRIPT_DIR}/setup-pve-node.sh"
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
deploy_alt_workstation "$VM_ID_CUSTOM" "$VM_NAME_CUSTOM" "$REMOTE_HOST"
