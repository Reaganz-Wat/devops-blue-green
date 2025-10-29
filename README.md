# Blue/Green Deployment with Nginx Auto-Failover

This project implements a Blue/Green deployment strategy for a Node.js application with automatic failover using Nginx.

## Prerequisites

- Docker
- Docker Compose

## Quick Start

1. **Clone the repository**
```bash
   git clone https://github.com/Reaganz-Wat/devops-blue-green.git
   cd devops-blue-green
```

2. **Configure environment variables**
```bash
   cp .env.example .env
   # Edit .env if needed
```

3. **Generate Nginx configuration**
```bash
   ./setup.sh
```

4. **Start the services**
```bash
   docker-compose up -d
```

5. **Verify deployment**
```bash
   curl http://localhost:8080/version
```

## Testing Failover

1. **Check current active pool (should be Blue)**
```bash
   curl -i http://localhost:8080/version
```

2. **Trigger chaos on Blue**
```bash
   curl -X POST http://localhost:8081/chaos/start?mode=error
```

3. **Verify automatic failover to Green**
```bash
   curl -i http://localhost:8080/version
   # Should show X-App-Pool: green
```

4. **Stop chaos**
```bash
   curl -X POST http://localhost:8081/chaos/stop
```

## Architecture

- **Nginx (port 8080)**: Load balancer with automatic failover
- **Blue App (port 8081)**: Primary application instance
- **Green App (port 8082)**: Backup application instance

## Configuration

Edit `.env` file to customize:
- `ACTIVE_POOL`: Set active pool (blue/green)
- `RELEASE_ID_BLUE`: Blue release identifier
- `RELEASE_ID_GREEN`: Green release identifier

## Health Checks

Both applications expose:
- `GET /healthz`: Health check endpoint
- `GET /version`: Version information with headers
- `POST /chaos/start`: Simulate failure
- `POST /chaos/stop`: Stop simulated failure

## Stopping Services
```bash
docker-compose down
```