# Check if gh CLI is installed
if (-not (Get-Command "gh" -ErrorAction SilentlyContinue)) {
    Write-Error "GitHub CLI (gh) is not installed. Please install it and run 'gh auth login' before running this script."
    exit 1
}

# Check authentication
if (-not (gh auth status 2>&1 | Select-String "Logged in to")) {
    Write-Error "You are not logged in to GitHub CLI. Please run 'gh auth login'."
    exit 1
}

# Determine paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigDir = Join-Path $ScriptDir "config"
$TemplatesDir = Join-Path $ScriptDir "templates"
$SettingsFile = Join-Path $ConfigDir "settings.json"
$EnvFile = Join-Path $ConfigDir ".env"
$TargetWorkflowDir = Join-Path (Get-Location) ".github\workflows"

Write-Host "Installing Gemini Workflow..." -ForegroundColor Cyan

# 1. Install Workflow Template
if (-not (Test-Path $TargetWorkflowDir)) {
    Write-Host "Creating .github/workflows directory..."
    New-Item -ItemType Directory -Force -Path $TargetWorkflowDir | Out-Null
}

$TemplateFile = Join-Path $TemplatesDir "lumine-gemini.yml"
$TargetFile = Join-Path $TargetWorkflowDir "lumine-gemini.yml"

if (Test-Path $TargetFile) {
    Write-Warning "Workflow file already exists at $TargetFile."
    $response = Read-Host "Do you want to overwrite it? (y/N)"
    if ($response -eq "y") {
        Copy-Item -Path $TemplateFile -Destination $TargetFile -Force
        Write-Host "Workflow updated." -ForegroundColor Green
    } else {
        Write-Host "Skipping workflow installation."
    }
} else {
    Copy-Item -Path $TemplateFile -Destination $TargetFile
    Write-Host "Workflow installed to $TargetFile." -ForegroundColor Green
}

# 2. Inject Configuration
Write-Host "`nSetting up GitHub Variables..." -ForegroundColor Cyan

# Load Settings
if (Test-Path $SettingsFile) {
    try {
        $settings = Get-Content $SettingsFile -Raw | ConvertFrom-Json
        foreach ($prop in $settings.PSObject.Properties) {
            $key = $prop.Name
            $value = $prop.Value
            Write-Host "Setting variable: $key"
            gh variable set $key --body $value
        }
    } catch {
        Write-Error "Failed to parse $SettingsFile. Please ensure it is valid JSON."
        exit 1
    }
} else {
    Write-Warning "Settings file not found at $SettingsFile"
}

Write-Host "`nSetting up GitHub Secrets..." -ForegroundColor Cyan

# Load Secrets from .env with Multi-line Support
if (Test-Path $EnvFile) {
    $envContent = Get-Content $EnvFile
    $currentKey = $null
    $currentValue = $null

    function Set-Secret {
        param($key, $val)
        if (-not [string]::IsNullOrWhiteSpace($key) -and -not [string]::IsNullOrWhiteSpace($val)) {
             # Remove surrounding quotes if present
             if ($val.StartsWith('"') -and $val.EndsWith('"')) {
                 $val = $val.Substring(1, $val.Length - 2)
                 # Unescape \n
                 $val = $val -replace '\\n', "`n"
             }
             Write-Host "Setting secret from .env: $key"
             $val | gh secret set $key
        } elseif (-not [string]::IsNullOrWhiteSpace($key)) {
             Write-Warning "Secret '$key' is empty in .env. Skipping."
        }
    }

    foreach ($line in $envContent) {
        # Check for new key definition (Start of line, Key=Value)
        if ($line -match "^[A-Za-z_][A-Za-z0-9_]*=") {
            # Flush previous
            if ($currentKey) { Set-Secret $currentKey $currentValue }

            $parts = $line.Split("=", 2)
            $currentKey = $parts[0].Trim()
            $currentValue = $parts[1].Trim() # Might be empty or start of value
        } 
        # Skip pure comments or empty lines if strict, but if parsing multi-line value, append
        elseif ($null -ne $currentKey) {
            # We are inside a value (likely multi-line key)
            $currentValue += "`n" + $line
        }
    }
    # Flush final
    if ($currentKey) { Set-Secret $currentKey $currentValue }

} else {
    Write-Warning ".env file not found at $EnvFile"
}

# 3. Create Priority Labels
# [ADDED] Create labels required for triage workflow
Write-Host "`nCreating Priority Labels..." -ForegroundColor Cyan

$Labels = @{
    # Priority labels
    "priority/p0" = @{ Color = "b60205"; Description = "Critical/Blocker - Catastrophic failure demanding immediate attention" }
    "priority/p1" = @{ Color = "d93f0b"; Description = "High - Serious issue significantly degrading UX or core feature" }
    "priority/p2" = @{ Color = "fbca04"; Description = "Medium - Moderately impactful, noticeable but non-blocking" }
    "priority/p3" = @{ Color = "0e8a16"; Description = "Low - Minor, trivial or cosmetic issue" }
}

foreach ($label in $Labels.Keys) {
    $color = $Labels[$label].Color
    $description = $Labels[$label].Description
    Write-Host "Creating label: $label"
    $createResult = gh label create $label --color $color --description $description 2>&1
    if ($LASTEXITCODE -ne 0) {
        $editResult = gh label edit $label --color $color --description $description 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  Label '$label' already exists and couldn't be updated (skipped)" -ForegroundColor Yellow
        }
    }
}

Write-Host "`nSetup complete! Workflow installed and config applied." -ForegroundColor Green
Write-Host "You can verify settings with:"
Write-Host "gh variable list"
Write-Host "gh secret list"
Write-Host "gh label list"
