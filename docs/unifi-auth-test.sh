#!/bin/bash
# Test d'authentification UniFi Protect avec username/password puis utilisation du token

BASE_URL="https://192.168.0.1"
USERNAME="admin"  # Remplacez par votre username
PASSWORD="your_password"  # Remplacez par votre password

echo "=== Étape 1: Authentification avec username/password ==="
AUTH_RESPONSE=$(curl -k -X POST "${BASE_URL}/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${USERNAME}\",\"password\":\"${PASSWORD}\"}" \
  -c /tmp/unifi_cookies.txt \
  -w "\nHTTP: %{http_code}\n" \
  -s)

echo "$AUTH_RESPONSE"

# Extraire le token du header Authorization ou des cookies
TOKEN=$(curl -k -X POST "${BASE_URL}/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${USERNAME}\",\"password\":\"${PASSWORD}\"}" \
  -D - -s | grep -i "authorization\|set-cookie" | head -1)

echo -e "\nToken/Cookie extrait: $TOKEN"

echo -e "\n=== Étape 2: Test bootstrap avec cookies de session ==="
curl -k -X GET "${BASE_URL}/api/bootstrap" \
  -b /tmp/unifi_cookies.txt \
  -H "Accept: application/json" \
  -w "\nHTTP: %{http_code}\n" \
  -s | head -20

echo -e "\n=== Étape 3: Test avec API key après auth ==="
API_KEY="tUMJhGwzryEJ7KuWZU2FUQGIa5F5R60_"
curl -k -X GET "${BASE_URL}/unifi-api/protect/integration/v1/meta/info" \
  -b /tmp/unifi_cookies.txt \
  -H "X-API-KEY: ${API_KEY}" \
  -H "Accept: application/json" \
  -w "\nHTTP: %{http_code}\n" \
  -s | head -20
