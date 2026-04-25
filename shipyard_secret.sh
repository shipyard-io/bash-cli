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
# CLEANUP
# ========================
cleanup() { stty echo < /dev/tty 2>/dev/null || true; }
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

ask_choice() {
  local prompt="$1"; shift
  local options=("$@")
  local choice=""

  if command -v fzf >/dev/null 2>&1; then
    choice=$(printf "%s\n" "${options[@]}" | fzf --height 10 --reverse --border --prompt "➜ $prompt > ")
    stty sane < /dev/tty 2>/dev/null || true
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
printf "%s\n\n" "--- Shipyard Secret Manager ---"

# ========================
# CHECK DEPENDENCIES
# ========================
command -v gh >/dev/null || error "Thiếu GitHub CLI: https://cli.github.com/"

if ! gh auth status >/dev/null 2>&1; then
  error "Chưa login GitHub CLI. Chạy: gh auth login"
fi

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
[ -z "$REPO" ] && error "Không tìm thấy repo GitHub hiện tại"

printf "${BLUE}[INFO]${NC} Repo: ${CYAN}%s${NC}\n" "$REPO"
echo ""

# ========================
# DANH SÁCH SECRETS
# ========================
get_desc() {
  case "$1" in
    SERVER_IP)              echo "Địa chỉ IP của VPS" ;;
    SERVER_USER)            echo "SSH username (thường là root)" ;;
    SSH_PRIVATE_KEY)        echo "Nội dung SSH Private Key (file)" ;;
    TELEGRAM_BOT_TOKEN)     echo "Token của Telegram Bot (secret)" ;;
    TELEGRAM_CHAT_ID)       echo "Chat ID nhận thông báo" ;;
    CLOUDFLARE_ORIGIN_CERT) echo "Cloudflare Origin Certificate (.pem)" ;;
    CLOUDFLARE_ORIGIN_KEY)  echo "Cloudflare Origin Private Key (.pem)" ;;
    TRAEFIK_DASHBOARD_AUTH) echo "Traefik Basic Auth (htpasswd format)" ;;
    ENV_FILE_CONTENT)       echo "Toàn bộ nội dung file .env" ;;
    *)                      echo "" ;;
  esac
}

SECRET_LIST=(
  "SERVER_IP"
  "SERVER_USER"
  "SSH_PRIVATE_KEY"
  "TELEGRAM_BOT_TOKEN"
  "TELEGRAM_CHAT_ID"
  "CLOUDFLARE_ORIGIN_CERT"
  "CLOUDFLARE_ORIGIN_KEY"
  "TRAEFIK_DASHBOARD_AUTH"
  "ENV_FILE_CONTENT"
  "Tùy chỉnh (nhập tên secret)"
)

# ========================
# VÒNG LẶP CHÍNH
# ========================
while true; do
  echo ""
  printf "${YELLOW}>>> Chọn secret cần cập nhật:${NC}\n"

  SELECTED=$(ask_choice "Secret cần set" "${SECRET_LIST[@]}" "Thoát")

  if [ "$SELECTED" = "Thoát" ] || [ -z "$SELECTED" ]; then
    break
  fi

  # Xác định tên secret
  if [[ "$SELECTED" == "Tùy chỉnh"* ]]; then
    SECRET_NAME=$(ask "Nhập tên secret (VD: MY_API_KEY)")
    [ -z "$SECRET_NAME" ] && warn "Tên secret không được trống" && continue
  else
    SECRET_NAME="$SELECTED"
  fi

  DESC=$(get_desc "$SECRET_NAME")
  [ -n "$DESC" ] && printf "${BLUE}  → %s${NC}\n" "$DESC" >&2

  # Xử lý từng loại secret đặc biệt
  case "$SECRET_NAME" in
    SSH_PRIVATE_KEY)
      SSH_KEY_PATH=$(ask "Đường dẫn file SSH Private Key" "$HOME/.ssh/id_rsa")
      if [ ! -f "$SSH_KEY_PATH" ]; then
        warn "Không tìm thấy file: $SSH_KEY_PATH"
        continue
      fi
      info "Đang set $SECRET_NAME..."
      gh secret set "$SECRET_NAME" < "$SSH_KEY_PATH"
      ;;

    TRAEFIK_DASHBOARD_AUTH)
      TRAEFIK_MODE=$(ask_choice "Chọn cách nhập Traefik Auth" \
        "Tự sinh từ Username + Password" \
        "Nhập thủ công (htpasswd format)")

      if [[ "$TRAEFIK_MODE" == *"Tự sinh"* ]]; then
        TK_USER=$(ask "Username")
        [ -z "$TK_USER" ] && warn "Username trống, bỏ qua" && continue
        TK_PASS=$(ask "Password" "" "true")
        [ -z "$TK_PASS" ] && warn "Password trống, bỏ qua" && continue

        # Dùng htpasswd nếu có, fallback sang openssl apr1
        if command -v htpasswd >/dev/null 2>&1; then
          VALUE=$(htpasswd -nbB "$TK_USER" "$TK_PASS")
        else
          HASH=$(openssl passwd -apr1 "$TK_PASS")
          VALUE="${TK_USER}:${HASH}"
        fi

        info "Đã sinh: ${CYAN}${VALUE}${NC}"
      else
        VALUE=$(ask "Nhập htpasswd string (user:hash)")
        [ -z "$VALUE" ] && warn "Giá trị trống, bỏ qua" && continue
      fi

      info "Đang set $SECRET_NAME..."
      printf "%s" "$VALUE" | gh secret set "$SECRET_NAME"
      ;;

    CLOUDFLARE_ORIGIN_CERT|CLOUDFLARE_ORIGIN_KEY)
      printf "${BLUE}Paste nội dung certificate (Ctrl+D để kết thúc):${NC}\n" >&2
      VALUE=$(cat < /dev/tty)
      if [ -z "$VALUE" ]; then
        warn "Giá trị trống, bỏ qua"
        continue
      fi
      info "Đang set $SECRET_NAME..."
      printf "%s" "$VALUE" | gh secret set "$SECRET_NAME"
      ;;

    ENV_FILE_CONTENT)
      MODE=$(ask_choice "Nhập ENV như thế nào?" \
        "Paste trực tiếp" \
        "Đọc từ file .env" \
        "Chỉ cập nhật APP_NAME / APP_DOMAIN / HEALTH_CHECK_PATH / INIT_INFRA")

      if [[ "$MODE" == *"file"* ]]; then
        ENV_PATH=$(ask "Đường dẫn file .env" ".env")
        if [ ! -f "$ENV_PATH" ]; then
          warn "Không tìm thấy file: $ENV_PATH"
          continue
        fi
        BASE_ENV=$(cat "$ENV_PATH")
      elif [[ "$MODE" == *"Chỉ cập nhật"* ]]; then
        # Lấy ENV_FILE_CONTENT hiện tại từ GitHub
        info "Đang lấy ENV_FILE_CONTENT hiện tại từ GitHub..."
        BASE_ENV=$(gh secret list --json name | grep -q "ENV_FILE_CONTENT" && echo "" || echo "")
        BASE_ENV=""
        printf "${YELLOW}(Bỏ qua - sẽ chỉ ghi đè 4 trường bên dưới lên nội dung hiện tại)${NC}\n" >&2
      else
        printf "${BLUE}Paste nội dung .env (Ctrl+D để kết thúc):${NC}\n" >&2
        BASE_ENV=$(cat < /dev/tty)
      fi

      # Hỏi 4 trường resolved quan trọng
      printf "\n${YELLOW}>>> CẬP NHẬT CÁC TRƯỜNG RESOLVED:${NC}\n" >&2
      printf "${BLUE}(Nhấn Enter để giữ giá trị hiện tại trong .env, hoặc nhập mới để ghi đè)${NC}\n\n" >&2

      # Parse giá trị hiện tại từ BASE_ENV (|| true để tránh set -e kill khi grep không tìm thấy)
      CUR_APP_NAME=$(echo "$BASE_ENV" | grep "^APP_NAME=" | cut -d= -f2 || true)
      CUR_APP_DOMAIN=$(echo "$BASE_ENV" | grep "^APP_DOMAIN=" | cut -d= -f2 || true)
      CUR_HEALTH=$(echo "$BASE_ENV" | grep "^HEALTH_CHECK_PATH=" | cut -d= -f2- || true)
      CUR_INIT=$(echo "$BASE_ENV" | grep "^INIT_INFRA=" | cut -d= -f2 || true)
      CUR_PORT=$(echo "$BASE_ENV" | grep "^APP_PORT=" | cut -d= -f2 || true)
      CUR_DOMAIN=$(echo "$BASE_ENV" | grep "^DOMAIN=" | cut -d= -f2 || true)

      NEW_APP_NAME=$(ask "APP_NAME" "${CUR_APP_NAME:-}")
      NEW_APP_DOMAIN=$(ask "APP_DOMAIN" "${CUR_APP_DOMAIN:-}")
      NEW_HEALTH=$(ask "HEALTH_CHECK_PATH" "${CUR_HEALTH:-/}")
      NEW_INIT=$(ask "INIT_INFRA" "${CUR_INIT:-true}")
      NEW_PORT=$(ask "APP_PORT" "${CUR_PORT:-80}")
      NEW_DOMAIN=$(ask "DOMAIN" "${CUR_DOMAIN:-}")

      # Loại bỏ các key cũ, giữ lại phần còn lại (custom vars)
      EXTRA_ENVS=$(echo "$BASE_ENV" | grep -v "^APP_NAME=" | grep -v "^APP_DOMAIN=" \
        | grep -v "^HEALTH_CHECK_PATH=" | grep -v "^INIT_INFRA=" \
        | grep -v "^APP_PORT=" | grep -v "^DOMAIN=" | grep -v "^$")

      VALUE="APP_NAME=${NEW_APP_NAME}
APP_PORT=${NEW_PORT}
APP_DOMAIN=${NEW_APP_DOMAIN}
DOMAIN=${NEW_DOMAIN}
HEALTH_CHECK_PATH=${NEW_HEALTH}
INIT_INFRA=${NEW_INIT}
${EXTRA_ENVS}"

      printf "\n${BLUE}Preview ENV_FILE_CONTENT:${NC}\n" >&2
      printf "${CYAN}%s${NC}\n\n" "$VALUE" >&2

      if [ -z "$VALUE" ]; then
        warn "Giá trị trống, bỏ qua"
        continue
      fi
      info "Đang set $SECRET_NAME..."
      printf "%s" "$VALUE" | gh secret set "$SECRET_NAME"
      ;;

    TELEGRAM_BOT_TOKEN)
      VALUE=$(ask "$SECRET_NAME" "" "true")
      [ -z "$VALUE" ] && warn "Giá trị trống, bỏ qua" && continue
      info "Đang set $SECRET_NAME..."
      printf "%s" "$VALUE" | gh secret set "$SECRET_NAME"
      ;;

    *)
      VALUE=$(ask "$SECRET_NAME")
      [ -z "$VALUE" ] && warn "Giá trị trống, bỏ qua" && continue
      info "Đang set $SECRET_NAME..."
      printf "%s" "$VALUE" | gh secret set "$SECRET_NAME"
      ;;
  esac

  success "✓ $SECRET_NAME đã được cập nhật cho $REPO"
done

# ========================
# DONE
# ========================
echo ""
printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
success "Hoàn tất cập nhật secrets!"
echo "Repo: $REPO"
printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
