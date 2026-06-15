#!/bin/bash
# Script pour tester tous les endpoints possibles UniFi Protect

API_KEY="tUMJhGwzryEJ7KuWZU2FUQGIa5F5R60_"
BASE_URL="https://192.168.0.1"

echo "=== Test 1: /unifi-api/protect/api/bootstrap ==="
curl -k -X GET "${BASE_URL}/unifi-api/protect/api/bootstrap" \
  -H "X-API-KEY: ${API_KEY}" \
  -H "Accept: application/json" \
  -w "\nHTTP: %{http_code}\n" \
  -s | head -5

echo -e "\n=== Test 2: /api/bootstrap ==="
curl -k -X GET "${BASE_URL}/api/bootstrap" \
  -H "X-API-KEY: ${API_KEY}" \
  -H "Accept: application/json" \
  -w "\nHTTP: %{http_code}\n" \
  -s | head -5

echo -e "\n=== Test 3: /proxy/protect/api/bootstrap ==="
curl -k -X GET "${BASE_URL}/proxy/protect/api/bootstrap" \
  -H "X-API-KEY: ${API_KEY}" \
  -H "Accept: application/json" \
  -w "\nHTTP: %{http_code}\n" \
  -s | head -5

echo -e "\n=== Test 4: /unifi-api/protect/bootstrap (sans /api) ==="
curl -k -X GET "${BASE_URL}/unifi-api/protect/bootstrap" \
  -H "X-API-KEY: ${API_KEY}" \
  -H "Accept: application/json" \
  -w "\nHTTP: %{http_code}\n" \
  -s | head -5

echo -e "\n=== Test 5: /proxy/protect/bootstrap (sans /api) ==="
curl -k -X GET "${BASE_URL}/proxy/protect/bootstrap" \
  -H "X-API-KEY: ${API_KEY}" \
  -H "Accept: application/json" \
  -w "\nHTTP: %{http_code}\n" \
  -s | head -5

echo -e "\n=== Test 6: /unifi-api/protect/integration/v1/bootstrap ==="
curl -k -X GET "${BASE_URL}/unifi-api/protect/integration/v1/bootstrap" \
  -H "X-API-KEY: ${API_KEY}" \
  -H "Accept: application/json" \
  -w "\nHTTP: %{http_code}\n" \
  -s | head -5

echo -e "\n=== Test 7: /unifi-api/protect/integration/v1/meta/info (exemple doc) ==="
curl -k -X GET "${BASE_URL}/unifi-api/protect/integration/v1/meta/info" \
  -H "X-API-KEY: ${API_KEY}" \
  -H "Accept: application/json" \
  -w "\nHTTP: %{http_code}\n" \
  -s | head -10

echo -e "\n=== Test 8: Vérifier la doc API ==="
curl -k -X GET "${BASE_URL}/unifi-api/protect" \
  -H "X-API-KEY: ${API_KEY}" \
  -H "Accept: application/json" \
  -w "\nHTTP: %{http_code}\n" \
  -s | head -10
