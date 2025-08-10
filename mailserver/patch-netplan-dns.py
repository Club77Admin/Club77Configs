#!/usr/bin/env python3
# patch-netplan-dns.py - Patch netplan with DNS-resolved IPs

import yaml
import subprocess
import sys
import shutil
import re
from datetime import datetime

def get_dns_record(hostname, record_type):
    """Get DNS record using dig"""
    try:
        result = subprocess.run(['dig', '+short', '+time=5', '+tries=3', hostname, record_type], 
                              capture_output=True, text=True, timeout=15)
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip().split('\n')[0]
    except subprocess.TimeoutExpired:
        pass
    return None

def validate_ip(ip, version):
    """Basic IP validation"""
    if version == 4:
        pattern = r'^(\d{1,3}\.){3}\d{1,3}$'
    else:  # IPv6
        pattern = r'^[0-9a-fA-F:]+$'
    return re.match(pattern, ip) is not None

def main():
    hostname = "mail.club77.org"
    netplan_file = "/etc/netplan/50-cloud-init.yaml"
    backup_file = f"{netplan_file}.backup"
    
    print(f"Querying DNS for {hostname}...")
    
    # Get IPs from DNS
    ipv4 = get_dns_record(hostname, 'A')
    ipv6 = get_dns_record(hostname, 'AAAA')
    
    if not ipv4 or not validate_ip(ipv4, 4):
        print(f"ERROR: Could not get valid IPv4 for {hostname}")
        sys.exit(1)
        
    if not ipv6 or not validate_ip(ipv6, 6):
        print(f"ERROR: Could not get valid IPv6 for {hostname}")
        sys.exit(1)
    
    print(f"Found: IPv4={ipv4}, IPv6={ipv6}")
    
    # Backup original
    shutil.copy2(netplan_file, backup_file)
    
    try:
        # Load current netplan config
        with open(netplan_file, 'r') as f:
            config = yaml.safe_load(f)
        
        # Get current addresses or create empty list
        addresses = config['network']['ethernets']['eth0'].get('addresses', [])
        
        # Add new IPs if not already present
        new_ipv4 = f"{ipv4}/24"
        new_ipv6 = f"{ipv6}/64"
        
        if new_ipv4 not in addresses:
            addresses.append(new_ipv4)
            print(f"Added {new_ipv4}")
        
        if new_ipv6 not in addresses:
            addresses.append(new_ipv6)
            print(f"Added {new_ipv6}")
        
        # Update config
        config['network']['ethernets']['eth0']['addresses'] = addresses
        
        # Write updated config
        with open(netplan_file, 'w') as f:
            yaml.dump(config, f, default_flow_style=False, sort_keys=False)
        
        # Apply the configuration (changed from 'try')
        result = subprocess.run(['netplan', 'apply'], 
                              capture_output=True, text=True)
        
        if result.returncode != 0:
            print("ERROR: Failed to apply netplan config, restoring backup")
            print(f"Error: {result.stderr}")
            shutil.copy2(backup_file, netplan_file)
            sys.exit(1)
        
        print("Successfully updated netplan configuration")
        
    except Exception as e:
        print(f"ERROR: {e}")
        shutil.copy2(backup_file, netplan_file)
        sys.exit(1)

if __name__ == "__main__":
    main()
