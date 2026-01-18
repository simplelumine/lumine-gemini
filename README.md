# Lumine Gemini Workflows

**Lumine Gemini** automates code reviews, issue triage, and bug fixing. It functions as a "Workflow Distribution", allowing you to bootstrap AI capabilities into any repository with a single command.

## Features

- **🤖 Automated Triage**: Automatically categorizes and labels new issues.
- **🧐 AI Code Review**: Reviews Pull Requests on open, synchronize (`push`), and reopen events.
- **💬 ChatOps**: Interact with the bot using comments (e.g., `@gemini /fix`).
- **📦 Zero-Config Distribution**: Install into any repo with a one-line setup script.

## ChatOps Commands

You can trigger Gemini manually by commenting on Issues or Pull Requests:

| Command            | Description                                                  |
| :----------------- | :----------------------------------------------------------- |
| `@gemini /review`  | Trigger a full code review for the current PR.               |
| `@gemini /fix`     | Ask Gemini to fix the issue or PR based on context.          |
| `@gemini /triage`  | Re-run triage analysis on the current issue.                 |
| `@gemini <prompt>` | Ask Gemini any question (e.g. `@gemini explain this logic`). |

## Installation

To install Gemini Workflows into a consumer repository (e.g., `k8s-gitops`):

### 1. Prerequisites (One-time)

Ensure you have configured your secrets in **this** repository (`lumine-gemini`) at `setup/config/.env`:

```env
APP_PRIVATE_KEY=-----BEGIN RSA PRIVATE KEY-----...
GEMINI_API_KEY=...
```

### 2. Run Installer

Open your terminal in the **target repository** and run the install script:

**Windows (PowerShell):**

```powershell
..\lumine-gemini\setup\install.ps1
```

**Linux / macOS:**

```bash
../lumine-gemini/setup/install.sh
```

This will automatically:

- Install `.github/workflows/gemini.yml`.
- Set all required GitHub Variables and Secrets.
