#!/bin/bash
set -e

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed. Please install it and run 'gh auth login' before running this script."
    exit 1
fi

# Check authentication
if ! gh auth status &> /dev/null; then
    echo "Error: You are not logged in to GitHub CLI. Please run 'gh auth login'."
    exit 1
fi

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Please install jq."
    exit 1
fi

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
CONFIG_DIR="${SCRIPT_DIR}/config"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"
SETTINGS_FILE="${CONFIG_DIR}/settings.json"
ENV_FILE="${CONFIG_DIR}/.env"
TARGET_WORKFLOW_DIR=".github/workflows"

echo -e "\033[0;36mInstalling Gemini Workflow...\033[0m"

# 1. Install Workflow Template
mkdir -p "$TARGET_WORKFLOW_DIR"

TEMPLATE_FILE="${TEMPLATES_DIR}/lumine-gemini.yml"
TARGET_FILE="${TARGET_WORKFLOW_DIR}/lumine-gemini.yml"

if [ -f "$TARGET_FILE" ]; then
    echo "Warning: Workflow file already exists at $TARGET_FILE."
    read -p "Do you want to overwrite it? (y/N) " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        cp "$TEMPLATE_FILE" "$TARGET_FILE"
        echo -e "\033[0;32mWorkflow updated.\033[0m"
    else
        echo "Skipping workflow installation."
    fi
else
    cp "$TEMPLATE_FILE" "$TARGET_FILE"
    echo -e "\033[0;32mWorkflow installed to $TARGET_FILE.\033[0m"
fi

# 2. Inject Configuration
echo -e "\n\033[0;36mSetting up GitHub Variables...\033[0m"

# Load Settings
if [ -f "$SETTINGS_FILE" ]; then
    jq -r 'to_entries | .[] | "\(.key)=\(.value)"' "$SETTINGS_FILE" | while IFS='=' read -r key value; do
        echo "Setting variable: $key"
        gh variable set "$key" --body "$value"
    done
else
    echo "Warning: Settings file not found at $SETTINGS_FILE"
fi

echo -e "\n\033[0;36mSetting up GitHub Secrets...\033[0m"

# Load Secrets from .env with Multi-line Support
if [ -f "$ENV_FILE" ]; then
    current_key=""
    current_value=""

    set_secret() {
        local key="$1"
        local val="$2"
        if [ -n "$key" ] && [ -n "$val" ]; then
            # Remove surrounding quotes
            val="${val%\"}"
            val="${val#\"}"
            # Unescape \n
            val="${val//\\n/$'\n'}"
            
            echo "Setting secret from .env: $key"
            echo "$val" | gh secret set "$key"
        elif [ -n "$key" ]; then
             echo "Warning: Secret '$key' is empty in .env. Skipping."
        fi
    }

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Check for new key (Start of line, Key=Value)
        if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
            # Flush previous
            set_secret "$current_key" "$current_value"

            current_key="${line%%=*}"
            current_value="${line#*=}"
        elif [ -n "$current_key" ]; then
            # Append to current value (assuming multi-line)
            current_value="${current_value}"$'\n'"${line}"
        fi
    done < "$ENV_FILE"
    
    # Flush final
    set_secret "$current_key" "$current_value"
else
    echo "Warning: .env file not found at $ENV_FILE"
fi

echo -e "\n\033[0;32mSetup complete! Workflow installed and config applied.\033[0m"
echo "gh variable list"
echo "gh secret list"
