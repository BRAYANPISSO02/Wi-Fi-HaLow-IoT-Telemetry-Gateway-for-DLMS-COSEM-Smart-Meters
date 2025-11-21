#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)

# Detect docker compose (v2 plugin or legacy binary)
dc() {
    if docker compose version >/dev/null 2>&1; then
        docker compose "$@"
    elif command -v docker-compose >/dev/null 2>&1; then
        docker-compose "$@"
    else
        echo "[error] Neither 'docker compose' nor 'docker-compose' found in PATH." >&2
        echo "        Install Docker Compose v2 (recommended) or v1." >&2
        exit 2
    fi
}

# Ensure data dirs exist with permissive perms for Docker on macOS/Linux
mkdir -p "$REPO_DIR/data/thingsboard/postgres" "$REPO_DIR/data/thingsboard/logs"

# -----------------------------------------------------------------------------
# Port pre-check (can be skipped with SKIP_PORT_CHECK=1)
# Set FORCE_START=1 to proceed even if conflicts detected.
# -----------------------------------------------------------------------------
if [[ "${SKIP_PORT_CHECK:-0}" != "1" ]]; then
	PORTS_TCP=(8080 7070 1883 8883 9092)
	PORTS_UDP_RANGE_START=5683
	PORTS_UDP_RANGE_END=5688
	conflict=0
	echo "[up] Checking required host TCP ports: ${PORTS_TCP[*]}"
	for p in "${PORTS_TCP[@]}"; do
		if ss -ltn 2>/dev/null | grep -q ":$p "; then
			echo "[warn] TCP port $p appears to be in use." >&2
			conflict=1
		fi
	done
	echo "[up] Checking required UDP port range: ${PORTS_UDP_RANGE_START}-${PORTS_UDP_RANGE_END}"
	for ((u=PORTS_UDP_RANGE_START; u<=PORTS_UDP_RANGE_END; u++)); do
		if ss -lun 2>/dev/null | grep -q ":$u "; then
			echo "[warn] UDP port $u appears to be in use." >&2
			conflict=1
		fi
	done
	if [[ $conflict -eq 1 ]]; then
		if [[ "${FORCE_START:-0}" == "1" ]]; then
			echo "[up] Conflicts detected but FORCE_START=1 set. Continuing..." >&2
		else
			cat <<EOF >&2
[error] One or more required ports are in use.
				Libera los puertos o ejecuta uno de:
					SKIP_PORT_CHECK=1 $0        # omitir chequeo (no recomendado)
					FORCE_START=1 $0            # continuar a pesar de conflictos
				Para diagnosticar procesos:
					sudo ss -ltnp | grep -E ':8080 |:7070 |:1883 |:8883 |:9092 '
					sudo ss -lunp | grep -E ':5683 '
EOF
			exit 1
		fi
	fi
fi

echo "Starting ThingsBoard CE stack (Postgres + Kafka + tb-node) ..."
cd "$SCRIPT_DIR"
dc up -d
echo "REST/API (and UI if present): http://localhost:8080"
echo "Kafka (host): localhost:9092"
