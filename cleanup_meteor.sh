#!/bin/bash

# **METEOR SERVER - COMPLETE CLEANUP SCRIPT**
# Removes all meteor server components and configurations
# Safe to run multiple times

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[CLEANUP]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[CLEANUP]${NC} $1"
}

error() {
    echo -e "${RED}[CLEANUP ERROR]${NC} $1"
}

print_banner() {
    cat << 'BANNER'

███╗   ███╗███████╗████████╗███████╗ ██████╗ ██████╗ 
████╗ ████║██╔════╝╚══██╔══╝██╔════╝██╔═══██╗██╔══██╗
██╔████╔██║█████╗     ██║   █████╗  ██║   ██║██████╔╝
██║╚██╔╝██║██╔══╝     ██║   ██╔══╝  ██║   ██║██╔══██╗
██║ ╚═╝ ██║███████╗   ██║   ███████╗╚██████╔╝██║  ██║
╚═╝     ╚═╝╚══════╝   ╚═╝   ╚══════╝ ╚═════╝ ╚═╝  ╚═╝

    METEOR SERVER CLEANUP UTILITY
    Complete System Cleanup & Removal
    
BANNER
}

cleanup_meteor() {
    print_banner
    
    log "Starting complete Meteor server cleanup..."
    
    # Check root privileges
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Stop and disable all meteor services
    log "Stopping Meteor services..."
    systemctl stop meteor 2>/dev/null || warn "Meteor service not running"
    systemctl stop meteor-healthmon.timer 2>/dev/null || warn "Health monitor timer not running"
    systemctl stop meteor-hangdetector.timer 2>/dev/null || warn "Hang detector timer not running"
    systemctl stop meteor-healthmon.service 2>/dev/null || warn "Health monitor service not running"
    systemctl stop meteor-hangdetector.service 2>/dev/null || warn "Hang detector service not running"
    
    systemctl disable meteor 2>/dev/null || warn "Meteor service not enabled"
    systemctl disable meteor-healthmon.timer 2>/dev/null || warn "Health monitor timer not enabled"
    systemctl disable meteor-hangdetector.timer 2>/dev/null || warn "Hang detector timer not enabled"
    
    # Remove all systemd services
    log "Removing systemd services..."
    rm -f /etc/systemd/system/meteor.service
    rm -f /etc/systemd/system/meteor-healthmon.service
    rm -f /etc/systemd/system/meteor-healthmon.timer
    rm -f /etc/systemd/system/meteor-hangdetector.service
    rm -f /etc/systemd/system/meteor-hangdetector.timer
    systemctl daemon-reload
    
    # Remove user and group
    log "Removing meteor user..."
    userdel -r meteor 2>/dev/null || warn "Meteor user not found"
    groupdel meteor 2>/dev/null || warn "Meteor group not found"
    
    # Remove directories and temp files
    log "Removing Meteor directories and temp files..."
    rm -rf /opt/meteor
    rm -rf /var/lib/meteor
    rm -rf /var/log/meteor
    rm -rf /etc/meteor
    rm -rf /run/meteor
    rm -f /tmp/meteor-failure-count
    
    # Remove system configurations
    log "Removing system configurations..."
    rm -f /etc/sysctl.d/99-meteor.conf
    rm -f /etc/security/limits.d/99-meteor.conf
    rm -f /etc/ld.so.conf.d/meteor.conf
    
    # Remove log rotation
    log "Removing log rotation..."
    rm -f /etc/logrotate.d/meteor
    
    # Remove monitoring
    log "Removing monitoring configurations..."
    rm -f /etc/cron.d/meteor-metrics
    rm -f /etc/cron.d/meteor-health
    
    # Update ldconfig
    ldconfig 2>/dev/null || warn "Could not update library cache"
    
    # Reload sysctl
    sysctl --system >/dev/null 2>&1 || warn "Could not reload sysctl settings"
    
    log "✅ Meteor server cleanup completed successfully!"
    log "All components, configurations, and data have been removed."
}

show_help() {
    cat << HELP
Meteor Server Cleanup Script

USAGE:
    sudo $0              # Complete cleanup
    sudo $0 --help       # Show this help

This script will completely remove:
- Meteor server binaries and libraries
- All configuration files
- System user and directories  
- Systemd service and health monitors
- Health monitoring services (healthmon, hangdetector)
- Log files and rotation
- System optimizations
- Monitoring configurations
- Temporary state files

WARNING: This operation cannot be undone!
All Meteor server data will be permanently lost.

HELP
}

# Main execution
case "${1:-cleanup}" in
    cleanup|--cleanup)
        cleanup_meteor
        ;;
    --help|-h|help)
        show_help
        ;;
    *)
        error "Unknown option: $1"
        show_help
        exit 1
        ;;
esac
