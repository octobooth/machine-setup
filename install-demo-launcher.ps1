<#
.SYNOPSIS
    Installs or updates the Demo Launcher canvas checkout on Windows.

.DESCRIPTION
    Windows counterpart to install-demo-launcher.sh. The Demo Launcher's
    install.sh is macOS/Linux only, so on Windows the canvas loads from the
    repo-setup-scripts project checkout in $HOME\repos\repo-setup-scripts.
    This script clones that checkout if it's missing, or fast-forwards it if
    it's already there. Safe to re-run.

.EXAMPLE
    .\install-demo-launcher.ps1
#>

# setup.ps1 only runs Invoke-Main when executed directly, so dot-sourcing it just loads its helpers
. (Join-Path $PSScriptRoot "setup.ps1")

# Only this repo is trusted as the Demo Launcher source, because its checkout is
# added as a Copilot project and its contents shape what Copilot does there.
$script:TrustedDemoLauncherRepo = "octobooth-demos/repo-setup-scripts"

function Get-DemoLauncherRepo {
    if ($null -ne $script:config) {
        $configured = $script:config.shared.repos_to_clone | Where-Object { ($_ -split '/')[-1] -eq 'repo-setup-scripts' } | Select-Object -First 1
        if ($configured -and $configured -ne $script:TrustedDemoLauncherRepo) {
            Write-Warn "Ignoring untrusted Demo Launcher repo '$configured' in config.json; using $script:TrustedDemoLauncherRepo."
        }
    }
    return $script:TrustedDemoLauncherRepo
}

function Test-DemoLauncherRemote {
    param([string]$Target)

    $url = git -C $Target remote get-url origin 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    $pattern = '^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)' + [regex]::Escape($script:TrustedDemoLauncherRepo) + '(\.git)?/?$'
    return ("$url".Trim() -match $pattern)
}

function Get-DemoLauncherRepoDir {
    return Join-Path (Join-Path $env:USERPROFILE "repos") "repo-setup-scripts"
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
    $script:failedItems = @()
    if (Test-Path $script:configPath) { Import-Config }

    if (-not (Test-DemoLauncherPrerequisite)) { return 1 }

    # Send git/gh output to the console so it doesn't become part of the return value
    Sync-DemoLauncherRepo | Out-Host

    Write-Summary
    if ($script:failedItems.Count -gt 0) { return 1 }

    $target = Get-DemoLauncherRepoDir
    Write-Success "Demo Launcher checkout is up to date at $target"
    Write-Info "Restart the GitHub Copilot app (or reload extensions) to pick up the update."
    Write-Info "If you haven't yet, add the existing $target folder as a project in the Copilot app (don't clone it again)."
    Write-Info "Then start a session in that project (choose Current checkout, not New worktree) and ask Copilot to `"open the demo launcher`"."
    return 0
}

if ($MyInvocation.InvocationName -ne ".") {
    exit (Invoke-DemoLauncherMain)
}
