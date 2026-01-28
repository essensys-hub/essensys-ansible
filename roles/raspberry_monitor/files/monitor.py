#!/usr/bin/env python3
import curses
import time
import subprocess
import threading
import os
import sys
from collections import deque
import re

# Configuration
LOG_FILES = [
    ("/var/logs/Essensys/backend/console.out.log", "Backend"),
    ("/var/log/caddy/access.log", "Caddy"),
    ("/opt/essensys/homeassistant/config/home-assistant.log", "H.Asst")
]

SERVICES = [
    {"name": "Backend", "service": "essensys-backend", "key": "b"},
    {"name": "Caddy", "service": "caddy", "key": "c"},
    {"name": "AdGuard", "service": "AdGuardHome", "key": "a"},
    {"name": "Push", "service": "essensys-push.timer", "key": "p"},
    {"name": "HomeAss", "service": "homeassistant", "key": "h"}
]
REFRESH_RATE = 1.0  # seconds

class SystemMonitor:
    def __init__(self):
        self.cpu_prev = self._read_cpu_stats()
        # Separate buffers for each source
        self.log_buffers = {
            "Backend": deque(maxlen=200),
            "Caddy": deque(maxlen=200),
            "H.Asst": deque(maxlen=200)
        }
        self.log_lock = threading.Lock()
        self.running = True
        
        # Start log reader thread
        self.log_thread = threading.Thread(target=self._tail_log, daemon=True)
        self.log_thread.start()

        # Cache for disk stats
        self.last_disk_check = 0
        self.cached_disk_usage = (0, 0, 0)
        self.cached_logs_size = 0

        # Cache for services
        self.last_service_check = 0
        self.service_cache = {}
        self.service_refresh_interval = 60 # Check every 60s

    def _read_cpu_stats(self):
        try:
            with open('/proc/stat', 'r') as f:
                line = f.readline()
                if line.startswith('cpu '):
                    parts = line.split()
                    # user, nice, system, idle, iowait
                    return [int(x) for x in parts[1:6]]
        except:
            return None
        return None

    def get_cpu_usage(self):
        curr = self._read_cpu_stats()
        if not curr or not self.cpu_prev:
            self.cpu_prev = curr
            return 0.0
        
        # Calculate diffs
        prev_sum = sum(self.cpu_prev)
        curr_sum = sum(curr)
        
        prev_idle = self.cpu_prev[3]
        curr_idle = curr[3]
        if len(self.cpu_prev) > 4:
            prev_idle += self.cpu_prev[4]
            curr_idle += curr[4]
            
        diff_total = curr_sum - prev_sum
        diff_idle = curr_idle - prev_idle
        
        self.cpu_prev = curr
        
        if diff_total == 0: return 0.0
        return 100.0 * (diff_total - diff_idle) / diff_total

    def get_mem_usage(self):
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
            avail = mem.get('MemAvailable', mem.get('MemFree', 0)) # Fallback if MemAvailable missing
            used = total - avail
            return (used / total) * 100.0, used/1024, total/1024
        except:
            return 0.0, 0, 0

    def get_client_count(self):
        try:
            cmd = "ss -tnH state established '( dport = :80 or dport = :443 or dport = :7070 )' | wc -l"
            output = subprocess.check_output(cmd, shell=True)
            return int(output.strip())
        except:
            return 0

    def update_services(self, services_list):
        # Force initial check or check if interval passed
        if self.last_service_check == 0 or (time.time() - self.last_service_check > self.service_refresh_interval):
            for s in services_list:
                name = s['service']
                try:
                    ret = subprocess.call(["systemctl", "is-active", "--quiet", name])
                    self.service_cache[name] = (ret == 0)
                except:
                    self.service_cache[name] = False
            self.last_service_check = time.time()

    def get_service_refresh_remaining(self):
        if self.last_service_check == 0: return 0
        elapsed = time.time() - self.last_service_check
        remaining = self.service_refresh_interval - elapsed
        return max(0, int(remaining))

    def get_service_status(self, service_name):
        return self.service_cache.get(service_name, False)

    def restart_service(self, service_name):
        def _restart():
            subprocess.call(["sudo", "systemctl", "restart", service_name])
            time.sleep(3)
            try:
                ret = subprocess.call(["systemctl", "is-active", "--quiet", service_name])
                self.service_cache[service_name] = (ret == 0)
            except:
                pass
        
        t = threading.Thread(target=_restart)
        t.start()

    def update_disk_stats(self):
        # Update every 120 seconds
        if time.time() - self.last_disk_check > 120:
            self.cached_disk_usage = self._get_disk_usage('/')
            self.cached_logs_size = self._get_dir_size('/var/logs') if os.path.exists('/var/logs') else self._get_dir_size('/var/log')
            self.last_disk_check = time.time()

    def get_network_interfaces(self):
        interfaces = []
        try:
            # Get IPs: ip -o -4 addr show
            output = subprocess.check_output(['ip', '-o', '-4', 'addr', 'show'], text=True)
            for line in output.splitlines():
                parts = line.split()
                if len(parts) >= 4:
                    iface = parts[1]
                    if iface == 'lo': continue
                    ip = parts[3].split('/')[0]
                    mac = self.get_mac_address(iface)
                    interfaces.append({'name': iface, 'ip': ip, 'mac': mac})
        except:
            pass
        return interfaces

    def get_mac_address(self, interface):
        try:
            path = f"/sys/class/net/{interface}/address"
            if os.path.exists(path):
                with open(path, 'r') as f:
                    return f.read().strip()
        except:
            pass
        return "N/A"

    def _get_disk_usage(self, path):
        try:
            st = os.statvfs(path)
            total = st.f_blocks * st.f_frsize
            used = (st.f_blocks - st.f_bfree) * st.f_frsize
            return used, total, (used/total)*100
        except:
            return 0, 0, 0

    def _get_dir_size(self, path):
        try:
            cmd = ['du', '-sk', path]
            output = subprocess.check_output(cmd, stderr=subprocess.DEVNULL, text=True).split()[0]
            return int(output) * 1024 
        except:
            return 0

    def reboot_system(self):
        def _reboot():
            time.sleep(1)
            subprocess.call(["sudo", "reboot"])
        
        t = threading.Thread(target=_reboot)
        t.start()
        return "Rebooting system..."

    def prompt_login(self, stdscr):
        self.running = False
        stdscr.clear()
        stdscr.refresh()
        curses.endwin()
        os.execl("/bin/login", "login")

    def open_raspi_config(self, stdscr):
        curses.def_prog_mode()
        curses.endwin()
        try:
            subprocess.call(["sudo", "raspi-config"])
        except Exception as e:
            pass
        curses.reset_prog_mode()
        stdscr.refresh()

    def _tail_log(self):
        # Create a mapping from filename to nice name
        file_map = {f[0]: f[1] for f in LOG_FILES}
        files_to_tail = [f[0] for f in LOG_FILES]
        
        # Determine initial context
        current_source = "Backend"

        try:
            cmd = ['tail', '-F', '-n', '20'] + files_to_tail
            process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1, encoding='utf-8', errors='replace')
            
            while self.running:
                line = process.stdout.readline()
                if not line:
                    break
                
                line = line.strip()
                if not line: continue

                # Check for header: ==> file <==
                header_match = re.match(r'^==> (.+) <==$', line)
                if header_match:
                    fname = header_match.group(1)
                    current_source = file_map.get(fname, "Backend")
                    continue
                
                with self.log_lock:
                    if current_source in self.log_buffers:
                        self.log_buffers[current_source].append(line)
                    else:
                        self.log_buffers["Backend"].append(f"[{current_source}] {line}")
                    
        except Exception as e:
            with self.log_lock:
                self.log_buffers["Backend"].append(f"Error reading logs: {str(e)}")

    def stop(self):
        self.running = False


def format_bytes(size):
    power = 2**10
    n = 0
    power_labels = {0 : '', 1: 'K', 2: 'M', 3: 'G', 4: 'T'}
    while size > power:
        size /= power
        n += 1
    return f"{size:.1f}{power_labels.get(n, '')}B"

def draw_centered(stdscr, y, text, attr=0):
    h, w = stdscr.getmaxyx()
    x = max(0, (w - len(text)) // 2)
    try:
        stdscr.addstr(y, x, text, attr)
    except:
        pass

def draw_box(stdscr, y, x, h, w, title, logs, color):
    # Check bounds
    max_y, max_x = stdscr.getmaxyx()
    if y >= max_y or x >= max_x: return
    h = min(h, max_y - y)
    w = min(w, max_x - x)
    
    # Draw Header
    header = f" {title} "
    try:
        stdscr.addstr(y, x, header[:w], color | curses.A_BOLD | curses.A_REVERSE)
        # Fill rest of header line
        if len(header) < w:
            stdscr.addstr(y, x + len(header), " " * (w - len(header)), color | curses.A_REVERSE)
            
        # Draw logs
        content_h = h - 1
        visible_logs = list(logs)[-content_h:]
        for i, line in enumerate(visible_logs):
            if y + 1 + i < max_y:
                stdscr.addstr(y + 1 + i, x, line[:w])
                
    except:
        pass

def main(stdscr):
    # Setup curses
    curses.start_color()
    curses.use_default_colors()
    curses.init_pair(1, curses.COLOR_GREEN, -1)   # Status OK
    curses.init_pair(2, curses.COLOR_RED, -1)     # Status Error/Inactive
    curses.init_pair(3, curses.COLOR_CYAN, -1)    # Header
    curses.init_pair(4, curses.COLOR_YELLOW, -1)  # Warnings/Info
    curses.init_pair(5, curses.COLOR_WHITE, curses.COLOR_BLUE) # Focused/Box Header
    
    stdscr.nodelay(True) # Non-blocking input
    stdscr.timeout(1000) # Refresh every 1s if no input
    curses.curs_set(0)   # Hide cursor

    monitor = SystemMonitor()
    
    # Store last restart times to show feedback
    last_restart_msg = ""
    last_restart_time = 0

    # View State: 0=All, 1=Backend, 2=Caddy
    view_mode = 0 
    VIEW_NAMES = {0: "Overview", 1: "Backend", 2: "Caddy"}

    try:
        while True:
            stdscr.erase()
            h, w = stdscr.getmaxyx()
            
            # --- Header ---
            hostname = os.uname()[1]
            header = f"ESSENSYS PI MONITOR - {VIEW_NAMES[view_mode]} View"
            draw_centered(stdscr, 0, header, curses.color_pair(3) | curses.A_BOLD)
            stdscr.hline(1, 0, curses.ACS_HLINE, w)
            
            # --- Stats ---
            cpu_pct = monitor.get_cpu_usage()
            mem_pct, mem_used, mem_total = monitor.get_mem_usage()
            clients = monitor.get_client_count()
            
            # Disk Usage (Cached)
            monitor.update_disk_stats()
            root_used, root_total, root_pct = monitor.cached_disk_usage
            logs_size = monitor.cached_logs_size
            
            stats_str = f"CPU: {cpu_pct:.1f}% | MEM: {mem_pct:.1f}% ({int(mem_used)}/{int(mem_total)}MB) | CLIENTS: {clients}"
            stats_str2 = f"DISK /: {root_pct:.1f}% ({format_bytes(root_used)}/{format_bytes(root_total)}) | /var/logs: {format_bytes(logs_size)}"
            
            draw_centered(stdscr, 2, stats_str)
            draw_centered(stdscr, 3, stats_str2)
            
            # --- Network Interfaces ---
            interfaces = monitor.get_network_interfaces()
            line_idx = 4
            for iface in interfaces:
                net_str = f"{iface['name']}: {iface['ip']} [{iface['mac']}]"
                draw_centered(stdscr, line_idx, net_str)
                line_idx += 1
            
            stdscr.hline(line_idx, 0, curses.ACS_HLINE, w)
            line_idx += 1

            # --- Services ---
            monitor.update_services(SERVICES)
            refresh_sec = monitor.get_service_refresh_remaining()
            
            # Service Header with Timer
            stdscr.hline(line_idx, 0, curses.ACS_HLINE, w)
            stdscr.addstr(line_idx, 2, f" SERVICES (Next refresh: {refresh_sec}s) ", curses.color_pair(3))
            line_idx += 1
            
            # Calculate layout (Box services)
            col_width = w // len(SERVICES)
            for i, service in enumerate(SERVICES):
                status = monitor.get_service_status(service['service'])
                color = curses.color_pair(1) if status else curses.color_pair(2)
                status_txt = "ACTIVE" if status else "INACTIVE"
                
                # Draw Box
                bx = i * col_width
                # content
                try:
                    stdscr.addstr(line_idx, bx + 2, f"{service['name']}", curses.A_BOLD)
                    stdscr.addstr(line_idx + 1, bx + 2, f"Status: {status_txt}", color)
                    stdscr.addstr(line_idx + 2, bx + 2, f"Restart: '{service['key']}'")
                except:
                    pass

            line_idx += 3
            stdscr.hline(line_idx, 0, curses.ACS_HLINE, w)
            # stdscr.addstr(line_idx, 2, " LOGS ", curses.color_pair(3))

            # --- Logs Section ---
            log_start_y = line_idx + 1
            log_area_h = h - log_start_y - 2 # Reserve bottom for status bar
            
            if log_area_h > 0:
                with monitor.log_lock:
                    if view_mode == 0:
                        if w > 100:
                            # 2 Columns
                            col_w = w // 2
                            draw_box(stdscr, log_start_y, 0, log_area_h, col_w-1, "Backend", monitor.log_buffers["Backend"], curses.color_pair(5))
                            draw_box(stdscr, log_start_y, col_w, log_area_h, col_w-1, "Caddy", monitor.log_buffers["Caddy"], curses.color_pair(5))
                        else:
                            # 2 Stacked Rows
                            row_h = log_area_h // 2
                            draw_box(stdscr, log_start_y, 0, row_h, w, "Backend", monitor.log_buffers["Backend"], curses.color_pair(5))
                            draw_box(stdscr, log_start_y + row_h, 0, log_area_h - row_h, w, "Caddy", monitor.log_buffers["Caddy"], curses.color_pair(5))
                    
                    elif view_mode == 1:
                        draw_box(stdscr, log_start_y, 0, log_area_h, w, "Backend (Maximized)", monitor.log_buffers["Backend"], curses.color_pair(5))
                    elif view_mode == 2:
                        draw_box(stdscr, log_start_y, 0, log_area_h, w, "Caddy (Maximized)", monitor.log_buffers["Caddy"], curses.color_pair(5))

            # --- Status Bar ---
            if time.time() - last_restart_time < 3:
                stdscr.addstr(h-1, 0, last_restart_msg, curses.color_pair(4) | curses.A_REVERSE)
            else:
                cmds = "1:Bk 2:Cd 0:All | q:Off | r:Reb | b/c/a/p/h:Rst Svc | f:Conf"
                stdscr.addstr(h-1, 0, cmds[:w-1], curses.color_pair(3))

            # --- Input Handling ---
            key = stdscr.getch()
            if key == ord('q'):
                monitor.prompt_login(stdscr)
                break
            elif key == ord('0') or key == 27: # 27 is ESC
                view_mode = 0
            elif key == ord('1'):
                view_mode = 1
            elif key == ord('2'):
                view_mode = 2
            elif key == ord('u'):
                monitor.last_service_check = 0 # Force refresh on next loop
            elif key == ord('f'):
                monitor.open_raspi_config(stdscr)
            elif key == ord('l'):
                monitor.prompt_login(stdscr)
                break
            elif key == ord('r'):
                last_restart_msg = monitor.reboot_system()
                last_restart_time = time.time()
            elif key == ord('b'):
                monitor.restart_service("essensys-backend")
                last_restart_msg = "Restarting Backend..."
                last_restart_time = time.time()
            elif key == ord('c'):
                monitor.restart_service("caddy")
                last_restart_msg = "Restarting Caddy..."
                last_restart_time = time.time()
            elif key == ord('a'):
                monitor.restart_service("AdGuardHome")
                last_restart_msg = "Restarting AdGuard..."
                last_restart_time = time.time()
            elif key == ord('p'):
                monitor.restart_service("essensys-push.timer")
                last_restart_msg = "Restarting Push Timer..."
                last_restart_time = time.time()
            elif key == ord('h'):
                monitor.restart_service("homeassistant")
                last_restart_msg = "Restarting Home Asst..."
                last_restart_time = time.time()

            stdscr.refresh()
            
    except KeyboardInterrupt:
        pass
    finally:
        monitor.stop()

if __name__ == '__main__':
    # Ensure terminal size is sufficient
    # Set ESC delay to 0 to avoid lag
    os.environ.setdefault('ESCDELAY', '25')
    curses.wrapper(main)
