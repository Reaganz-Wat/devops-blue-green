#!/bin/bash

echo "=== Test 1: Failover Alert ==="
echo "Triggering chaos on Blue..."
curl -X POST "http://localhost:8081/chaos/start?mode=error"

echo ""
echo "Generating traffic to force failover..."
for i in {1..60}; do
  curl -s http://localhost:8080/version > /dev/null
  sleep 0.1
done

echo ""
echo "✅ Failover should have triggered!"
echo "📸 Check Slack and take screenshot 1"
echo ""
read -p "Press Enter after taking screenshot 1..."

echo ""
echo "=== Test 2: Error Rate Alert ==="
echo "Generating more traffic for error rate..."
for i in {1..300}; do
  curl -s http://localhost:8080/version > /dev/null
  sleep 0.05
done

echo ""
echo "✅ Error rate alert should have triggered!"
echo "📸 Check Slack and take screenshot 2"
echo ""
read -p "Press Enter after taking screenshot 2..."

echo ""
echo "=== Test 3: Nginx Logs ==="
docker logs nginx_proxy 2>&1 | grep "pool=" | tail -10

echo ""
echo "📸 Take screenshot 3 of the logs above"
echo ""
read -p "Press Enter to stop chaos..."

echo ""
echo "Stopping chaos..."
curl -X POST "http://localhost:8081/chaos/stop"

echo ""
echo "✅ All tests complete!"
