#!/usr/bin/env python3
import curses
import time
import subprocess
import threading
import os
import sys
import json
from collections import deque
import re

# Docker Compose file location
COMPOSE_FILE = "/opt/data/docker-compose.yml"

# Container services to monitor
SERVICES = [
    {"name": "Backend",  "container": "essensys-backend",        "key": "b"},
    {"name": "MCP",      "container": "essensys-mcp",            "key": "m"},
    {"name": "Nginx",    "container": "essensys-nginx",          "key": "n"},
    {"name": "Traefik",  "container": "essensys-traefik",        "key": "t"},
    {"name": "Redis",    "container": "essensys-redis",          "key": "d"},
    {"name": "MQTT",     "container": "essensys-mosquitto",      "key": "q"},
    {"name": "CtrlPlan", "container": "essensys-control-plane",  "key": "c"},
    {"name": "AdGuard",  "container": "adguardhome",             "key": "a"},
]

# Log sources (docker logs)
LOG_SOURCES = [
    ("essensys-backend", "Backend"),
    ("essensys-nginx", "Nginx"),
]

REFRESH_RATE = 1.0

class SystemMonitor:
    def __init__(self):
        self.cpu_prev = self._read_cpu_stats()
        self.log_buffers = {src[1]: deque(maxlen=200) for src in LOG_SOURCES}
        self.log_lock = threading.Lock()
        self.running = True

        # Start log reader threads
        for container, label in LOG_SOURCES:
            t = threading.Thread(target=self._tail_docker_log, args=(container, label), daemon=True)
            t.start()

        # Cache for disk stats
        self.last_disk_check = 0
        self.cached_disk_usage = (0, 0, 0)
        self.cached_logs_size = 0

        # Cache for services
        self.last_service_check = 0
        self.service_cache = {}
        self.service_refresh_interval = 15

    def _read_cpu_stats(self):
        try:
            with open('/proc/stat', 'r') as f:
                line = f.readline()
                if line.startswith('cpu '):
                    parts = line.split()
                    return [int(x) for x in parts[1:6]]
        except:
            return None
        return None

    def get_cpu_usage(self):
        curr = self._read_cpu_stats()
        if not curr or not self.cpu_prev:
            self.cpu_prev = curr
            return 0.0
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
        if diff_total == 0:
            return 0.0
        return 100.0 * (diff_total - diff_idle) / diff_total

    def get_mem_usage(self):
        try:
            mem = {}
            with open('/proc/meminfo', 'r') as f:
                for line in f:
                    parts = line.split(':')
                    if len(parts) == 2:
                        key = parts[0].strip()
                        val = int(parts[1].split()[0])
                        mem[key] = val
            total = mem.get('MemTotal', 1)
            avail = mem.get('MemAvailable', mem.get('MemFree', 0))
            used = total - avail
            return (used / total) * 100.0, used / 1024, total / 1024
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
        if self.last_service_check == 0 or (time.time() - self.last_service_check > self.service_refresh_interval):
            try:
                output = subprocess.check_output(
                    ["docker", "ps", "--format", "{{.Names}}\t{{.Status}}"],
                    text=True, timeout=5
                )
                running = {}
                for line in output.strip().splitlines():
                    parts = line.split('\t', 1)
                    if len(parts) == 2:
                        running[parts[0]] = parts[1]

                for s in services_list:
                    name = s['container']
                    if name in running:
                        status = running[name]
                        if 'Restarting' in status:
                            self.service_cache[name] = 'restarting'
                        else:
                            self.service_cache[name] = 'running'
                    else:
                        self.service_cache[name] = 'stopped'
            except:
                pass
            self.last_service_check = time.time()

    def get_service_refresh_remaining(self):
        if self.last_service_check == 0:
            return 0
        elapsed = time.time() - self.last_service_check
        remaining = self.service_refresh_interval - elapsed
        return max(0, int(remaining))

    def get_service_status(self, container_name):
        return self.service_cache.get(container_name, 'unknown')

    def restart_service(self, container_name):
        def _restart():
            subprocess.call(["docker", "restart", container_name], timeout=30)
            time.sleep(3)
            try:
                output = subprocess.check_output(
                    ["docker", "inspect", "-f", "{{.State.Status}}", container_name],
                    text=True, timeout=5
                ).strip()
                self.service_cache[container_name] = output
            except:
                pass
        t = threading.Thread(target=_restart)
        t.start()

    def update_disk_stats(self):
        if time.time() - self.last_disk_check > 120:
            self.cached_disk_usage = self._get_disk_usage('/')
            self.cached_logs_size = self._get_dir_size('/var/log')
            self.last_disk_check = time.time()

    def get_network_interfaces(self):
        interfaces = []
        try:
            output = subprocess.check_output(['ip', '-o', '-4', 'addr', 'show'], text=True)
            for line in output.splitlines():
                parts = line.split()
                if len(parts) >= 4:
                    iface = parts[1]
                    if iface == 'lo':
                        continue
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
            return used, total, (used / total) * 100
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

    def compose_restart_all(self):
        def _restart():
            subprocess.call(
                ["docker", "compose", "-f", COMPOSE_FILE, "up", "-d", "--remove-orphans"],
                timeout=120
            )
            self.last_service_check = 0
        t = threading.Thread(target=_restart)
        t.start()
        return "Restarting all services..."

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
        except:
            pass
        curses.reset_prog_mode()
        stdscr.refresh()

    def _tail_docker_log(self, container, label):
        try:
            cmd = ['docker', 'logs', '-f', '--tail', '30', '--timestamps', container]
            process = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, bufsize=1, encoding='utf-8', errors='replace'
            )
            while self.running:
                line = process.stdout.readline()
                if not line:
                    time.sleep(2)
                    process = subprocess.Popen(
                        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                        text=True, bufsize=1, encoding='utf-8', errors='replace'
                    )
                    continue
                line = line.strip()
                if not line:
                    continue
                # Strip Docker timestamp prefix if present
                if len(line) > 31 and line[4] == '-' and line[10] == 'T':
                    line = line[31:].strip()
                with self.log_lock:
                    if label in self.log_buffers:
                        self.log_buffers[label].append(line)
        except Exception as e:
            with self.log_lock:
                if label in self.log_buffers:
                    self.log_buffers[label].append(f"Error reading {container} logs: {str(e)}")

    def stop(self):
        self.running = False


def format_bytes(size):
    power = 2 ** 10
    n = 0
    power_labels = {0: '', 1: 'K', 2: 'M', 3: 'G', 4: 'T'}
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
    max_y, max_x = stdscr.getmaxyx()
    if y >= max_y or x >= max_x:
        return
    h = min(h, max_y - y)
    w = min(w, max_x - x)
    try:
        header = f" {title} "
        stdscr.addstr(y, x, header[:w], color | curses.A_BOLD | curses.A_REVERSE)
        if len(header) < w:
            stdscr.addstr(y, x + len(header), " " * (w - len(header)), color | curses.A_REVERSE)
        content_h = h - 1
        visible_logs = list(logs)[-content_h:]
        for i, line in enumerate(visible_logs):
            if y + 1 + i < max_y:
                stdscr.addstr(y + 1 + i, x, line[:w])
    except:
        pass


def main(stdscr):
    curses.start_color()
    curses.use_default_colors()
    curses.init_pair(1, curses.COLOR_GREEN, -1)
    curses.init_pair(2, curses.COLOR_RED, -1)
    curses.init_pair(3, curses.COLOR_CYAN, -1)
    curses.init_pair(4, curses.COLOR_YELLOW, -1)
    curses.init_pair(5, curses.COLOR_WHITE, curses.COLOR_BLUE)

    stdscr.nodelay(True)
    stdscr.timeout(1000)
    curses.curs_set(0)

    monitor = SystemMonitor()

    last_restart_msg = ""
    last_restart_time = 0

    log_source_names = [src[1] for src in LOG_SOURCES]
    view_mode = 0
    VIEW_NAMES = {0: "Overview"}
    for i, name in enumerate(log_source_names):
        VIEW_NAMES[i + 1] = name

    try:
        while True:
            stdscr.erase()
            h, w = stdscr.getmaxyx()

            # Header
            hostname = os.uname()[1]
            view_label = VIEW_NAMES.get(view_mode, "Overview")
            header = f"ESSENSYS DOCKER MONITOR - {view_label} View"
            draw_centered(stdscr, 0, header, curses.color_pair(3) | curses.A_BOLD)
            stdscr.hline(1, 0, curses.ACS_HLINE, w)

            # System stats
            cpu_pct = monitor.get_cpu_usage()
            mem_pct, mem_used, mem_total = monitor.get_mem_usage()
            clients = monitor.get_client_count()

            monitor.update_disk_stats()
            root_used, root_total, root_pct = monitor.cached_disk_usage
            logs_size = monitor.cached_logs_size

            stats_str = f"CPU: {cpu_pct:.1f}% | MEM: {mem_pct:.1f}% ({int(mem_used)}/{int(mem_total)}MB) | CLIENTS: {clients}"
            stats_str2 = f"DISK /: {root_pct:.1f}% ({format_bytes(root_used)}/{format_bytes(root_total)}) | /var/log: {format_bytes(logs_size)}"

            draw_centered(stdscr, 2, stats_str)
            draw_centered(stdscr, 3, stats_str2)

            # Network
            interfaces = monitor.get_network_interfaces()
            line_idx = 4
            for iface in interfaces:
                net_str = f"{iface['name']}: {iface['ip']} [{iface['mac']}]"
                draw_centered(stdscr, line_idx, net_str)
                line_idx += 1

            stdscr.hline(line_idx, 0, curses.ACS_HLINE, w)
            line_idx += 1

            # Services (Docker containers)
            monitor.update_services(SERVICES)
            refresh_sec = monitor.get_service_refresh_remaining()

            stdscr.hline(line_idx, 0, curses.ACS_HLINE, w)
            stdscr.addstr(line_idx, 2, f" CONTAINERS (Refresh: {refresh_sec}s) ", curses.color_pair(3))
            line_idx += 1

            # Display services in rows of max_per_row
            max_per_row = min(len(SERVICES), w // 14)
            if max_per_row < 1:
                max_per_row = 1
            col_width = w // max_per_row

            for i, service in enumerate(SERVICES):
                row = i // max_per_row
                col = i % max_per_row
                bx = col * col_width
                by = line_idx + row * 3

                status = monitor.get_service_status(service['container'])
                if status == 'running':
                    color = curses.color_pair(1)
                    status_txt = "RUNNING"
                elif status == 'restarting':
                    color = curses.color_pair(4)
                    status_txt = "RESTART"
                else:
                    color = curses.color_pair(2)
                    status_txt = "STOPPED"

                try:
                    stdscr.addstr(by, bx + 1, f"{service['name']}", curses.A_BOLD)
                    stdscr.addstr(by + 1, bx + 1, f"{status_txt}", color)
                    stdscr.addstr(by + 2, bx + 1, f"'{service['key']}'")
                except:
                    pass

            total_rows = (len(SERVICES) + max_per_row - 1) // max_per_row
            line_idx += total_rows * 3
            stdscr.hline(line_idx, 0, curses.ACS_HLINE, w)

            # Logs
            log_start_y = line_idx + 1
            log_area_h = h - log_start_y - 2

            if log_area_h > 0:
                with monitor.log_lock:
                    if view_mode == 0:
                        num_sources = len(log_source_names)
                        if num_sources > 0:
                            if w > 100 and num_sources > 1:
                                col_w = w // num_sources
                                for i, name in enumerate(log_source_names):
                                    draw_box(stdscr, log_start_y, i * col_w, log_area_h, col_w - 1, name, monitor.log_buffers.get(name, []), curses.color_pair(5))
                            else:
                                row_h = log_area_h // max(num_sources, 1)
                                for i, name in enumerate(log_source_names):
                                    draw_box(stdscr, log_start_y + i * row_h, 0, row_h, w, name, monitor.log_buffers.get(name, []), curses.color_pair(5))
                    else:
                        idx = view_mode - 1
                        if 0 <= idx < len(log_source_names):
                            name = log_source_names[idx]
                            draw_box(stdscr, log_start_y, 0, log_area_h, w, f"{name} (Maximized)", monitor.log_buffers.get(name, []), curses.color_pair(5))

            # Status bar
            if time.time() - last_restart_time < 3:
                stdscr.addstr(h - 1, 0, last_restart_msg, curses.color_pair(4) | curses.A_REVERSE)
            else:
                keys = " ".join(f"{s['key']}:{s['name']}" for s in SERVICES[:6])
                cmds = f"0:All 1:Bk 2:Nx | {keys} | R:All q:Off r:Reb f:Conf"
                stdscr.addstr(h - 1, 0, cmds[:w - 1], curses.color_pair(3))

            # Input handling
            key = stdscr.getch()
            if key == ord('q'):
                monitor.prompt_login(stdscr)
                break
            elif key == ord('0') or key == 27:
                view_mode = 0
            elif key == ord('u'):
                monitor.last_service_check = 0
            elif key == ord('f'):
                monitor.open_raspi_config(stdscr)
            elif key == ord('l'):
                monitor.prompt_login(stdscr)
                break
            elif key == ord('r'):
                last_restart_msg = monitor.reboot_system()
                last_restart_time = time.time()
            elif key == ord('R'):
                last_restart_msg = monitor.compose_restart_all()
                last_restart_time = time.time()
            else:
                # View mode shortcuts
                for i, name in enumerate(log_source_names):
                    if key == ord(str(i + 1)):
                        view_mode = i + 1
                        break
                # Service restart shortcuts
                for s in SERVICES:
                    if key == ord(s['key']):
                        monitor.restart_service(s['container'])
                        last_restart_msg = f"Restarting {s['name']}..."
                        last_restart_time = time.time()
                        break

            stdscr.refresh()

    except KeyboardInterrupt:
        pass
    finally:
        monitor.stop()


if __name__ == '__main__':
    os.environ.setdefault('ESCDELAY', '25')
    curses.wrapper(main)
