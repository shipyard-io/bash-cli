#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -x "${SCRIPT_DIR}/shipyard" ]; then
  echo "Shipyard Go binary not found. Building..."
  (cd "${SCRIPT_DIR}" && go build -o shipyard ./cmd/shipyard)
fi

exec "${SCRIPT_DIR}/shipyard" secrets
