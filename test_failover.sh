#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Blue/Green Failover Test Suite${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Test 1: Verify initial state (Blue active)
echo -e "${YELLOW}Test 1: Verify Blue is active${NC}"
echo "Testing 5 consecutive requests to http://localhost:8080/version"
echo "Expected: All should return HTTP 200 with X-App-Pool: blue"
echo "---"

failed_requests=0
for i in {1..5}; do 
  response=$(curl -s -i http://localhost:8080/version)
  http_code=$(echo "$response" | grep "HTTP" | head -1 | awk '{print $2}')
  pool=$(echo "$response" | grep "X-App-Pool:" | awk '{print $2}' | tr -d '\r')
  release=$(echo "$response" | grep "X-Release-Id:" | awk '{print $2}' | tr -d '\r')
  
  if [ "$http_code" != "200" ]; then
    failed_requests=$((failed_requests + 1))
  fi
  
  echo "Request $i: HTTP $http_code | Pool: $pool | Release: $release"
done

if [ $failed_requests -eq 0 ]; then
  echo -e "${GREEN}✓ Test 1 PASSED: All requests returned 200${NC}\n"
else
  echo -e "${RED}✗ Test 1 FAILED: $failed_requests requests did not return 200${NC}\n"
fi

# Test 2: Verify direct access to both apps
echo -e "${YELLOW}Test 2: Verify direct access to both apps${NC}"
echo "---"

echo "Blue (port 8081):"
blue_response=$(curl -s -w "\nHTTP_CODE:%{http_code}" http://localhost:8081/version)
blue_code=$(echo "$blue_response" | grep "HTTP_CODE" | cut -d: -f2)
echo "Status: $blue_code"

echo -e "\nGreen (port 8082):"
green_response=$(curl -s -w "\nHTTP_CODE:%{http_code}" http://localhost:8082/version)
green_code=$(echo "$green_response" | grep "HTTP_CODE" | cut -d: -f2)
echo "Status: $green_code"

if [ "$blue_code" == "200" ] && [ "$green_code" == "200" ]; then
  echo -e "${GREEN}✓ Test 2 PASSED: Both apps are accessible${NC}\n"
else
  echo -e "${RED}✗ Test 2 FAILED: One or both apps are not accessible${NC}\n"
fi

# Test 3: Trigger chaos and test failover (ERROR MODE)
echo -e "${YELLOW}Test 3: Failover test with ERROR mode${NC}"
echo "Triggering chaos on Blue (will return 500 errors)..."
curl -s -X POST "http://localhost:8081/chaos/start?mode=error" > /dev/null

echo "Waiting 2 seconds for chaos to take effect..."
sleep 2

echo "Testing 20 requests - ALL should return HTTP 200 and switch to Green"
echo "---"

failed_requests=0
green_count=0
blue_count=0

for i in {1..20}; do 
  response=$(curl -s -i http://localhost:8080/version)
  http_code=$(echo "$response" | grep "HTTP" | head -1 | awk '{print $2}')
  pool=$(echo "$response" | grep "X-App-Pool:" | awk '{print $2}' | tr -d '\r')
  release=$(echo "$response" | grep "X-Release-Id:" | awk '{print $2}' | tr -d '\r')
  
  if [ "$http_code" != "200" ]; then
    failed_requests=$((failed_requests + 1))
    echo -e "${RED}Request $i: HTTP $http_code | Pool: $pool | Release: $release${NC}"
  else
    echo "Request $i: HTTP $http_code | Pool: $pool | Release: $release"
  fi
  
  if [ "$pool" == "green" ]; then
    green_count=$((green_count + 1))
  elif [ "$pool" == "blue" ]; then
    blue_count=$((blue_count + 1))
  fi
  
  sleep 0.3
done

green_percentage=$((green_count * 100 / 20))

echo "---"
echo "Summary: Blue responses: $blue_count | Green responses: $green_count | Green %: $green_percentage%"

if [ $failed_requests -eq 0 ] && [ $green_percentage -ge 95 ]; then
  echo -e "${GREEN}✓ Test 3 PASSED: Zero failed requests and ≥95% traffic on Green${NC}\n"
elif [ $failed_requests -eq 0 ] && [ $green_percentage -lt 95 ]; then
  echo -e "${YELLOW}⚠ Test 3 PARTIAL: Zero failed requests but only $green_percentage% on Green (need ≥95%)${NC}\n"
else
  echo -e "${RED}✗ Test 3 FAILED: $failed_requests requests failed (expected 0)${NC}\n"
fi

# Test 4: Stop chaos and verify Blue recovery
echo -e "${YELLOW}Test 4: Blue recovery after chaos ends${NC}"
echo "Stopping chaos on Blue..."
curl -s -X POST "http://localhost:8081/chaos/stop" > /dev/null

echo "Waiting 10 seconds for Blue to recover..."
sleep 10

echo "Testing 10 requests - should eventually return to Blue"
echo "---"

blue_recovered=0
for i in {1..10}; do 
  response=$(curl -s -i http://localhost:8080/version)
  pool=$(echo "$response" | grep "X-App-Pool:" | awk '{print $2}' | tr -d '\r')
  release=$(echo "$response" | grep "X-Release-Id:" | awk '{print $2}' | tr -d '\r')
  
  echo "Request $i: Pool: $pool | Release: $release"
  
  if [ "$pool" == "blue" ]; then
    blue_recovered=1
  fi
  
  sleep 1
done

if [ $blue_recovered -eq 1 ]; then
  echo -e "${GREEN}✓ Test 4 PASSED: Blue has recovered and is serving traffic${NC}\n"
else
  echo -e "${YELLOW}⚠ Test 4 WARNING: Blue has not yet resumed serving traffic (may need more time)${NC}\n"
fi

# Test 5: Failover test with TIMEOUT mode
echo -e "${YELLOW}Test 5: Failover test with TIMEOUT mode${NC}"
echo "Triggering chaos on Blue (will timeout)..."
curl -s -X POST "http://localhost:8081/chaos/start?mode=timeout" > /dev/null

echo "Waiting 2 seconds for chaos to take effect..."
sleep 2

echo "Testing 15 requests - ALL should return HTTP 200 and switch to Green"
echo "---"

failed_requests=0
green_count=0

for i in {1..15}; do 
  response=$(curl -s -i http://localhost:8080/version 2>&1)
  http_code=$(echo "$response" | grep "HTTP" | head -1 | awk '{print $2}')
  pool=$(echo "$response" | grep "X-App-Pool:" | awk '{print $2}' | tr -d '\r')
  
  if [ "$http_code" != "200" ]; then
    failed_requests=$((failed_requests + 1))
    echo -e "${RED}Request $i: HTTP $http_code | Pool: $pool${NC}"
  else
    echo "Request $i: HTTP $http_code | Pool: $pool"
  fi
  
  if [ "$pool" == "green" ]; then
    green_count=$((green_count + 1))
  fi
  
  sleep 0.3
done

echo "Stopping chaos on Blue..."
curl -s -X POST "http://localhost:8081/chaos/stop" > /dev/null

green_percentage=$((green_count * 100 / 15))

echo "---"
echo "Summary: Green responses: $green_count | Green %: $green_percentage%"

if [ $failed_requests -eq 0 ] && [ $green_percentage -ge 95 ]; then
  echo -e "${GREEN}✓ Test 5 PASSED: Zero failed requests and ≥95% traffic on Green${NC}\n"
else
  echo -e "${RED}✗ Test 5 FAILED: $failed_requests requests failed or insufficient Green traffic${NC}\n"
fi

# Final Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Suite Complete${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "\nKey metrics for grader validation:"
echo "- All failover tests should have ZERO non-200 responses"
echo "- After chaos, ≥95% of responses should be from Green"
echo "- Headers should correctly identify the active pool"
echo "- Blue should recover after chaos ends"
