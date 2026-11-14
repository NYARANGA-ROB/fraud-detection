#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/logs"
mkdir -p "$LOG_DIR"

command="${1:-start}"

ensure_java() {
  if [[ -z "${JAVA_HOME:-}" ]]; then
    echo "JAVA_HOME is not set. Install JDK 17+ and rerun this command." >&2
    exit 1
  fi
  export PATH="$JAVA_HOME/bin:$PATH"
}

ensure_python_env() {
  local venv_path="$ROOT_DIR/ai-reasoning-service/.venv"
  if [[ ! -x "$venv_path/bin/python" ]]; then
    python3 -m venv "$venv_path"
  fi
  "$venv_path/bin/python" -m pip install --quiet -r "$ROOT_DIR/ai-reasoning-service/requirements.txt"
  echo "$venv_path/bin/python"
}

start_services() {
  ensure_java
  local venv_python
  venv_python="$(ensure_python_env)"

  echo "Starting infrastructure..."
  docker compose -f "$ROOT_DIR/docker-compose.yml" up -d

  echo "Starting Java services..."
  nohup bash -lc "cd '$ROOT_DIR/payment-service' && ./mvnw spring-boot:run" > "$LOG_DIR/payment-service.log" 2>&1 &
  nohup bash -lc "cd '$ROOT_DIR/fraud-detection-service' && ./mvnw spring-boot:run" > "$LOG_DIR/fraud-detection-service.log" 2>&1 &
  nohup bash -lc "cd '$ROOT_DIR/notification-service' && ./mvnw spring-boot:run" > "$LOG_DIR/notification-service.log" 2>&1 &
  nohup bash -lc "cd '$ROOT_DIR/api-gateway' && ./mvnw spring-boot:run" > "$LOG_DIR/api-gateway.log" 2>&1 &

  echo "Starting AI reasoning service..."
  nohup bash -lc "cd '$ROOT_DIR/ai-reasoning-service' && '$venv_python' main.py" > "$LOG_DIR/ai-reasoning-service.log" 2>&1 &

  echo ""
  echo "Services are starting. Logs are in $LOG_DIR"
  echo "Open:"
  echo "  http://localhost:8080"
  echo "  http://localhost:8081/swagger-ui.html"
  echo "  http://localhost:8082/swagger-ui.html"
  echo "  http://localhost:8083/swagger-ui.html"
  echo "  http://localhost:8084/docs"
}

stop_services() {
  pgrep -af 'spring-boot:run|main.py|fraud-detection|payment-service|notification-service|api-gateway' | awk '{print $1}' | xargs -r kill
  echo "Stopped project services."
}

status_services() {
  pgrep -af 'spring-boot:run|main.py|fraud-detection|payment-service|notification-service|api-gateway' || true
}

run_tests() {
  ensure_java
  for dir in payment-service fraud-detection-service notification-service api-gateway; do
    echo "Running tests for $dir..."
    (cd "$ROOT_DIR/$dir" && ./mvnw test -q)
  done
  echo "All service tests passed."
}

case "$command" in
  start)
    start_services
    ;;
  stop)
    stop_services
    ;;
  status)
    status_services
    ;;
  test)
    run_tests
    ;;
  *)
    echo "Usage: $0 [start|stop|status|test]" >&2
    exit 1
    ;;
 esac
