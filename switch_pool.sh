#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Usage: ./switch_pool.sh [blue|green]"
    exit 1
fi

TARGET_POOL=$1

if [ "$TARGET_POOL" != "blue" ] && [ "$TARGET_POOL" != "green" ]; then
    echo "Error: Pool must be 'blue' or 'green'"
    exit 1
fi

echo "Switching active pool to: $TARGET_POOL"

# Update .env file
if [ "$TARGET_POOL" == "blue" ]; then
    sed -i 's/^BLUE_BACKUP=.*/BLUE_BACKUP=/' .env
    sed -i 's/^GREEN_BACKUP=.*/GREEN_BACKUP=backup/' .env
    sed -i 's/^ACTIVE_POOL=.*/ACTIVE_POOL=blue/' .env
else
    sed -i 's/^BLUE_BACKUP=.*/BLUE_BACKUP=backup/' .env
    sed -i 's/^GREEN_BACKUP=.*/GREEN_BACKUP=/' .env
    sed -i 's/^ACTIVE_POOL=.*/ACTIVE_POOL=green/' .env
fi

# Restart nginx to apply changes
echo "Restarting nginx..."
docker compose restart nginx

echo "Waiting for nginx to stabilize..."
sleep 3

# Test the switch
echo "Testing new configuration..."
curl -s http://localhost:8080/version -i | grep "X-App-Pool"

echo "Done! Active pool is now: $TARGET_POOL"