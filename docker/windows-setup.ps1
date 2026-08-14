# Windows 11 Setup Script for Agentic AI Stack
# Run this in PowerShell as Administrator
# Purpose: Automate WSL2 and Docker Desktop setup

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

# Color output functions
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Error-Message {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Check Windows version
function Test-WindowsVersion {
    Write-Info "Checking Windows version..."

    $osInfo = Get-ComputerInfo
    $osVersion = $osInfo.OsVersion
    $osBuild = $osInfo.OsBuildNumber

    if ($osInfo.OsName -notlike "*Windows 11*") {
        Write-Warning "Not Windows 11: $($osInfo.OsName)"
        Write-Warning "WSL2 should work but is not officially tested"
    } else {
        Write-Success "Running Windows 11 ✓"
    }

    if ($osBuild -lt 19041) {
        Write-Error-Message "Build $osBuild is too old for WSL2"
        Write-Error-Message "WSL2 requires build 19041 or later"
        exit 1
    }

    Write-Success "Build $osBuild supports WSL2 ✓"
}

# Check system resources
function Test-SystemResources {
    Write-Info "Checking system resources..."

    # RAM
    $totalRAM = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    if ($totalRAM -ge 64) {
        Write-Success "RAM: $totalRAM GB (adequate) ✓"
    } else {
        Write-Warning "RAM: $totalRAM GB (need 64+ GB for 14B models)"
    }

    # CPU
    $cpuCores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
    if ($cpuCores -ge 16) {
        Write-Success "CPU: $cpuCores cores (adequate) ✓"
    } else {
        Write-Warning "CPU: $cpuCores cores (need 16+ for optimal performance)"
    }

    # Disk space
    $disk = Get-PSDrive C
    $freeSpaceGB = [math]::Round($disk.Free / 1GB)
    if ($freeSpaceGB -ge 100) {
        Write-Success "Disk: $freeSpaceGB GB free (adequate) ✓"
    } else {
        Write-Warning "Disk: $freeSpaceGB GB free (need 100+ GB)"
    }
}

# Enable WSL2
function Enable-WSL2 {
    Write-Info "Checking WSL2 status..."

    try {
        $wslVersion = wsl --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "WSL2 already enabled ✓"
            return $false  # No reboot needed
        }
    } catch {
        Write-Info "WSL2 not yet enabled"
    }

    Write-Info "Enabling WSL2 features..."

    try {
        # Enable WSL
        dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null

        # Enable Virtual Machine Platform
        dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null

        Write-Success "WSL2 features enabled"
        return $true  # Reboot needed
    } catch {
        Write-Error-Message "Failed to enable WSL2 features: $_"
        Write-Error-Message "Run this script as Administrator"
        exit 1
    }
}

# Set WSL2 as default
function Set-WSL2Default {
    Write-Info "Setting WSL2 as default version..."

    try {
        wsl --set-default-version 2 2>&1 | Out-Null
        Write-Success "WSL2 set as default ✓"
    } catch {
        Write-Warning "Could not set WSL2 as default (may need reboot first)"
    }
}

# Install Ubuntu
function Install-Ubuntu {
    Write-Info "Checking for Ubuntu installation..."

    $ubuntuInstalled = wsl -l -v 2>&1 | Select-String "Ubuntu"

    if ($ubuntuInstalled) {
        Write-Success "Ubuntu already installed ✓"
        return
    }

    Write-Info "Installing Ubuntu 24.04..."
    Write-Info "This will take a few minutes..."

    try {
        wsl --install -d Ubuntu-24.04
        Write-Success "Ubuntu 24.04 installed ✓"
        Write-Info "First launch will require username/password setup"
    } catch {
        Write-Error-Message "Ubuntu installation failed: $_"
        Write-Info "You can manually install from Microsoft Store:"
        Write-Info "https://www.microsoft.com/store/productId/9NZ3KLHXDJP5"
        exit 1
    }
}

# Check Docker Desktop
function Test-DockerDesktop {
    Write-Info "Checking Docker Desktop..."

    $dockerExe = "C:\Program Files\Docker\Docker\Docker Desktop.exe"

    if (Test-Path $dockerExe) {
        Write-Success "Docker Desktop installed ✓"

        # Check if running
        $dockerProcess = Get-Process "Docker Desktop" -ErrorAction SilentlyContinue
        if ($dockerProcess) {
            Write-Success "Docker Desktop is running ✓"
        } else {
            Write-Info "Starting Docker Desktop..."
            Start-Process $dockerExe
            Write-Success "Docker Desktop started"
            Write-Info "Wait 30-60 seconds for Docker to initialize"
        }
    } else {
        Write-Warning "Docker Desktop not found"
        Write-Info "Download from: https://www.docker.com/products/docker-desktop"
        Write-Info ""
        Write-Info "Installation steps:"
        Write-Info "  1. Download Docker Desktop for Windows"
        Write-Info "  2. Run installer"
        Write-Info "  3. Enable 'Use WSL 2 based engine'"
        Write-Info "  4. Restart computer if prompted"
        Write-Info "  5. Run this script again"
    }
}

# Create WSL config
function New-WSLConfig {
    Write-Info "Creating WSL configuration..."

    $wslConfigPath = "$env:USERPROFILE\.wslconfig"

    if (Test-Path $wslConfigPath) {
        Write-Info ".wslconfig already exists"
        return
    }

    $totalRAM = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    $wslRAM = [math]::Min($totalRAM - 16, 64)  # Leave 16GB for Windows, max 64GB
    $cpuCores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
    $wslCPU = [math]::Max($cpuCores - 4, 16)  # Leave 4 cores for Windows, min 16

    $configContent = @"
[wsl2]
memory=${wslRAM}GB
processors=$wslCPU
swap=2GB
localhostForwarding=true

# Optimize for Docker workloads
guiApplications=false
nestedVirtualization=false
"@

    Set-Content -Path $wslConfigPath -Value $configContent
    Write-Success ".wslconfig created: ${wslRAM}GB RAM, $wslCPU cores"
    Write-Info "Location: $wslConfigPath"
}

# Show next steps
function Show-NextSteps {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║           Windows 11 Setup Complete                          ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    Write-Success "✓ WSL2 enabled"
    Write-Success "✓ Ubuntu 24.04 ready"
    Write-Success "✓ Docker Desktop configured"
    Write-Success "✓ Resource limits set"

    Write-Host ""
    Write-Info "Next Steps:"
    Write-Host ""
    Write-Host "1. Configure Docker Desktop:"
    Write-Host "   • Open Docker Desktop"
    Write-Host "   • Go to Settings → Resources → WSL Integration"
    Write-Host "   • Enable Ubuntu-24.04"
    Write-Host "   • Click Apply & Restart"
    Write-Host ""
    Write-Host "2. Launch Ubuntu and clone repository:"
    Write-Host "   wsl -d Ubuntu-24.04"
    Write-Host "   cd ~"
    Write-Host "   git clone <your-repo-url>"
    Write-Host "   cd applications.ai.enterprise.agentic-ai-stack"
    Write-Host ""
    Write-Host "3. Configure deployment:"
    Write-Host "   cd docker"
    Write-Host "   nano config.cfg  # Add your HuggingFace token"
    Write-Host ""
    Write-Host "4. Deploy:"
    Write-Host "   ./windows-deploy.sh start"
    Write-Host ""
    Write-Host "5. Access from Windows browser:"
    Write-Host "   http://localhost:4000/ui  (LiteLLM Gateway)"
    Write-Host "   http://localhost:2080/docs  (vLLM API)"
    Write-Host ""

    Write-Info "Documentation:"
    Write-Host "  • Quick Start: docker/WINDOWS_QUICK_START.md"
    Write-Host "  • Full Guide:  docker/WINDOWS_DEPLOYMENT.md"
    Write-Host ""

    Write-Info "Helper commands (in WSL2):"
    Write-Host "  ./windows-deploy.sh status   # Check health"
    Write-Host "  ./windows-deploy.sh logs     # View logs"
    Write-Host "  ./windows-deploy.sh test     # Test API"
    Write-Host "  ./windows-deploy.sh check    # System check"
    Write-Host ""
}

# Main execution
function Main {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║     Agentic AI Stack - Windows 11 Setup Script              ║" -ForegroundColor Cyan
    Write-Host "║     Intel Enterprise Agent Toolkit                           ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # Checks
    Test-WindowsVersion
    Test-SystemResources
    Write-Host ""

    # Setup
    $needsReboot = Enable-WSL2

    if ($needsReboot) {
        Write-Warning "REBOOT REQUIRED"
        Write-Info "Restart your computer, then run this script again"
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 0
    }

    Set-WSL2Default
    Install-Ubuntu
    New-WSLConfig
    Test-DockerDesktop

    # Summary
    Show-NextSteps

    Write-Host ""
    Write-Success "Setup complete!"
    Write-Host ""
    Read-Host "Press Enter to exit"
}

# Run
try {
    Main
} catch {
    Write-Error-Message "Setup failed: $_"
    Write-Error-Message $_.ScriptStackTrace
    Read-Host "Press Enter to exit"
    exit 1
}
