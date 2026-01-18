# Gemini Lumine Workflows

This repository hosts reusable GitHub Actions workflows for Gemini-powered issue triage and management. It also provides a "distribution" setup to easily install these workflows into other repositories.

## Installation

You can install the Gemini workflows into any repository (e.g., `k8s-gitops`) using the provided setup scripts. This will:

1.  Install the standard `.github/workflows/gemini.yml` caller workflow.
2.  Configure necessary GitHub Variables (APP_ID, etc.).
3.  Configure necessary GitHub Secrets (API Keys) from your local configuration.

### Prerequisites

1.  **Configure Secrets (One-time):**
    Ensure you have configured your secrets in this repository:
    Edit `setup/config/.env` and add your keys:
    ```env
    APP_PRIVATE_KEY=...
    GEMINI_API_KEY=...
    ```

### Run the Installer

Run the installer script **from the directory of the target repository** (the one you want to install gemini into).

#### Windows (PowerShell)

Open your terminal in the target repo (e.g., `k8s-gitops`) and run:

```powershell
..\gemini-lumine\setup\install.ps1
```

#### Linux / macOS

Open your terminal in the target repo and run:

```bash
../gemini-lumine/setup/install.sh
```

## Features

- **Automatic Triage**: Automatically labels new issues based on their content.
- **Scheduled Triage**: Periodically scans for untriaged issues.
- **Dispatch Support**: Can be triggered manually or via other events.
