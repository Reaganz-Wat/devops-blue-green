# Blue/Green Deployment Runbook

## Alert Types & Response Actions

### 🔴 Failover Detected

**Alert Message:**
```
Failover Detected
Pool switched from blue → green
```

**What it means:**
- The primary pool (Blue) has failed or become unhealthy
- Nginx automatically switched traffic to the backup pool (Green)
- Users should not experience any downtime

**Operator Actions:**

1. **Check the failed pool's health:**
```bash
   docker logs app_blue
   docker inspect app_blue
```

2. **Verify the backup pool is serving traffic:**
```bash
   curl -i http://localhost:8080/version
   # Should show X-App-Pool: green
```

3. **Diagnose the root cause:**
   - Check application logs for errors
   - Review resource usage (CPU, memory)
   - Check for chaos mode: `curl http://localhost:8081/chaos/status`

4. **Recovery steps:**
```bash
   # Stop chaos if active
   curl -X POST http://localhost:8081/chaos/stop
   
   # Restart the failed container if needed
   docker restart app_blue
   
   # Wait for health checks to pass
   docker ps  # Check health status
```

5. **Verify recovery:**
```bash
   # Traffic should automatically return to Blue
   curl -i http://localhost:8080/version
```

---

### 🔴 High Error Rate Detected

**Alert Message:**
```
High Error Rate Detected
Error Rate: 5.25% (threshold: 2%)
Errors: 21 / 400 requests
```

**What it means:**
- The upstream application is returning excessive 5xx errors
- More than 2% of recent requests have failed
- This may indicate application issues, resource exhaustion, or configuration problems

**Operator Actions:**

1. **Identify which pool is affected:**
```bash
   docker logs nginx_proxy | grep "upstream_status=5"
```

2. **Check application logs:**
```bash
   docker logs app_blue --tail 100
   docker logs app_green --tail 100
```

3. **Check resource usage:**
```bash
   docker stats
```

4. **Consider manual pool toggle:**
```bash
   # If Blue is failing, switch to Green
   # Edit .env:
   ACTIVE_POOL=green
   BLUE_BACKUP=backup
   GREEN_BACKUP=
   
   # Regenerate nginx config and reload
   docker exec nginx_proxy nginx -s reload
```

5. **If both pools are affected:**
   - Check database connectivity
   - Verify external service dependencies
   - Review recent deployments or configuration changes
   - Scale resources if needed

6. **Monitor recovery:**
   - Watch for "Service Recovery" alert
   - Check error rate drops below threshold

---

### 🟢 Service Recovery

**Alert Message:**
```
Service Recovery
Error rate has improved: 0.5%
System is stabilizing
```

**What it means:**
- The error rate has dropped below half the threshold
- The system is recovering from a previous incident
- Normal operations are resuming

**Operator Actions:**

1. **Verify stability:**
```bash
   # Run several test requests
   for i in {1..20}; do
     curl -s http://localhost:8080/version | grep "X-App-Pool"
   done
```

2. **Review incident timeline:**
   - Document what caused the issue
   - Note what resolved it
   - Update runbook if needed

3. **Post-mortem (if major incident):**
   - Analyze logs for root cause
   - Identify preventive measures
   - Update monitoring thresholds if needed

---

## Maintenance Mode

### Suppress Alerts During Planned Changes

When performing planned maintenance (deployments, testing, infrastructure changes):

1. **Enable maintenance mode:**
```bash
   # Edit .env
   MAINTENANCE_MODE=true
   
   # Restart watcher
   docker-compose restart alert_watcher
```

2. **Perform your maintenance:**
   - Deploy new versions
   - Test failover scenarios
   - Update configurations

3. **Disable maintenance mode:**
```bash
   # Edit .env
   MAINTENANCE_MODE=false
   
   # Restart watcher
   docker-compose restart alert_watcher
```

---

## Manual Testing & Verification

### Test Failover Alert
```bash
# 1. Ensure Blue is active
curl http://localhost:8080/version

# 2. Trigger chaos on Blue
curl -X POST "http://localhost:8081/chaos/start?mode=error"

# 3. Generate traffic to trigger failover
for i in {1..50}; do
  curl -s http://localhost:8080/version
  sleep 0.1
done

# 4. Check Slack for failover alert
# 5. Stop chaos
curl -X POST http://localhost:8081/chaos/stop
```

### Test Error Rate Alert
```bash
# 1. Trigger chaos with high error rate
curl -X POST "http://localhost:8081/chaos/start?mode=error"

# 2. Generate traffic to build error window
for i in {1..300}; do
  curl -s http://localhost:8080/version
  sleep 0.05
done

# 3. Check Slack for error rate alert
# 4. Stop chaos
curl -X POST http://localhost:8081/chaos/stop
```

---

## Troubleshooting

### Alerts Not Appearing in Slack

1. **Verify webhook URL:**
```bash
   echo $SLACK_WEBHOOK_URL
   # Should show: https://hooks.slack.com/services/...
```

2. **Test webhook manually:**
```bash
   curl -X POST $SLACK_WEBHOOK_URL \
     -H 'Content-Type: application/json' \
     -d '{"text":"Test alert from runbook"}'
```

3. **Check watcher logs:**
```bash
   docker logs alert_watcher
```

### Watcher Not Detecting Events

1. **Verify log file access:**
```bash
   docker exec alert_watcher ls -la /var/log/nginx/
```

2. **Check Nginx log format:**
```bash
   docker logs nginx_proxy | tail -5
   # Should show pool=blue/green in logs
```

3. **Restart watcher:**
```bash
   docker-compose restart alert_watcher
```

---

## Configuration Reference

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SLACK_WEBHOOK_URL` | (required) | Slack incoming webhook URL |
| `ERROR_RATE_THRESHOLD` | 2 | Error rate % threshold for alerts |
| `WINDOW_SIZE` | 200 | Number of requests in sliding window |
| `ALERT_COOLDOWN_SEC` | 300 | Minimum seconds between same alert type |
| `MAINTENANCE_MODE` | false | Set to `true` to suppress alerts |

### Adjusting Thresholds

**More sensitive (alerts trigger easier):**
```bash
ERROR_RATE_THRESHOLD=1
WINDOW_SIZE=100
ALERT_COOLDOWN_SEC=180
```

**Less sensitive (fewer alerts):**
```bash
ERROR_RATE_THRESHOLD=5
WINDOW_SIZE=500
ALERT_COOLDOWN_SEC=600
```

---

## Emergency Procedures

### Complete Service Failure

If both pools fail:

1. **Check all containers:**
```bash
   docker-compose ps
```

2. **Restart all services:**
```bash
   docker-compose restart
```

3. **Full reset if needed:**
```bash
   docker-compose down
   docker-compose up -d
```

### Database/External Dependency Failure

1. **Verify connectivity:**
```bash
   docker exec app_blue ping database-host
```

2. **Check network:**
```bash
   docker network inspect devops-blue-green_app_network
```

3. **Review service dependencies in docker-compose.yml**

---

## Contact & Escalation

- **DevOps Team:** devops@company.com
- **On-Call Engineer:** Check PagerDuty
- **Slack Channel:** #alerts-production

---

## Changelog

| Date | Change | Author |
|------|--------|--------|
| 2025-11-01 | Initial runbook | DevOps Team |