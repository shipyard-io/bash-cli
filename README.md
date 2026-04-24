# Shipyard Bash CLI

An interactive CLI to bootstrap your Shipyard-based projects.

## Features
- **Validation**: Checks SSH connectivity and DNS resolution before setting up.
- **Automation**: Uses GitHub CLI to automatically set all necessary secrets.
- **Simplicity**: No complex configuration files needed. Just run and follow the prompts.

## Prerequisites
1. [GitHub CLI (gh)](https://cli.github.com/) installed and authenticated (`gh auth login`).
2. SSH access to your target VPS.

## Usage
1. Clone your project repository.
2. Run the Shipyard setup script:
   ```bash
   curl -sSL https://raw.githubusercontent.com/shipyard-io/bash-cli/main/shipyard.sh | bash
   ```
   *Note: Or run it locally if you have the file.*

3. Follow the interactive prompts to:
   - Provide Server IP and SSH Key.
   - Configure App Name, Port, and Domain.
   - Automatically sync everything to GitHub Secrets.

4. Push your code and watch the deployment!
