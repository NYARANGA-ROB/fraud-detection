#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKIP_DOCKER=false
SKIP_TESTS=false

for arg in "$@"; do
  case "$arg" in
    --skip-docker)
      SKIP_DOCKER=true
      ;;
    --skip-tests)
      SKIP_TESTS=true
      ;;
    -h|--help)
      echo "Usage: $0 [--skip-docker] [--skip-tests]"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

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
}

ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is required but was not found in PATH." >&2
    exit 1
  fi
  docker compose -f "$ROOT_DIR/docker-compose.yml" up -d
}

run_java_tests() {
  for dir in payment-service fraud-detection-service notification-service api-gateway; do
    echo "Running tests for $dir..."
    (cd "$ROOT_DIR/$dir" && ./mvnw test -q)
  done
}

ensure_java
ensure_python_env
if [[ "$SKIP_DOCKER" != true ]]; then
  ensure_docker
fi
if [[ "$SKIP_TESTS" != true ]]; then
  run_java_tests
fi

echo ""
echo "Bootstrap complete."
echo "Next: use ./scripts/dev.sh start to launch the stack."
