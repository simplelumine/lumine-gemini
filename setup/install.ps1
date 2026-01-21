# Check Requirements
if (-not (Get-Command "gh" -ErrorAction SilentlyContinue)) {
    Write-Error "GitHub CLI (gh) not found."
    exit 1
}
if (-not (gh auth status 2>&1 | Select-String "Logged in to")) {
    Write-Error "Not logged in to GitHub CLI."
    exit 1
}

$ScriptDir = Split-Path $MyInvocation.MyCommand.Path
$ConfigDir = Join-Path $ScriptDir "config"
$TemplatesDir = Join-Path $ScriptDir "templates"
$SettingsFile = Join-Path $ConfigDir "settings.json"
$EnvFile = Join-Path $ConfigDir ".env"
$TargetWorkflowDir = ".github/workflows"

# --- Functions ---

function Install-Workflows {
    Write-Host "`n[1] Installing Gemini Workflows & Prompts..." -ForegroundColor Cyan
    if (-not (Test-Path $TargetWorkflowDir)) { New-Item -ItemType Directory -Force -Path $TargetWorkflowDir | Out-Null }

    # Install YAML
    $TemplateFile = Join-Path $TemplatesDir "lumine-gemini.yml"
    $TargetFile = Join-Path $TargetWorkflowDir "lumine-gemini.yml"

    if (Test-Path $TargetFile) {
        $response = Read-Host "Workflow file exists. Overwrite? (y/N)"
        if ($response -match "^[Yy]$") {
            Copy-Item -Path $TemplateFile -Destination $TargetFile -Force
            Write-Host "Workflow updated." -ForegroundColor Green
        } else {
            Write-Host "Skipped workflow file." -ForegroundColor Gray
        }
    } else {
        Copy-Item -Path $TemplateFile -Destination $TargetFile -Force
        Write-Host "Workflow installed." -ForegroundColor Green
    }

    # Install TOML Commands
    $TargetCommandsDir = ".github/commands"
    if (-not (Test-Path $TargetCommandsDir)) { New-Item -ItemType Directory -Force -Path $TargetCommandsDir | Out-Null }
    Copy-Item -Path "$ScriptDir/../.github/commands/*" -Destination $TargetCommandsDir -Recurse -Force
    Write-Host "Prompts installed to $TargetCommandsDir." -ForegroundColor Green
}

function Configure-Vars-Secrets {
    Write-Host "`n[2] Configuring Variables & Secrets..." -ForegroundColor Cyan
    
    # Variables
    if (Test-Path $SettingsFile) {
        try {
            $settings = Get-Content $SettingsFile -Raw | ConvertFrom-Json
            foreach ($prop in $settings.PSObject.Properties) {
                Write-Host "Setting variable: $($prop.Name)"
                gh variable set $prop.Name --body $prop.Value
            }
        } catch {
            Write-Error "Failed to parse $SettingsFile. Please ensure it is valid JSON."
        }
    } else {
        Write-Warning "$SettingsFile not found."
    }

    # Secrets
    if (Test-Path $EnvFile) {
        $envContent = Get-Content $EnvFile
        $currentKey = $null; $currentValue = $null

        function Set-Secret {
            param($k, $v)
            if (-not [string]::IsNullOrWhiteSpace($k) -and -not [string]::IsNullOrWhiteSpace($v)) {
                if ($v.StartsWith('"') -and $v.EndsWith('"')) { $v = $v.Substring(1, $v.Length - 2) }
                $v = $v -replace '\\n', "`n"
                Write-Host "Setting secret from .env: $k"
                $v | gh secret set $k
            } elseif (-not [string]::IsNullOrWhiteSpace($k)) {
                Write-Warning "Secret '$k' is empty in .env. Skipping."
            }
        }

        foreach ($line in $envContent) {
            if ($line -match "^[A-Za-z_][A-Za-z0-9_]*=") {
                Set-Secret $currentKey $currentValue
                $parts = $line.Split("=", 2)
                $currentKey = $parts[0].Trim()
                $currentValue = $parts[1].Trim()
            } elseif ($currentKey) {
                $currentValue += "`n$line"
            }
        }
        Set-Secret $currentKey $currentValue
    } else {
        Write-Warning "$EnvFile not found."
    }
}

function Create-Labels {
    Write-Host "`n[3] Creating Standard Labels..." -ForegroundColor Cyan
    $Labels = @{
        "priority/p0" = @{ Color = "b60205"; Description = "Critical/Blocker - Catastrophic failure demanding immediate attention" }
        "priority/p1" = @{ Color = "d93f0b"; Description = "High - Serious issue significantly degrading UX or core feature" }
        "priority/p2" = @{ Color = "fbca04"; Description = "Medium - Moderately impactful, noticeable but non-blocking" }
        "priority/p3" = @{ Color = "0e8a16"; Description = "Low - Minor, trivial or cosmetic issue" }
        "kind/bug"    = @{ Color = "d73a4a"; Description = "Something isn't working" }
        "kind/enhancement" = @{ Color = "a2eeef"; Description = "New feature or request" }
        "kind/question"    = @{ Color = "d876e3"; Description = "Further information is requested" }
        "kind/documentation" = @{ Color = "0075ca"; Description = "Improvements or additions to documentation" }
    }

    foreach ($label in $Labels.Keys) {
        $props = $Labels[$label]
        Write-Host "Processing label: $label"
        gh label create $label --color $props.Color --description $props.Description 2>$null
        if ($LASTEXITCODE -ne 0) {
            gh label edit $label --color $props.Color --description $props.Description 2>$null
        }
    }
}

function Delete-Conflict-Labels {
    Write-Host "`n[4] Deleting Conflicting Default Labels..." -ForegroundColor Cyan
    $ConflictLabels = @("bug", "enhancement", "documentation", "question")
    
    foreach ($label in $ConflictLabels) {
        Write-Host "Deleting label: $label"
        gh label delete $label --yes 2>$null
    }
}

# --- Main Menu ---

while ($true) {
    Write-Host "`nGemini Workflow Setup" -ForegroundColor Yellow
    Write-Host "1. Install Workflows & Prompts"
    Write-Host "2. Configure Variables & Secrets"
    Write-Host "3. Create Standard Labels"
    Write-Host "4. Delete Conflicting Default Labels"
    Write-Host "5. Run All (Recommended for new repo)"
    Write-Host "0. Exit"
    
    $choice = Read-Host "Select an option"
    switch ($choice) {
        "1" { Install-Workflows }
        "2" { Configure-Vars-Secrets }
        "3" { Create-Labels }
        "4" { Delete-Conflict-Labels }
        "5" { 
            Install-Workflows
            Configure-Vars-Secrets
            Create-Labels
            Delete-Conflict-Labels
        }
        "0" { exit }
        default { Write-Host "Invalid option." -ForegroundColor Red }
    }
    Write-Host "`nDone." -ForegroundColor Green
}
Write-Host "gh label list"
