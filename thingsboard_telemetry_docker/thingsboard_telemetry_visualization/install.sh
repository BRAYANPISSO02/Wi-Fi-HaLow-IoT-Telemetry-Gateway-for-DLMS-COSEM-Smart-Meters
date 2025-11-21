#!/usr/bin/env bash
set -euo pipefail

# Enhanced ThingsBoard DB install/migration script.
# Features:
#  - Flags: --demo, --no-demo, --force, --wait, --timeout=<s>, --help
#  - Auto-detect compose plugin/binary
#  - Optional wait for postgres health before running migrations
#  - Idempotent: detect if schema already exists (simple probe) unless --force
#  - Respects env var LOAD_DEMO=true|false as legacy override
#
# Examples:
#   ./install.sh                 # install (no demo)
#   ./install.sh --demo          # install + demo data
#   ./install.sh --wait          # wait for postgres health (if stack up separately)
#   LOAD_DEMO=true ./install.sh  # legacy style (equivalent to --demo)
#   ./install.sh --force --demo  # re-run even if appears already installed

cd "$(dirname "$0")"

LOAD_DEMO_FLAG=${LOAD_DEMO:-false}
FORCE=0
WAIT=0
TIMEOUT=180

usage() {
  cat <<EOF
Usage: $0 [--demo|--no-demo] [--force] [--wait] [--timeout=SECONDS]
          [--help]

Flags:
  --demo           Cargar datos de demo además del esquema.
  --no-demo        No cargar datos de demo (por defecto).
  --force          Forzar ejecución aunque parezca ya instalado.
  --wait           Esperar a que Postgres esté healthy (requiere servicio 'postgres').
  --timeout=SECS   Tiempo máximo de espera con --wait (default: 180).
  --help           Mostrar esta ayuda.

También puedes usar LOAD_DEMO=true/false como variable de entorno (legacy).
EOF
}

for arg in "$@"; do
  case "$arg" in
    --demo) LOAD_DEMO_FLAG=true ;;
    --no-demo) LOAD_DEMO_FLAG=false ;;
    --force) FORCE=1 ;;
    --wait) WAIT=1 ;;
    --timeout=*) TIMEOUT="${arg#*=}" ;;
    --help|-h) usage; exit 0 ;;
    *) echo "[error] Opción desconocida: $arg" >&2; usage; exit 1 ;;
  esac
done

echo "[thingsboard] Install start (demo=${LOAD_DEMO_FLAG} force=${FORCE} wait=${WAIT} timeout=${TIMEOUT}s)"

# Detect docker compose (v2 plugin or legacy binary)
dc() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    echo "[error] Neither 'docker compose' nor 'docker-compose' found in PATH." >&2
    exit 2
  fi
}

# Simple idempotency check: try to query an existing table (tenant) via psql if postgres service is up.
already_installed=0
sysadmin_exists=0
if docker ps --format '{{.Names}}' | grep -q '^thingsboard-postgres-'; then
  if command -v psql >/dev/null 2>&1; then
    # local psql may not have network route to container mapped port; fallback using a temp psql container
    POSTGRES_CONT=$(docker ps --format '{{.Names}}' | grep '^thingsboard-postgres-' | head -n1 || true)
    if [[ -n "$POSTGRES_CONT" ]]; then
      # exec psql inside container
      # Use count(*) for robustness (avoid relying on limit order)
      if docker exec "$POSTGRES_CONT" bash -c "psql -U postgres -d thingsboard -tc 'select count(*) from tenant'" 2>/dev/null | grep -Eq '^[[:space:]]*[0-9]+'; then
        already_installed=1
      fi
      # Check if sysadmin user already exists (email unique constraint trigger)
      if docker exec "$POSTGRES_CONT" bash -c "psql -U postgres -d thingsboard -tc \"select 1 from tb_user where email='sysadmin@thingsboard.org' limit 1\"" | grep -q 1; then
        sysadmin_exists=1
      fi
    fi
  else
    POSTGRES_CONT=$(docker ps --format '{{.Names}}' | grep '^thingsboard-postgres-' | head -n1 || true)
    if [[ -n "$POSTGRES_CONT" ]]; then
      if docker exec "$POSTGRES_CONT" bash -c "psql -U postgres -d thingsboard -tc 'select count(*) from tenant'" 2>/dev/null | grep -Eq '^[[:space:]]*[0-9]+'; then
        already_installed=1
      fi
      if docker exec "$POSTGRES_CONT" bash -c "psql -U postgres -d thingsboard -tc \"select 1 from tb_user where email='sysadmin@thingsboard.org' limit 1\"" | grep -q 1; then
        sysadmin_exists=1
      fi
    fi
  fi
fi

if [[ $FORCE -ne 1 ]]; then
  if [[ $already_installed -eq 1 || $sysadmin_exists -eq 1 ]]; then
    echo "[thingsboard] Instalación ya detectada (tenant count o sysadmin existente). Usa --force para reejecutar o --demo para intentar cargar demo adicional." >&2
    exit 0
  fi
fi

if [[ $WAIT -eq 1 ]]; then
  echo "[thingsboard] Esperando a Postgres (timeout ${TIMEOUT}s)..."
  start_ts=$(date +%s)
  while true; do
    if dc ps --format '{{.Name}} {{.State}}' 2>/dev/null | grep -q 'postgres running'; then
      # healthcheck may not be ready yet
      if docker inspect --format '{{json .State.Health.Status}}' thingsboard-postgres-1 2>/dev/null | grep -q 'healthy'; then
        echo "[thingsboard] Postgres healthy."
        break
      fi
    fi
    now=$(date +%s)
    if (( now - start_ts > TIMEOUT )); then
      echo "[error] Timeout esperando a Postgres." >&2
      exit 3
    fi
    sleep 3
  done
fi

dc run --rm \
  -e INSTALL_TB=true \
  -e LOAD_DEMO=${LOAD_DEMO_FLAG} \
  thingsboard-ce

echo "[thingsboard] Install finished. If services were not up, start with ./up.sh"
