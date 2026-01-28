#!/bin/bash
set -e

# Checks
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed."
    exit 1
fi
if ! gh auth status &> /dev/null; then
    echo "Error: You are not logged in to GitHub CLI."
    exit 1
fi
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed."
    exit 1
fi

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
CONFIG_DIR="${SCRIPT_DIR}/config"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"
SETTINGS_FILE="${CONFIG_DIR}/settings.json"
ENV_FILE="${CONFIG_DIR}/.env"
TARGET_WORKFLOW_DIR=".github/workflows"

# --- Functions ---

install_workflows() {
    echo -e "\n\033[0;36m[*] Installing Workflows Only...\033[0m"
    mkdir -p "$TARGET_WORKFLOW_DIR"

    # Install YAML
    TEMPLATE_FILE="${TEMPLATES_DIR}/lumine-gemini.yml"
    TARGET_FILE="${TARGET_WORKFLOW_DIR}/lumine-gemini.yml"
    
    if [ -f "$TARGET_FILE" ]; then
        read -p "Workflow file exists. Overwrite? (y/N) " response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            cp "$TEMPLATE_FILE" "$TARGET_FILE"
            echo "Workflow updated."
        else
            echo "Skipped workflow file."
        fi
    else
        cp "$TEMPLATE_FILE" "$TARGET_FILE"
        echo "Workflow installed."
    fi



configure_vars_secrets() {
    echo -e "\n\033[0;36m[2] Configuring Variables & Secrets...\033[0m"
    
    # Variables
    if [ -f "$SETTINGS_FILE" ]; then
        jq -r 'to_entries | .[] | "\(.key)=\(.value)"' "$SETTINGS_FILE" | while IFS='=' read -r key value; do
            echo "Setting variable: $key"
            gh variable set "$key" --body "$value"
        done
    else
        echo "Warning: $SETTINGS_FILE not found."
    fi

    # Secrets
    if [ -f "$ENV_FILE" ]; then
        current_key=""
        current_value=""
        set_secret() {
            local key="$1"
            local val="$2"
            if [ -n "$key" ] && [ -n "$val" ]; then
                val="${val%\"}"
                val="${val#\"}"
                val="${val//\\n/$'\n'}"
                echo "Setting secret: $key"
                echo "$val" | gh secret set "$key"
            fi
        }

        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
                set_secret "$current_key" "$current_value"
                current_key="${line%%=*}"
                current_value="${line#*=}"
            elif [ -n "$current_key" ]; then
                current_value="${current_value}"$'\n'"${line}"
            fi
        done < "$ENV_FILE"
        set_secret "$current_key" "$current_value"
    else
        echo "Warning: $ENV_FILE not found."
    fi
}

create_labels() {
    echo -e "\n\033[0;36m[3] Creating Standard Labels (Priority & Kind)...\033[0m"
    declare -A LABELS=(
        # Priority
        ["priority/p0"]="#b60205:Critical/Blocker - Catastrophic failure demanding immediate attention"
        ["priority/p1"]="#d93f0b:High - Serious issue significantly degrading UX or core feature"
        ["priority/p2"]="#fbca04:Medium - Moderately impactful, noticeable but non-blocking"
        ["priority/p3"]="#0e8a16:Low - Minor, trivial or cosmetic issue"

        ["status/gemini-triaged"]="#6f42c1:Issue has been successfully analyzed and classified by Gemini"
        ["status/needs-triage"]="#db2869:Issue needs to be triaged by AI or maintainers"

        # Kind - User Defined
        ["kind/discussion"]="#7057ff:Discussion regarding architecture or design decisions"
        ["kind/security"]="#FF4500:Security vulnerability or critical safety issue"
        ["kind/cleanup"]="#FFFFFF:Code cleanup, dead code removal, and maintenance"
        ["kind/bug"]="#FF0055:Something isn't working"
        ["kind/feature"]="#00E0FF:New feature or request"
        ["kind/perf"]="#CCFF00:Code change that improves performance"
        ["kind/refactor"]="#9D00FF:Code change that neither fixes a bug nor adds a feature"
        ["kind/test"]="#00FF9D:Adding missing tests or correcting existing tests"
        ["kind/docs"]="#F4D03F:Improvements or additions to documentation"
        ["kind/chore"]="#BFC9CA:Build process, auxiliary tool changes, etc."
    )

    for label in "${!LABELS[@]}"; do
        IFS=':' read -r color description <<< "${LABELS[$label]}"
        echo "Processing label: $label"
        gh label create "$label" --color "${color#\#}" --description "$description" 2>/dev/null || \
        gh label edit "$label" --color "${color#\#}" --description "$description" 2>/dev/null || true
    done
}

delete_conflict_labels() {
    echo -e "\n\033[0;36m[4] Deleting Conflicting Default Labels...\033[0m"
    # Only remove labels that conflict with our new kind/* schema
    CONFLICT_LABELS=("bug" "enhancement" "documentation" "question" "duplicate" "wontfix" "invalid")
    
    for label in "${CONFLICT_LABELS[@]}"; do
        echo "Deleting label: $label"
        gh label delete "$label" --yes 2>/dev/null || echo "  Label '$label' not found or already deleted."
    done
}

# --- Main Menu ---

show_menu() {
    echo -e "\n\033[1;33mGemini Workflow Setup\033[0m"
    echo "1. Install Workflows & Prompts"
    echo "2. Configure Variables & Secrets"
    echo "3. Create Standard Labels"
    echo "4. Delete Conflicting Default Labels"
    echo "5. Run All (Recommended for new repo)"
    echo "0. Exit"
}

while true; do
    echo -e "\n\033[1;33mGemini Workflow Setup\033[0m"
    echo "1. Run All (Recommended for new repo)"
    echo "2. Install Workflows Only"
    echo "3. Configure Variables & Secrets"
    echo "4. Create Standard Labels"
    echo "5. Delete Conflicting Default Labels"
    echo "0. Exit"
    read -p "Select an option: " choice
    case $choice in
        1) 
            install_workflows
            configure_vars_secrets
            create_labels
            delete_conflict_labels
            ;;
        2) install_workflows ;;
        3) configure_vars_secrets ;;
        4) create_labels ;;
        5) delete_conflict_labels ;;
        0) exit 0 ;;
        *) echo "Invalid option." ;;
    esac
    echo -e "\n\033[0;32mDone.\033[0m"
done
