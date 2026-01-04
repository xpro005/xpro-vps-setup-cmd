#!/bin/bash
set -euo pipefail

# =============================
# Enhanced Multi-VM Manager
# =============================

display_header() {
    clear
    cat << "HEADER_EOF"
========================================================================
                  __   __   _____    _____     ___  
                  \ \ / /  |  __ \  |  __ \   / _ \ 
                   \ V /   | |__) | | |__) | | | | |
                    > <    |  ___/  |  _  /  | | | |
                   / . \   | |      | | \ \  | |_| |
                  /_/ \_\  |_|      |_|  \_\\  \___/
========================================================================
HEADER_EOF
    echo
}

print_status() {
    local type=$1
    local message=$2
    case $type in
        "INFO") echo -e "\033[1;34m📋 [INFO]\033[0m $message" ;;
        "WARN") echo -e "\033[1;33m⚠️  [WARN]\033[0m $message" ;;
        "ERROR") echo -e "\033[1;31m❌ [ERROR]\033[0m $message" ;;
        "SUCCESS") echo -e "\033[1;32m✅ [SUCCESS]\033[0m $message" ;;
        "INPUT") echo -e "\033[1;36m🎯 [INPUT]\033[0m $message" ;;
        *) echo "[$type] $message" ;;
    esac
}

check_image_lock() {
    local img_file=$1
    local vm_name=$2
    if lsof "$img_file" 2>/dev/null | grep -q qemu-system; then
        print_status "WARN" "🔒 Image file $img_file is in use"
        local pid=$(lsof "$img_file" 2>/dev/null | grep qemu-system | awk '{print $2}' | head -1)
        if [[ -n "$pid" ]]; then
            print_status "INFO" "🔎 Process ID: $pid"
            if ps -p "$pid" -o cmd= | grep -q "$vm_name"; then
                read -p "$(print_status "INPUT" "🔄 Kill and restart? (y/N): ")" kill_choice
                if [[ "$kill_choice" =~ ^[Yy]$ ]]; then
                    kill -9 "$pid"
                    return 0
                fi
            fi
        fi
        return 1
    fi
    return 0
}

validate_input() {
    local type=$1
    local value=$2
    case $type in
        "number") [[ "$value" =~ ^[0-9]+$ ]] || return 1 ;;
        "size") [[ "$value" =~ ^[0-9]+[GgMm]$ ]] || return 1 ;;
        "port") [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge 22 ] && [ "$value" -le 65535 ] || return 1 ;;
        "name") [[ "$value" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1 ;;
    esac
    return 0
}

check_dependencies() {
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img" "lsof")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            print_status "ERROR" "🛠️ Missing: $dep. Run: pkg install qemu-system-x86-64-headless wget cloud-utils openssl lsof"
            exit 1
        fi
    done
}

get_vm_list() { find "$VM_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort; }

load_vm_config() {
    local config="$VM_DIR/$1.conf"
    [ -f "$config" ] && source "$config" || return 1
}

save_vm_config() {
    cat > "$VM_DIR/$VM_NAME.conf" <<CONFIG_EOF
VM_NAME="$VM_NAME"
OS_TYPE="$OS_TYPE"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
DISK_SIZE="$DISK_SIZE"
MEMORY="$MEMORY"
CPUS="$CPUS"
SSH_PORT="$SSH_PORT"
GUI_MODE="$GUI_MODE"
IMG_FILE="$IMG_FILE"
SEED_FILE="$SEED_FILE"
CONFIG_EOF
}

create_new_vm() {
    print_status "INFO" "🆕 Setup new VM"
    read -p "Enter VM Name: " VM_NAME
    read -p "Enter Username: " USERNAME
    read -p "Enter Password: " PASSWORD
    DISK_SIZE="20G"; MEMORY="2048"; CPUS="2"; SSH_PORT="2222"; GUI_MODE="false"
    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    
    print_status "INFO" "📥 Creating disk..."
    qemu-img create -f qcow2 "$IMG_FILE" "$DISK_SIZE"
    
    cat > user-data <<UD_EOF
#cloud-config
password: $PASSWORD
chpasswd: { expire: False }
ssh_pwauth: True
UD_EOF
    cloud-localds "$SEED_FILE" user-data
    save_vm_config
    print_status "SUCCESS" "🚀 VM Created!"
}

start_vm() {
    load_vm_config "$1" || return 1
    print_status "INFO" "🚀 Starting $VM_NAME..."
    qemu-system-x86_64 -m "$MEMORY" -smp "$CPUS" -drive "file=$IMG_FILE,format=qcow2" \
        -drive "file=$SEED_FILE,format=raw" -netdev "user,id=n1,hostfwd=tcp::$SSH_PORT-:22" \
        -device virtio-net-pci,netdev=n1 -nographic
}

main_menu() {
    while true; do
        display_header
        vms=($(get_vm_list))
        echo "1) 🆕 Create VM"
        [ ${#vms[@]} -gt 0 ] && echo "2) 🚀 Start VM"
        echo "0) 👋 Exit"
        read -p "Choice: " c
        case $c in
            1) create_new_vm ;;
            2) read -p "VM Name: " n; start_vm "$n" ;;
            0) exit 0 ;;
        esac
    done
}

VM_DIR="$HOME/vms"; mkdir -p "$VM_DIR"
check_dependencies
main_menu
