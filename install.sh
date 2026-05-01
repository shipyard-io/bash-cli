#!/usr/bin/env bash
set -euo pipefail

REPO="shipyard-io/templates"
BIN_NAME="shipyard"
INSTALL_DIR="${SHIPYARD_INSTALL_DIR:-$HOME/.local/bin}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

log() { printf "[shipyard-installer] %s\n" "$*"; }
err() { printf "[shipyard-installer] ERROR: %s\n" "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || err "Missing required command: $1"
}

detect_os() {
  local os
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "$os" in
    linux) echo "linux" ;;
    darwin) echo "darwin" ;;
    *) err "Unsupported OS: $os" ;;
  esac
}

detect_arch() {
  local arch
  arch="$(uname -m | tr '[:upper:]' '[:lower:]')"
  case "$arch" in
    x86_64|amd64) echo "amd64" ;;
    arm64|aarch64) echo "arm64" ;;
    *) err "Unsupported architecture: $arch" ;;
  esac
}

install_binary() {
  local src="$1"
  mkdir -p "$INSTALL_DIR"
  install -m 0755 "$src" "$INSTALL_DIR/$BIN_NAME"
  log "Installed $BIN_NAME to $INSTALL_DIR/$BIN_NAME"

  case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *)
      log "Add this to your shell profile if needed:"
      log "  export PATH=\"$INSTALL_DIR:\$PATH\""
      ;;
  esac
}

download_release_binary() {
  need_cmd curl
  local os arch version asset url out
  os="$(detect_os)"
  arch="$(detect_arch)"

  version="${SHIPYARD_VERSION:-latest}"
  asset="shipyard_${os}_${arch}.tar.gz"

  if [ "$version" = "latest" ]; then
    url="https://github.com/${REPO}/releases/latest/download/${asset}"
  else
    url="https://github.com/${REPO}/releases/download/${version}/${asset}"
  fi

  out="$TMP_DIR/$asset"
  log "Trying to download prebuilt binary: $url"
  if ! curl -fsSL "$url" -o "$out"; then
    return 1
  fi

  tar -xzf "$out" -C "$TMP_DIR"
  if [ ! -f "$TMP_DIR/$BIN_NAME" ]; then
    err "Archive downloaded but binary '$BIN_NAME' not found"
  fi

  install_binary "$TMP_DIR/$BIN_NAME"
  return 0
}

build_from_source() {
  need_cmd git
  need_cmd go

  local ref
  ref="${SHIPYARD_VERSION:-main}"

  log "Falling back to source build (ref: $ref)"
  git clone --depth 1 --branch "$ref" "https://github.com/${REPO}.git" "$TMP_DIR/templates"
  (cd "$TMP_DIR/templates/bash-cli" && go build -o "$TMP_DIR/$BIN_NAME" ./cmd/shipyard)
  install_binary "$TMP_DIR/$BIN_NAME"
}

run_shipyard() {
  local cmd="${1:-}"
  if [ -z "$cmd" ]; then
    log "Usage after install: shipyard setup | shipyard secrets"
    return 0
  fi
  shift || true
  "$INSTALL_DIR/$BIN_NAME" "$cmd" "$@"
}

main() {
  if download_release_binary; then
    :
  else
    log "No prebuilt binary found for this platform/version."
    build_from_source
  fi

  run_shipyard "$@"
}

main "$@"
