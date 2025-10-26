#!/bin/bash

# Generate nginx.conf from template
envsubst '${ACTIVE_POOL}' < nginx.conf.template > nginx.conf

echo "Nginx config generated successfully!"
echo "Active pool: $ACTIVE_POOL"