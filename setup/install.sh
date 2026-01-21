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

# 3. Create Priority and Kind Labels
# [ADDED] Create labels required for triage workflow
echo -e "\n\033[0;36mCreating Priority and Kind Labels...\033[0m"

declare -A LABELS=(
    # Priority labels
    ["priority/p0"]="#b60205:Critical/Blocker - Catastrophic failure demanding immediate attention"
    ["priority/p1"]="#d93f0b:High - Serious issue significantly degrading UX or core feature"
    ["priority/p2"]="#fbca04:Medium - Moderately impactful, noticeable but non-blocking"
    ["priority/p3"]="#0e8a16:Low - Minor, trivial or cosmetic issue"
    # Kind labels
    ["kind/bug"]="#d73a4a:Something isn't working"
    ["kind/enhancement"]="#a2eeef:New feature or request"
    ["kind/question"]="#d876e3:Further information is requested"
)

for label in "${!LABELS[@]}"; do
    IFS=':' read -r color description <<< "${LABELS[$label]}"
    echo "Creating label: $label"
    gh label create "$label" --color "${color#\#}" --description "$description" 2>/dev/null || \
        gh label edit "$label" --color "${color#\#}" --description "$description" 2>/dev/null || \
        echo "  Label '$label' already exists and couldn't be updated (skipped)"
done

echo -e "\n\033[0;32mSetup complete! Workflow installed and config applied.\033[0m"
echo "gh variable list"
echo "gh secret list"
echo "gh label list"
