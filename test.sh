#!/bin/bash

for i in {1..5}; do 
  echo "Request $i:"
  curl -s http://localhost:8080/version -i | grep -E "HTTP|X-App-Pool|X-Release-Id"
  echo "---"
done