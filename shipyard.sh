#!/usr/bin/env bash
set -euo pipefail

# fix: redirect read from tty per-command for curl | bash compatibility

# ========================
# COLORS
# ========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ========================
# LOGGING
# ========================
info()    { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
success() { printf "${GREEN}[SUCCESS]${NC} %s\n" "$*"; }
warn()    { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
error()   { printf "${RED}[ERROR]${NC} %s\n" "$*"; exit 1; }

# ========================
# CLEANUP (fix stty bug)
# ========================
cleanup() {
  stty echo 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# ========================
# INPUT HELPERS
# ========================
ask() {
  local prompt="$1"
  local default="${2:-}"
  local secret="${3:-false}"
  local value

  printf "${CYAN}➜ %s${NC}" "$prompt" >&2
  [ -n "$default" ] && printf " (${YELLOW}%s${NC})" "$default" >&2
  printf ": " >&2

  if [ "$secret" = "true" ]; then
    stty -echo < /dev/tty
    read -r value < /dev/tty
    stty echo < /dev/tty
    printf "\n" >&2
  else
    read -r value < /dev/tty
  fi

  echo "${value:-$default}"
}

ask_required() {
  local value=""
  while [ -z "$value" ]; do
    value=$(ask "$1" "${2:-}")
    [ -z "$value" ] && warn "Không được để trống" >&2
  done
  echo "$value"
}

ask_choice() {
  local prompt="$1"; shift
  local options=("$@")
  local choice=""

  if command -v fzf >/dev/null 2>&1; then
    choice=$(printf "%s\n" "${options[@]}" | fzf --height 10 --reverse --border --prompt "➜ $prompt > ")
  fi

  if [ -z "$choice" ]; then
    printf "${CYAN}➜ %s${NC}\n" "$prompt" >&2
    local i=1
    for opt in "${options[@]}"; do
      printf "  %d) %s\n" "$i" "$opt" >&2
      ((i++))
    done
    printf "Chọn (1-%d): " "$((i-1))" >&2
    read -r idx < /dev/tty
    choice="${options[$((idx-1))]}"
  fi

  echo "$choice"
}

check_cloudflare() {
  local domain="$1"
  local root_domain="$2"
  if [ "$HAS_DIG" = true ]; then
    # Kiểm tra trực tiếp domain
    if [ -n "$domain" ] && dig +short NS "$domain" | grep -qi "cloudflare.com"; then
      return 0
    fi
    # Kiểm tra root domain nếu domain hiện tại là subdomain
    if [ -n "$root_domain" ] && dig +short NS "$root_domain" | grep -qi "cloudflare.com"; then
      return 0
    fi
  fi
  return 1
}

# ========================
# HEADER
# ========================
printf "${CYAN}"
cat << "EOF"
  ____  _     _                           _
 / ___|| |__ (_)_ __  _   _  __ _ _ __ __| |
 \___ \| '_ \| | '_ \| | | |/ _` | '__/ _` |
  ___) | | | | | |_) | |_| | (_| | | | (_| |
 |____/|_| |_|_| .__/ \__, |\__,_|_|  \__,_|
               |_|    |___/
EOF
printf "${NC}"
printf "%s\n\n" "--- Shipyard Zero-Touch Setup CLI ---"

# ========================
# CHECK DEPENDENCIES
# ========================
command -v gh >/dev/null || error "Thiếu GitHub CLI: https://cli.github.com/"
command -v curl >/dev/null || error "Thiếu lệnh 'curl' để thực hiện các yêu cầu mạng."

if ! gh auth status >/dev/null 2>&1; then
  error "Chưa login GitHub CLI. Chạy: gh auth login"
fi

HAS_DIG=false
command -v dig >/dev/null && HAS_DIG=true

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
[ -z "$REPO" ] && error "Không tìm thấy repo GitHub hiện tại"

# ========================
# STEP 1: SERVER
# ========================
printf "${YELLOW}>>> BƯỚC 1: SERVER${NC}\n"

SERVER_IP=$(ask_required "Server IP")
SERVER_USER=$(ask "SSH User" "root")
SSH_KEY_PATH=$(ask "SSH Private Key" "$HOME/.ssh/id_rsa")

[ ! -f "$SSH_KEY_PATH" ] && error "Không tìm thấy SSH key"
chmod 600 "$SSH_KEY_PATH" 2>/dev/null || true

info "Checking SSH..."
if ssh -i "$SSH_KEY_PATH" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${SERVER_USER}@${SERVER_IP}" "exit" >/dev/null 2>&1; then
  success "SSH OK"
else
  error "SSH fail"
fi

# ========================
# STEP 2: TELEGRAM
# ========================
printf "\n${YELLOW}>>> BƯỚC 2: TELEGRAM${NC}\n"

TELEGRAM_BOT_TOKEN=$(ask "Bot Token" "" true)
TELEGRAM_CHAT_ID=$(ask "Chat ID")

if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
  info "Gửi tin nhắn test tới Telegram..."
  TG_RES=$(curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" \
    -d text="🚀 *Shipyard CLI*: Kết nối thành công! Repo: $REPO" \
    -d parse_mode="Markdown")
  
  if echo "$TG_RES" | grep -q '"ok":true'; then
    success "Telegram test OK"
  else
    warn "Telegram test fail: $(echo "$TG_RES" | grep -o '"description":"[^"]*"' | cut -d'"' -f4)"
  fi
fi

# ========================
# STEP 3: APP
# ========================
printf "\n${YELLOW}>>> BƯỚC 3: APP${NC}\n"

APP_NAME=$(ask_required "App Name")
APP_DOMAIN=$(ask "App Domain")
DOMAIN=$(ask "Root Domain")
APP_PORT=$(ask "Port" "80")
HEALTH_CHECK_PATH=$(ask "Health Path" "/")

# DNS CHECK
if [ "$HAS_DIG" = true ]; then
  for d in "$APP_DOMAIN" "$DOMAIN"; do
    [ -z "$d" ] && continue
    info "Checking DNS: $d..."
    DOMAIN_IP=$(dig +short "$d" | tail -n1)
    
    if [ "$DOMAIN_IP" = "$SERVER_IP" ]; then
      success "DNS OK: $d -> $SERVER_IP"
    elif check_cloudflare "$d" "$DOMAIN"; then
      success "DNS OK: $d -> Cloudflare Proxy detected"
    elif [ -n "$DOMAIN_IP" ]; then
      warn "DNS WARNING: $d đang trỏ về $DOMAIN_IP (Kỳ vọng: $SERVER_IP hoặc Cloudflare)"
    else
      warn "DNS FAIL: Không tìm thấy bản ghi cho $d"
    fi
  done
fi

# ========================
# STEP 4: ENV
# ========================
printf "\n${YELLOW}>>> BƯỚC 4: ENV${NC}\n"

MODE=$(ask_choice "Chọn mode ENV" \
  "Manual (KEY=VALUE)" \
  "Paste .env")

CUSTOM_ENVS=""

if [[ "$MODE" == *Paste* ]]; then
  echo "Paste .env (Ctrl+D để kết thúc):" >&2
  CUSTOM_ENVS=$(cat < /dev/tty)
else
  while true; do
    entry=$(ask "ENV (empty to stop)")
    [ -z "$entry" ] && break
    CUSTOM_ENVS+="$entry"$'\n'
  done
fi

ENV_CONTENT="APP_NAME=$APP_NAME
APP_PORT=$APP_PORT
APP_DOMAIN=$APP_DOMAIN
DOMAIN=$DOMAIN
HEALTH_CHECK_PATH=$HEALTH_CHECK_PATH
INIT_INFRA=true
$CUSTOM_ENVS"

# ========================
# STEP 5: SECRETS
# ========================
printf "\n${YELLOW}>>> BƯỚC 5: GITHUB SECRETS${NC}\n"

info "Repo: $REPO"

printf "%s" "$SERVER_IP"        | gh secret set SERVER_IP
printf "%s" "$SERVER_USER"      | gh secret set SERVER_USER
gh secret set SSH_PRIVATE_KEY < "$SSH_KEY_PATH"

[ -n "$TELEGRAM_BOT_TOKEN" ] && printf "%s" "$TELEGRAM_BOT_TOKEN" | gh secret set TELEGRAM_BOT_TOKEN
[ -n "$TELEGRAM_CHAT_ID" ] && printf "%s" "$TELEGRAM_CHAT_ID" | gh secret set TELEGRAM_CHAT_ID

printf "%s" "$ENV_CONTENT" | gh secret set ENV_FILE_CONTENT

# ========================
# DONE
# ========================
echo ""
printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
success "DONE"
echo "Repo: $REPO"
echo "App:  $APP_NAME"
echo ""
echo "Deploy:"
echo "git add . && git commit -m 'init' && git push"
printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"