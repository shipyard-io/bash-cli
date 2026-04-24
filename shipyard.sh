#!/bin/bash

# Giao diện màu sắc
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Hàm in thông báo
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

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

# 1. Kiểm tra GitHub CLI
if ! command -v gh &> /dev/null; then
    error "GitHub CLI (gh) chưa được cài đặt. Vui lòng cài đặt tại: https://cli.github.com/"
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
read -p "Nhập địa chỉ IP Server: " SERVER_IP
read -p "Nhập SSH User (mặc định: root): " SERVER_USER
SERVER_USER=${SERVER_USER:-root}
read -p "Đường dẫn tới file SSH Private Key (mặc định: ~/.ssh/id_rsa): " SSH_KEY_PATH
SSH_KEY_PATH=${SSH_KEY_PATH:-$HOME/.ssh/id_rsa}

if [ ! -f "$SSH_KEY_PATH" ]; then
    error "Không tìm thấy file SSH key tại $SSH_KEY_PATH"
fi

# Kiểm tra SSH
info "Đang kiểm tra kết nối SSH tới $SERVER_IP..."
if ssh -i "$SSH_KEY_PATH" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${SERVER_USER}@${SERVER_IP}" "exit" &> /dev/null; then
    success "Kết nối SSH thành công!"
else
    error "Không thể kết nối SSH. Vui lòng kiểm tra lại IP, User hoặc Key."
fi

echo ""
echo -e "${YELLOW}>>> BƯỚC 2: THÔNG BÁO TELEGRAM${NC}"
read -p "Nhập Telegram Bot Token: " TELEGRAM_BOT_TOKEN
read -p "Nhập Telegram Chat ID: " TELEGRAM_CHAT_ID

echo ""
echo -e "${YELLOW}>>> BƯỚC 3: CẤU HÌNH ỨNG DỤNG${NC}"
read -p "Nhập tên ứng dụng (APP_NAME): " APP_NAME
read -p "Nhập tên miền (APP_DOMAIN): " APP_DOMAIN
read -p "Nhập cổng ứng dụng (APP_PORT - mặc định: 80): " APP_PORT
APP_PORT=${APP_PORT:-80}
read -p "Đường dẫn Health Check (mặc định: /): " HEALTH_CHECK_PATH
HEALTH_CHECK_PATH=${HEALTH_CHECK_PATH:-/}

# Kiểm tra DNS
if [ -n "$APP_DOMAIN" ]; then
    info "Đang kiểm tra DNS cho $APP_DOMAIN..."
    DOMAIN_IP=$(dig +short "$APP_DOMAIN" | tail -n1)
    if [ "$DOMAIN_IP" == "$SERVER_IP" ]; then
        success "Domain $APP_DOMAIN đã trỏ đúng về $SERVER_IP"
    else
        warn "Domain $APP_DOMAIN đang trỏ về IP ($DOMAIN_IP). Vui lòng cập nhật DNS về $SERVER_IP sớm."
    fi
fi

# 4. Thu thập biến môi trường tùy chỉnh (Custom ENV)
echo ""
echo -e "${YELLOW}>>> BƯỚC 4: BIẾN MÔI TRƯỜNG TÙY CHỈNH (Optional)${NC}"
echo -e "Nhập các biến môi trường khác (ví dụ: DB_PASSWORD=secret). Nhấn Enter trống để kết thúc."
CUSTOM_ENVS=""
while true; do
    read -p "Nhập biến (KEY=VALUE): " ENV_ENTRY
    if [ -z "$ENV_ENTRY" ]; then
        break
    fi
    CUSTOM_ENVS="${CUSTOM_ENVS}${ENV_ENTRY}"$'\n'
done

# 3. Tạo ENV_FILE_CONTENT
ENV_CONTENT="APP_NAME=$APP_NAME
APP_PORT=$APP_PORT
APP_DOMAIN=$APP_DOMAIN
HEALTH_CHECK_PATH=$HEALTH_CHECK_PATH
INIT_INFRA=true
$CUSTOM_ENVS"

echo ""
echo -e "${YELLOW}>>> BƯỚC 5: CÀI ĐẶT GITHUB SECRETS TỰ ĐỘNG${NC}"
info "Đang thiết lập toàn bộ Secrets cho repo: ${CYAN}$REPO${NC}"

SSH_KEY_DATA=$(cat "$SSH_KEY_PATH")

# Đẩy tất cả các secret một cách đồng loạt
(
  echo "SERVER_IP=$SERVER_IP"
  echo "SERVER_USER=$SERVER_USER"
  echo "SSH_PRIVATE_KEY=$SSH_KEY_DATA"
  echo "ENV_FILE_CONTENT=$ENV_CONTENT"
  echo "TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN"
  echo "TELEGRAM_CHAT_ID=$TELEGRAM_CHAT_ID"
) | while IFS='=' read -r key value; do
    info "Đang cài đặt Secret: ${CYAN}$key${NC}..."
    echo "$value" | gh secret set "$key"
done

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
