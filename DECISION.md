# Implementation Decisions

## Nginx Configuration Choices

### 1. Upstream Configuration
- Used `backup` directive on Green to make it standby
- Set `max_fails=2` and `fail_timeout=5s` for quick failure detection
- This ensures Blue handles all traffic unless it fails

### 2. Timeout Strategy
- `proxy_connect_timeout: 2s` - Quick connection failure detection
- `proxy_read_timeout: 3s` - Fast detection of hung requests
- Total worst-case scenario: ~5s before complete failover

### 3. Retry Policy
- `proxy_next_upstream error timeout http_500 http_502 http_503 http_504`
- Ensures automatic retry to Green on any Blue failure
- `proxy_next_upstream_tries 2` - One retry to backup
- `proxy_next_upstream_timeout 10s` - Total timeout budget

### 4. Header Forwarding
- No `proxy_hide_header` directives
- `proxy_pass_request_headers on` ensures all upstream headers reach client
- X-App-Pool and X-Release-Id pass through unchanged

## Docker Compose Choices

### 1. Network Isolation
- Custom bridge network for service discovery
- Services communicate by container name

### 2. Port Exposure
- 8080: Public Nginx endpoint
- 8081, 8082: Direct app access for chaos testing

### 3. Health Checks
- Built-in Docker health checks on /healthz
- 5s intervals, 3s timeout, 3 retries

## Trade-offs

### Chosen Approach
- **Simple, battle-tested**: Nginx upstream with backup
- **Fast failover**: Tight timeouts detect failures in <5s
- **Zero client errors**: Retry happens within same request

### Alternatives Considered
- **Active-active**: Would require session stickiness
- **External health checker**: Adds complexity
- **Consul/service mesh**: Overkill for this use case