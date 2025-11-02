#!/usr/bin/env python3
"""
Nginx Log Watcher for Blue/Green Deployment
Monitors Nginx access logs and sends Slack alerts for:
- Pool failover events (Blue <-> Green)
- High upstream error rates
"""

import os
import sys
import time
import re
import json
from collections import deque
from datetime import datetime
import requests


class LogWatcher:
    def __init__(self):
        # Environment variables
        self.slack_webhook = os.getenv('SLACK_WEBHOOK_URL')
        self.error_threshold = float(os.getenv('ERROR_RATE_THRESHOLD', '2'))
        self.window_size = int(os.getenv('WINDOW_SIZE', '200'))
        self.cooldown_sec = int(os.getenv('ALERT_COOLDOWN_SEC', '300'))
        self.maintenance_mode = os.getenv('MAINTENANCE_MODE', 'false').lower() == 'true'
        
        # Log file path (from shared volume)
        self.log_file_path = '/var/log/nginx/access.log'
        
        # State tracking
        self.last_pool = None
        self.request_window = deque(maxlen=self.window_size)
        self.last_failover_alert = None
        self.last_error_alert = None
        self.last_recovery_alert = None
        
        # Validate configuration
        if not self.slack_webhook or 'https://hooks.slack.com/services/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' in self.slack_webhook:
            print("⚠️  WARNING: SLACK_WEBHOOK_URL not configured. Alerts will be printed to console only.")
            self.slack_webhook = None
        
        print(f"🚀 Log Watcher Started")
        print(f"   Error Threshold: {self.error_threshold}%")
        print(f"   Window Size: {self.window_size} requests")
        print(f"   Cooldown: {self.cooldown_sec}s")
        print(f"   Maintenance Mode: {self.maintenance_mode}")
        print(f"   Watching: {self.log_file_path}")
        print("-" * 60)

    def parse_log_line(self, line):
        """Parse Nginx log line to extract pool, status, and upstream info."""
        try:
            # Skip lines without pool info
            if 'pool=' not in line:
                return None
            
            # Extract pool (e.g., pool=blue or pool=green)
            pool_match = re.search(r'pool=(\w+)', line)
            pool = pool_match.group(1) if pool_match else None
            
            # Extract upstream status (e.g., upstream_status=200 or 500)
            status_match = re.search(r'upstream_status=([\d,\s]+)', line)
            if status_match:
                statuses = status_match.group(1).split(',')
                # Take the first status (the one that failed)
                upstream_status = int(statuses[0].strip())
            else:
                upstream_status = None
            
            # Extract upstream address
            addr_match = re.search(r'upstream_addr=([\d\.:,\s]+)', line)
            upstream_addr = addr_match.group(1).strip() if addr_match else None
            
            # Extract request time
            req_time_match = re.search(r'request_time=([\d\.]+)', line)
            request_time = float(req_time_match.group(1)) if req_time_match else None
            
            return {
                'pool': pool,
                'upstream_status': upstream_status,
                'upstream_addr': upstream_addr,
                'request_time': request_time,
                'timestamp': datetime.now(),
                'raw_line': line
            }
        except Exception as e:
            # Don't print errors for every line, just return None
            return None

    def send_slack_alert(self, message, color="warning", alert_type="info"):
        """Send alert to Slack webhook."""
        if self.maintenance_mode:
            print(f"🔧 MAINTENANCE MODE: Suppressing {alert_type} alert")
            return
        
        payload = {
            "attachments": [{
                "color": color,
                "title": f"🚨 Blue/Green Deployment Alert",
                "text": message,
                "footer": "Nginx Log Watcher",
                "ts": int(time.time())
            }]
        }
        
        # Print to console
        print(f"\n{'='*60}")
        print(f"📢 ALERT [{alert_type.upper()}]: {message}")
        print(f"{'='*60}\n")
        
        # Send to Slack if configured
        if self.slack_webhook:
            try:
                response = requests.post(
                    self.slack_webhook,
                    json=payload,
                    headers={'Content-Type': 'application/json'},
                    timeout=10
                )
                if response.status_code == 200:
                    print(f"✅ Alert sent to Slack successfully")
                else:
                    print(f"⚠️  Slack webhook returned status {response.status_code}")
            except Exception as e:
                print(f"❌ Failed to send Slack alert: {e}")

    def check_failover(self, current_pool):
        """Detect pool failover events."""
        if self.last_pool is None:
            self.last_pool = current_pool
            print(f"📍 Initial pool detected: {current_pool}")
            return
        
        if current_pool != self.last_pool and current_pool is not None:
            # Cooldown check
            now = datetime.now()
            if self.last_failover_alert:
                elapsed = (now - self.last_failover_alert).total_seconds()
                if elapsed < self.cooldown_sec:
                    print(f"⏳ Failover cooldown active ({int(elapsed)}s / {self.cooldown_sec}s)")
                    return
            
            # Failover detected!
            message = (
                f"*Failover Detected*\n"
                f"Pool switched from *{self.last_pool}* → *{current_pool}*\n"
                f"Time: {now.strftime('%Y-%m-%d %H:%M:%S')}\n\n"
                f"*Action Required:*\n"
                f"• Check health of `{self.last_pool}` container\n"
                f"• Review logs: `docker logs app_{self.last_pool}`\n"
                f"• Verify application is recovering"
            )
            
            self.send_slack_alert(message, color="danger", alert_type="failover")
            self.last_failover_alert = now
            self.last_pool = current_pool

    def check_error_rate(self):
        """Calculate and alert on high error rates."""
        if len(self.request_window) < min(50, self.window_size):
            return  # Not enough data yet
        
        # Count 5xx errors
        error_count = sum(1 for req in self.request_window 
                         if req['upstream_status'] and req['upstream_status'] >= 500)
        
        total_count = len(self.request_window)
        error_rate = (error_count / total_count) * 100
        
        if error_rate > self.error_threshold:
            # Cooldown check
            now = datetime.now()
            if self.last_error_alert:
                elapsed = (now - self.last_error_alert).total_seconds()
                if elapsed < self.cooldown_sec:
                    return
            
            # High error rate detected!
            message = (
                f"*High Error Rate Detected*\n"
                f"Error Rate: *{error_rate:.2f}%* (threshold: {self.error_threshold}%)\n"
                f"Errors: {error_count} / {total_count} requests\n"
                f"Window: Last {self.window_size} requests\n"
                f"Time: {now.strftime('%Y-%m-%d %H:%M:%S')}\n\n"
                f"*Action Required:*\n"
                f"• Check upstream application logs\n"
                f"• Consider toggling to backup pool\n"
                f"• Investigate root cause of 5xx errors"
            )
            
            self.send_slack_alert(message, color="danger", alert_type="error_rate")
            self.last_error_alert = now
        
        # Check for recovery
        elif error_rate < (self.error_threshold / 2) and self.last_error_alert:
            now = datetime.now()
            elapsed = (now - self.last_error_alert).total_seconds()
            
            if 60 < elapsed < self.cooldown_sec * 2:
                if not self.last_recovery_alert or \
                   (now - self.last_recovery_alert).total_seconds() > self.cooldown_sec:
                    
                    message = (
                        f"*Service Recovery*\n"
                        f"Error rate has improved: *{error_rate:.2f}%*\n"
                        f"System is stabilizing\n"
                        f"Time: {now.strftime('%Y-%m-%d %H:%M:%S')}"
                    )
                    
                    self.send_slack_alert(message, color="good", alert_type="recovery")
                    self.last_recovery_alert = now

    def tail_log_file(self):
        """Tail the Nginx access log file directly - handles FIFO/named pipes."""
        print(f"⏳ Waiting for log file: {self.log_file_path}")
        
        # Wait for log file to exist
        while not os.path.exists(self.log_file_path):
            print(f"📁 Log file not found, waiting...")
            time.sleep(2)
        
        print(f"✅ Found log file, starting to monitor...")
        print(f"📊 Monitoring started. Waiting for traffic...\n")
        
        # Open the file in read mode - for FIFO/named pipes, we can't seek
        try:
            with open(self.log_file_path, 'r') as file:
                while True:
                    line = file.readline()
                    if not line:
                        time.sleep(0.1)  # Wait for new content
                        continue
                    
                    line = line.strip()
                    if not line:
                        continue
                    
                    # Parse log line
                    parsed = self.parse_log_line(line)
                    if not parsed or not parsed['pool']:
                        continue
                    
                    # Add to window
                    self.request_window.append(parsed)
                    
                    # Check for failover
                    self.check_failover(parsed['pool'])
                    
                    # Check error rate
                    self.check_error_rate()
                    
        except IOError as e:
            print(f"❌ I/O error reading log file: {e}")
            raise
        except Exception as e:
            print(f"❌ Unexpected error reading log file: {e}")
            raise

    def run(self):
        """Main run loop."""
        try:
            self.tail_log_file()
        except KeyboardInterrupt:
            print("\n⚠️  Watcher stopped by user")
            sys.exit(0)
        except Exception as e:
            print(f"❌ Fatal error: {e}")
            import traceback
            traceback.print_exc()
            sys.exit(1)


if __name__ == '__main__':
    watcher = LogWatcher()
    watcher.run()