#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${JAVA_HOME:-}" ]]; then
  echo "JAVA_HOME is not set. Install JDK 17+ and rerun this command." >&2
  exit 1
fi
export PATH="$JAVA_HOME/bin:$PATH"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required but was not found in PATH." >&2
  exit 1
fi

docker compose -f "$ROOT_DIR/docker-compose.yml" up -d

for dir in payment-service fraud-detection-service notification-service api-gateway; do
  echo "Compiling $dir..."
  (cd "$ROOT_DIR/$dir" && ./mvnw test -q)
done

curl -fsS http://localhost:8080/actuator/health >/dev/null

echo "Smoke tests passed."
