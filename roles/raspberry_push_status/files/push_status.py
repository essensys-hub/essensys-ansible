#!/usr/bin/env python3
import subprocess
import json
import socket
import time
import os
import sys

# Configuration
#GATEWAY_URL = "http://gateway.essensys.fr/api/infos" # User requested HTTP for now
GATEWAY_URL = "https://gateway.essensys.fr/api/infos"

SERVICES = [
    "essensys-backend", 
    "nginx", 
    "traefik", 
    "AdGuardHome"
]

def get_cpu_usage():
    # Read /proc/stat for instantaneous usage
    # We need two readings to calculate usage, so we sleep briefly
    def read_stat():
        with open('/proc/stat', 'r') as f:
            line = f.readline()
            parts = line.split()
            return [int(x) for x in parts[1:6]] # user, nice, system, idle, iowait
    
    try:
        stat1 = read_stat()
        time.sleep(0.5)
        stat2 = read_stat()
        
        total1 = sum(stat1)
        total2 = sum(stat2)
        idle1 = stat1[3] + stat1[4] # idle + iowait
        idle2 = stat2[3] + stat2[4]
        
        diff_total = total2 - total1
        diff_idle = idle2 - idle1
        
        if diff_total == 0: return 0.0
        return 100.0 * (diff_total - diff_idle) / diff_total
    except:
        return 0.0

def get_mem_usage():
    try:
        mem = {}
        with open('/proc/meminfo', 'r') as f:
            for line in f:
                parts = line.split(':')
                if len(parts) == 2:
                    key = parts[0].strip()
                    val = int(parts[1].split()[0]) # kB
                    mem[key] = val
        
        total = mem.get('MemTotal', 1)
        avail = mem.get('MemAvailable', mem.get('MemFree', 0))
        used = total - avail
        return {
            "total_kb": total,
            "used_kb": used,
            "percent": (used / total) * 100.0
        }
    except:
        return {"total_kb": 0, "used_kb": 0, "percent": 0.0}

def get_disk_usage(path='/'):
    try:
        st = os.statvfs(path)
        total = st.f_blocks * st.f_frsize
        used = (st.f_blocks - st.f_bfree) * st.f_frsize
        return {
            "total_bytes": total,
            "used_bytes": used,
            "percent": (used/total)*100
        }
    except:
        return {"total_bytes": 0, "used_bytes": 0, "percent": 0.0}

def get_service_status(service_name):
    try:
        ret = subprocess.call(["systemctl", "is-active", "--quiet", service_name])
        return ret == 0
    except:
        return False

def push_data(payload):
    import urllib.request
    import urllib.error
    
    jsondata = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(GATEWAY_URL, data=jsondata, method='POST')
    req.add_header('Content-Type', 'application/json')
    req.add_header('User-Agent', 'Essensys-Monitor/1.0')
    
    try:
        print(f"Pushing data to: {GATEWAY_URL} ...")
        with urllib.request.urlopen(req, timeout=10) as response:
            print(f"Push success. Code: {response.getcode()}")
            return True
    except urllib.error.HTTPError as e:
        print(f"Push failed: HTTP {e.code} - {e.reason}")
    except urllib.error.URLError as e:
        print(f"Push failed: URL Error - {e.reason}")
    except Exception as e:
        print(f"Push failed: {e}")
    return False

def main():
    data = {
        "hostname": socket.gethostname(),
        "timestamp": time.time(),
        "cpu_usage_percent": round(get_cpu_usage(), 1),
        "memory": get_mem_usage(),
        "disk": get_disk_usage(),
        "services": {}
    }
    
    for svc in SERVICES:
        data["services"][svc] = get_service_status(svc)
        
    # Add client count (ss logic)
    try:
        cmd = "ss -tnH state established '( dport = :80 or dport = :443 or dport = :7070 )' | wc -l"
        output = subprocess.check_output(cmd, shell=True)
        data["client_count"] = int(output.strip())
    except:
        data["client_count"] = 0

    # Print for debug
    # print(json.dumps(data, indent=2))
    
    push_data(data)

if __name__ == "__main__":
    main()
