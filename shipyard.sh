#!/bin/bash

# Giao diện màu sắc
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Hàm in thông báo
info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
success() { printf "${GREEN}[SUCCESS]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*"; exit 1; }

# Hàm hỏi thông tin (Premium UI)
ask() {
    local prompt="$1"
    local default="$2"
    local is_secret="$3"
    local value

    printf "${CYAN}➜ %s${NC}" "$prompt" >&2
    if [ -n "$default" ]; then
        printf " (mặc định: ${YELLOW}%s${NC})" "$default" >&2
    fi
    printf ": " >&2

    if [ "$is_secret" = "true" ]; then
        stty -echo
        read -r value < /dev/tty
        stty echo
        printf "\n" >&2
    else
        read -r value < /dev/tty
    fi

    echo "${value:-$default}"
}

# Hàm chọn lựa (Sử dụng fzf nếu có)
ask_choice() {
    local prompt="$1"
    shift
    local options=("$@")
    local choice

    if command -v fzf &> /dev/null; then
        choice=$(printf "%s\n" "${options[@]}" | fzf --height 5 --reverse --header "➜ $prompt" --border rounded)
    fi

    if [ -z "$choice" ]; then
        # Fallback nếu không có fzf hoặc user hủy
        printf "${CYAN}➜ %s${NC}\n" "$prompt" >&2
        local i=1
        for opt in "${options[@]}"; do
            printf "  %d) %s\n" "$i" "$opt" >&2
            i=$((i+1))
        done
        local idx
        printf "Lựa chọn của bạn (1-%d): " "$((i-1))" >&2
        read -r idx < /dev/tty
        choice="${options[$((idx-1))]}"
    fi
    echo "$choice"
}

echo -e "${CYAN}"
echo "  ____  _     _                           _ "
echo " / ___|| |__ (_)_ __  _   _  __ _ _ __ __| |"
echo " \___ \| '_ \| | '_ \| | | |/ _\` | '__/ _\` |"
echo "  ___) | | | | | |_) | |_| | (_| | | | (_| |"
echo " |____/|_| |_|_| .__/ \__, |\__,_|_|  \__,_|"
echo "               |_|    |___/                 "
echo -e "${NC}"
echo -e "--- Shipyard Zero-Touch Setup CLI ---"
echo ""

# 1. Kiểm tra Tools
if ! command -v gh &> /dev/null; then
    error "GitHub CLI (gh) chưa được cài đặt. Vui lòng cài đặt tại: https://cli.github.com/"
fi

HAS_DIG=false
if command -v dig &> /dev/null; then
    HAS_DIG=true
fi

if ! gh auth status &> /dev/null; then
    error "Bạn chưa đăng nhập GitHub CLI. Vui lòng chạy: gh auth login"
fi

# Lấy thông tin Repo hiện tại
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
if [ -z "$REPO" ]; then
    error "Không tìm thấy thông tin repository. Vui lòng đảm bảo bạn đang ở trong thư mục git đã được push lên GitHub."
fi

# 2. Thu thập thông tin
echo -e "${YELLOW}>>> BƯỚC 1: THÔNG TIN SERVER${NC}"
SERVER_IP=$(ask "Địa chỉ IP Server (SERVER_IP)")
while [ -z "$SERVER_IP" ]; do
    warn "SERVER_IP không được để trống"
    SERVER_IP=$(ask "Địa chỉ IP Server (SERVER_IP)")
done

SERVER_USER=$(ask "SSH User" "root")

SSH_KEY_INPUT=$(ask "Đường dẫn SSH Private Key" "$HOME/.ssh/id_rsa")
SSH_KEY_PATH=$SSH_KEY_INPUT

# Kiểm tra file key sau khi đã có input
if [ ! -f "$SSH_KEY_PATH" ]; then
    error "Không tìm thấy file SSH key tại: $SSH_KEY_PATH"
fi
chmod 600 "$SSH_KEY_PATH" 2>/dev/null

# Kiểm tra SSH
info "Đang kiểm tra kết nối SSH tới $SERVER_IP..."
if ssh -i "$SSH_KEY_PATH" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${SERVER_USER}@${SERVER_IP}" "exit" &> /dev/null; then
    success "Kết nối SSH thành công!"
else
    error "Không thể kết nối SSH. Vui lòng kiểm tra lại IP, User hoặc Key."
fi

echo ""
echo -e "${YELLOW}>>> BƯỚC 2: THÔNG BÁO TELEGRAM (Optional)${NC}"
TELEGRAM_BOT_TOKEN=$(ask "Telegram Bot Token" "" "true")
TELEGRAM_CHAT_ID=$(ask "Telegram Chat ID")

echo ""
echo -e "${YELLOW}>>> BƯỚC 3: CẤU HÌNH ỨNG DỤNG${NC}"
while [ -z "$APP_NAME" ]; do
    APP_NAME=$(ask "Tên ứng dụng (APP_NAME - bắt buộc)")
done
APP_DOMAIN=$(ask "Tên miền Production (APP_DOMAIN)")
DOMAIN=$(ask "Tên miền cơ sở (DOMAIN)")
APP_PORT=$(ask "Cổng ứng dụng (APP_PORT)" "80")
HEALTH_CHECK_PATH=$(ask "Đường dẫn Health Check" "/")

# Kiểm tra DNS cho APP_DOMAIN
if [ -n "$APP_DOMAIN" ] && [ "$HAS_DIG" = true ]; then
    info "Đang kiểm tra DNS cho $APP_DOMAIN..."
    DOMAIN_IP=$(dig +short "$APP_DOMAIN" | tail -n1)
    if [ -n "$DOMAIN_IP" ]; then
        if [ "$DOMAIN_IP" == "$SERVER_IP" ]; then
            success "Domain $APP_DOMAIN đã trỏ đúng về $SERVER_IP"
        else
            warn "Domain $APP_DOMAIN đang trỏ về IP ($DOMAIN_IP). Vui lòng cập nhật DNS về $SERVER_IP sớm."
        fi
    else
        warn "Không thể tìm thấy bản ghi DNS cho $APP_DOMAIN."
    fi
elif [ -n "$APP_DOMAIN" ]; then
    warn "Bỏ qua kiểm tra DNS vì không tìm thấy lệnh 'dig'."
fi

# 4. Thu thập biến môi trường tùy chỉnh (Custom ENV)
echo ""
echo -e "${YELLOW}>>> BƯỚC 4: BIẾN MÔI TRƯỜNG TÙY CHỈNH (Optional)${NC}"
ENV_MODE=$(ask_choice "Bạn muốn nhập biến môi trường như thế nào?" "Nhập từng dòng (Key=Value)" "Dán nguyên khối (Bulk Paste từ file .env)")

CUSTOM_ENVS=""
if [[ "$ENV_MODE" == *"Bulk Paste"* ]] || [ "$ENV_MODE" == "2" ]; then
    echo -e "${BLUE}Hãy dán nội dung .env của bạn vào đây.${NC}"
    echo -e "${YELLOW}(Dán xong nhấn Ctrl+D để kết thúc)${NC}"
    CUSTOM_ENVS=$(cat < /dev/tty)
else
    echo -e "Nhập các biến môi trường (ví dụ: DB_PASSWORD=secret). Nhấn Enter trống để kết thúc."
    while true; do
        ENV_ENTRY=$(ask "Nhập biến (KEY=VALUE)")
        if [ -z "$ENV_ENTRY" ]; then
            break
        fi
        CUSTOM_ENVS="${CUSTOM_ENVS}${ENV_ENTRY}"$'\n'
    done
fi

# 5. Tạo nội dung file ENV (Sẽ được lưu vào ENV_FILE_CONTENT)
ENV_CONTENT="APP_NAME=$APP_NAME
APP_PORT=$APP_PORT
APP_DOMAIN=$APP_DOMAIN
DOMAIN=$DOMAIN
HEALTH_CHECK_PATH=$HEALTH_CHECK_PATH
INIT_INFRA=true
$CUSTOM_ENVS"

echo ""
echo -e "${YELLOW}>>> BƯỚC 5: CÀI ĐẶT GITHUB SECRETS TỰ ĐỘNG${NC}"
info "Đang thiết lập toàn bộ Secrets cho repo: ${CYAN}$REPO${NC}"


# Đẩy từng Secret lên GitHub
info "Cài đặt SERVER_IP..."
printf "%s" "$SERVER_IP" | gh secret set SERVER_IP
info "Cài đặt SERVER_USER..."
printf "%s" "$SERVER_USER" | gh secret set SERVER_USER
info "Cài đặt SSH_PRIVATE_KEY..."
gh secret set SSH_PRIVATE_KEY < "$SSH_KEY_PATH"
if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
    info "Cài đặt TELEGRAM_BOT_TOKEN..."
    printf "%s" "$TELEGRAM_BOT_TOKEN" | gh secret set TELEGRAM_BOT_TOKEN
fi
if [ -n "$TELEGRAM_CHAT_ID" ]; then
    info "Cài đặt TELEGRAM_CHAT_ID..."
    printf "%s" "$TELEGRAM_CHAT_ID" | gh secret set TELEGRAM_CHAT_ID
fi
info "Cài đặt ENV_FILE_CONTENT..."
printf "%s" "$ENV_CONTENT" | gh secret set ENV_FILE_CONTENT

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
success "CẤU HÌNH HOÀN TẤT!"
echo -e "Dự án:        ${CYAN}$REPO${NC}"
echo -e "Ứng dụng:     ${CYAN}$APP_NAME${NC}"
echo -e "Trạng thái:   ${GREEN}Sẵn sàng Deploy${NC}"
echo -e ""
echo -e "Bây giờ bạn chỉ cần chạy lệnh sau để deploy:"
echo -e "${YELLOW}git add . && git commit -m 'initial setup' && git push origin main${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
