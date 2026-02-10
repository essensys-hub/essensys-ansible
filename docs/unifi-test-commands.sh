#!/bin/bash
# Script de test UniFi Protect API

API_KEY="tUMJhGwzryEJ7KuWZU2FUQGIa5F5R60_"
BASE_URL="https://192.168.0.1"

echo "=== Test 1: Meta Info (exemple fourni) ==="
curl -k -X GET "${BASE_URL}/proxy/protect/integration/v1/meta/info" \
  -H "X-API-KEY: ${API_KEY}" \
  -H "Accept: application/json" \
  -w "\nHTTP: %{http_code}\n" \
  -s | head -30

echo -e "\n=== Test 2: Bootstrap API (/proxy/protect/api/bootstrap) ==="
curl -k -X GET "${BASE_URL}/proxy/protect/api/bootstrap" \
  -H "X-API-KEY: ${API_KEY}" \
  -H "Accept: application/json" \
  -w "\nHTTP: %{http_code}\n" \
  -s | head -50

echo -e "\n=== Test 3: Bootstrap Integration (/proxy/protect/integration/v1/bootstrap) ==="
curl -k -X GET "${BASE_URL}/proxy/protect/integration/v1/bootstrap" \
  -H "X-API-KEY: ${API_KEY}" \
  -H "Accept: application/json" \
  -w "\nHTTP: %{http_code}\n" \
  -s | head -50

echo -e "\n=== Test 4: Via Backend Proxy ==="
curl -X GET "http://localhost:7070/api/unifi/cameras" \
  -H "Accept: application/json" \
  -w "\nHTTP: %{http_code}\n" \
  -s | head -50
