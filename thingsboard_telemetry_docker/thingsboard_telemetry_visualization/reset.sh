#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)

MODE="hard" # hard: down -v (borra volúmenes). soft: down (mantiene volúmenes)

usage() {
  cat <<EOF
Uso: $0 [--soft|--keep-volumes] [--hard]

  --soft | --keep-volumes  Detiene y elimina contenedores/red sin borrar volúmenes (datos se conservan)
  --hard                    Detiene y además elimina volúmenes (limpieza total) [por defecto]

Ejemplos:
  $0 --soft
  $0 --hard
EOF
}

for arg in "${@:-}"; do
  case "$arg" in
    --soft|--keep-volumes)
      MODE="soft" ;;
    --hard)
      MODE="hard" ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Opción no reconocida: $arg" >&2
      usage; exit 1 ;;
  esac
done

cd "$SCRIPT_DIR"

if [[ "$MODE" == "soft" ]]; then
  echo "[reset] Soft reset: deteniendo y eliminando contenedores/red, conservando volúmenes..."
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
  dc down || true
  echo "[reset] Hecho. Tus datos en volúmenes Docker permanecen intactos. Puedes iniciar con ./up.sh"
else
  read -rp "Esto detendrá TB y borrará los volúmenes de Docker (Postgres/Kafka). ¿Continuar? (yes/NO): " ans
  if [[ "${ans:-}" != "yes" ]]; then
    echo "Cancelado."
    exit 1
  fi
  echo "[reset] Hard reset: deteniendo y eliminando contenedores/red y volúmenes..."
  dc down -v || true
  echo "Hecho. Vuelve a ejecutar ./up.sh y luego la inicialización:"
  echo "  docker compose run --rm -e INSTALL_TB=true -e LOAD_DEMO=true thingsboard-ce"
fi
