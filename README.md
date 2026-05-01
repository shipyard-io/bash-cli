# Shipyard Go CLI

CLI tương tác để bootstrap dự án Shipyard và quản lý GitHub Secrets.

## Lệnh

- `setup`: thay cho `shipyard.sh`, cấu hình ban đầu + set secrets.
- `secrets`: thay cho `shipyard_secret.sh`, cập nhật secrets tương tác.

## Cài 1 lệnh (khuyến nghị)

Chạy trực tiếp như package:

```bash
curl -fsSL https://raw.githubusercontent.com/shipyard-io/templates/main/bash-cli/install.sh | bash
```

Chạy luôn command sau khi cài:

```bash
curl -fsSL https://raw.githubusercontent.com/shipyard-io/templates/main/bash-cli/install.sh | bash -s -- setup
curl -fsSL https://raw.githubusercontent.com/shipyard-io/templates/main/bash-cli/install.sh | bash -s -- secrets
```

Script sẽ:
- Tự detect OS/ARCH
- Tải binary prebuilt từ GitHub Releases nếu có
- Nếu chưa có release phù hợp thì fallback build từ source (cần `go`)
- Cài vào `~/.local/bin/shipyard` (override bằng `SHIPYARD_INSTALL_DIR`)

## Yêu cầu

1. Cài và login GitHub CLI (`gh auth login`)
2. Có quyền SSH vào VPS
3. Nếu không có prebuilt binary cho platform của bạn: cần thêm Go + Git để fallback build

## Chạy nhanh

```bash
cd bash-cli
go build -o shipyard ./cmd/shipyard
./shipyard setup
./shipyard secrets
```

## Flags mới

```bash
./shipyard setup --repo owner/repo
./shipyard setup --non-interactive --repo owner/repo --env-file .env

./shipyard secrets --repo owner/repo
./shipyard secrets --non-interactive --repo owner/repo --secret ENV_FILE_CONTENT --value-file .env
```

## Non-interactive Setup

Biến môi trường hỗ trợ:

- `SHIPYARD_SERVER_IP` (required)
- `SHIPYARD_APP_NAME` (required)
- `SHIPYARD_SERVER_USER` (default `root`)
- `SHIPYARD_SSH_KEY_PATH` (default `~/.ssh/id_rsa`)
- `SHIPYARD_APP_PORT` (default `80`)
- `SHIPYARD_HEALTH_CHECK_PATH` (default `/`)
- `SHIPYARD_APP_DOMAIN`
- `SHIPYARD_DOMAIN`
- `SHIPYARD_CUSTOM_ENVS` (nhiều dòng `KEY=VALUE`)
- `SHIPYARD_TELEGRAM_BOT_TOKEN`
- `SHIPYARD_TELEGRAM_CHAT_ID`
- `SHIPYARD_CLOUDFLARE_ORIGIN_CERT`
- `SHIPYARD_CLOUDFLARE_ORIGIN_KEY`
- `SHIPYARD_TRAEFIK_DASHBOARD_AUTH`

Ví dụ:

```bash
SHIPYARD_SERVER_IP=1.2.3.4 \
SHIPYARD_APP_NAME=myapp \
SHIPYARD_SERVER_USER=ubuntu \
SHIPYARD_SSH_KEY_PATH=$HOME/.ssh/id_rsa \
SHIPYARD_APP_PORT=3000 \
SHIPYARD_HEALTH_CHECK_PATH=/health \
./shipyard setup --non-interactive --repo your-org/your-repo --env-file .env
```

## Non-interactive Secrets

```bash
./shipyard secrets --non-interactive --repo your-org/your-repo --secret SERVER_IP --value 1.2.3.4
./shipyard secrets --non-interactive --repo your-org/your-repo --secret SSH_PRIVATE_KEY --value-file ~/.ssh/id_rsa
```

## Tương thích lệnh cũ

Bạn vẫn có thể chạy:

```bash
./shipyard.sh
./shipyard_secret.sh
```

Hai script này giờ chỉ là wrapper mỏng gọi binary Go.

## Ghi chú nhập multiline

Với các trường dạng paste nhiều dòng (`.env`, certificate...), nhập xong dùng một dòng `END` để kết thúc.
