# Shipyard Bash CLI

An interactive CLI to bootstrap your Shipyard-based projects and automate GitHub Secrets configuration.

## Features
- **Zero Config**: Automates the creation of all required GitHub Secrets.
- **Validation**: Checks SSH connectivity and DNS resolution before setting up.
- **Notification Setup**: Configures Telegram bots for deployment alerts.
- **Automation**: Uses GitHub CLI to automatically sync infrastructure and application settings.

## Prerequisites
1. [GitHub CLI (gh)](https://cli.github.com/) installed and authenticated (`gh auth login`).
2. SSH access to your target VPS.
3. You should be inside the root directory of your project repository.

## Usage
Run the following command in your terminal:

```bash
curl -sSL https://raw.githubusercontent.com/shipyard-io/bash-cli/main/shipyard.sh | bash
```

## 🔐 Secrets Managed
The script will interactively ask for information and set the following **GitHub Secrets**:

### 🏗️ Infrastructure Secrets
- `SERVER_IP`: The public IP of your VPS.
- `SERVER_USER`: SSH username (defaults to `root`).
- `SSH_PRIVATE_KEY`: Your private key content for secure access.

### 📢 Notification Secrets
- `TELEGRAM_BOT_TOKEN`: Your Telegram Bot API token.
- `TELEGRAM_CHAT_ID`: The ID of the chat where notifications will be sent.

### 📝 Application Secret (`ENV_FILE_CONTENT`)
This secret consolidates app settings into a single block:
- `APP_NAME`: Your application's identifier.
- `APP_PORT`: Internal port the app listens on (default: `80`).
- `APP_DOMAIN`: Your production domain.
- `HEALTH_CHECK_PATH`: Path for deployment health checks (default: `/`).
- `INIT_INFRA`: Automatically set to `true` to ensure the first deployment sets up Docker/Traefik.

## Next Steps
After running the script, simply push your code:
```bash
git add .
git commit -m "chore: initial shipyard setup"
git push origin main
```
The Shipyard pipeline will take over from there!
