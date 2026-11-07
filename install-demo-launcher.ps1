<#
.SYNOPSIS
    Installs or updates the Demo Launcher canvas on Windows.

.DESCRIPTION
    Windows counterpart to install-demo-launcher.sh. Clones
    $HOME\repos\repo-setup-scripts if it's missing, or fast-forwards it if
    it's already there, then writes a user-level loader to
    $env:COPILOT_HOME\extensions\demo-launcher\extension.mjs (default
    $HOME\.copilot) that imports the launcher from that checkout, so the
    Copilot app can open it from any chat. Doesn't need admin. Safe to re-run.

.PARAMETER Uninstall
    Removes only the loader file. The checkout and the launcher's run history
    (the artifacts folder next to the loader) are kept.

.EXAMPLE
    .\install-demo-launcher.ps1

.EXAMPLE
    .\install-demo-launcher.ps1 -Uninstall
#>

param([switch]$Uninstall)

# setup.ps1 only runs Invoke-Main when executed directly, so dot-sourcing it just loads its helpers
. (Join-Path $PSScriptRoot "setup.ps1")

function Get-DemoLauncherRepo {
    if ($null -ne $script:config) {
        $configured = $script:config.shared.repos_to_clone | Where-Object { ($_ -split '/')[-1] -eq 'repo-setup-scripts' } | Select-Object -First 1
        if ($configured -and $configured -ne $script:TrustedDemoLauncherRepo) {
            Write-Warn "Ignoring untrusted Demo Launcher repo '$configured' in config.json; using $script:TrustedDemoLauncherRepo."
        }
    }
    return $script:TrustedDemoLauncherRepo
}

function Test-DemoLauncherPrerequisite {
    $ok = $true
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Err "git not found. Run .\setup.ps1 first, or: winget install --id Git.Git -e --source winget"
        $ok = $false
    }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Err "GitHub CLI not found. Run .\setup.ps1 first, or: winget install --id GitHub.cli -e --source winget"
        $ok = $false
    }
    return $ok
}

function Sync-DemoLauncherRepo {
    $repo = Get-DemoLauncherRepo
    $target = Get-DemoLauncherRepoDir

    if (Test-Path (Join-Path $target ".git")) {
        if (-not (Test-DemoLauncherRemote -Target $target)) {
            $script:failedItems += "update: $repo ($target origin isn't $repo)"
            Write-Err "$target doesn't point at $repo. Check 'git -C `"$target`" remote -v' before using it as a Copilot project."
            return
        }
        Write-Info "Updating $target..."
        Invoke-SafeInstall -Description "update: $repo" -Action {
            git -C $target pull --ff-only 2>&1
        }
        return
    }

    if (Test-Path $target) {
        $script:failedItems += "clone: $repo ($target exists but isn't a git checkout)"
        Write-Err "$target exists but isn't a git checkout. Move it aside and re-run."
        return
    }

    gh auth status --active -h github.com 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $script:failedItems += "clone: $repo (GitHub CLI not logged in)"
        Write-Err "GitHub CLI isn't logged in. Run 'gh auth login -h github.com' with the booth account, then re-run."
        return
    }

    New-Item -Path (Split-Path $target) -ItemType Directory -Force | Out-Null
    Write-Info "Cloning $repo into $target..."
    Invoke-SafeInstall -Description "clone: $repo" -Action {
        gh repo clone $repo $target 2>&1
    }
}

function Invoke-DemoLauncherMain {
    param([switch]$Uninstall)

    $script:failedItems = @()
    if ($Uninstall) {
        Uninstall-DemoLauncherLoader
        return 0
    }
    if (Test-Path $script:configPath) { Import-Config }

    if (-not (Test-DemoLauncherPrerequisite)) { return 1 }

    # Send git/gh output to the console so it doesn't become part of the return value
    Sync-DemoLauncherRepo | Out-Host

    $target = Get-DemoLauncherRepoDir
    if ($script:failedItems.Count -eq 0) {
        Install-DemoLauncherLoader -CheckoutDir $target
    }

    Write-Summary
    if ($script:failedItems.Count -gt 0) { return 1 }

    Write-Success "Demo Launcher is up to date at $target"
    Write-Info "Fully quit the GitHub Copilot app (right-click its tray icon and choose Quit), then reopen it."
    Write-Info "Then ask Copilot to `"open the demo launcher`" in any chat."
    Write-Info "Optional, for quick access: add the existing $target folder as a project (don't clone it again) and pin a Current checkout session."
    return 0
}

if ($MyInvocation.InvocationName -ne ".") {
    exit (Invoke-DemoLauncherMain -Uninstall:$Uninstall)
}
