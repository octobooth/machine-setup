<#
.SYNOPSIS
    Installs or updates the Demo Launcher canvas on Windows.

.DESCRIPTION
    Windows counterpart to install-demo-launcher.sh. Clones
    $HOME\repos\repo-setup-scripts if it's missing, or fast-forwards it if
    it's already there (or pins it to a release with -Ref), then writes a user-level loader to
    $env:COPILOT_HOME\extensions\demo-launcher\extension.mjs (default
    $HOME\.copilot) that imports the launcher from that checkout, so the
    Copilot app can open it from any chat. It also installs the pinned
    Playwright MCP bundle and refreshes the Copilot CLI MCP servers.
    Doesn't need admin. Safe to re-run.

.PARAMETER Ref
    Checks out the release tag: the major the booth uses (v1) or a full
    version (v1.2.0). Also read from $env:BOOTH_RELEASE. Without one, a
    checkout pinned to a release (detached HEAD) switches back to its default
    branch and pulls it (untested main), while a checkout on a branch stays
    on that branch and pulls it.

.PARAMETER Uninstall
    Removes only the loader file. The checkout and the launcher's run history
    (the artifacts folder next to the loader) are kept.

.EXAMPLE
    .\install-demo-launcher.ps1

.EXAMPLE
    .\install-demo-launcher.ps1 -Ref v1

.EXAMPLE
    .\install-demo-launcher.ps1 -Uninstall
#>

param(
    [switch]$Uninstall,
    [string]$Ref
)

# Dot-sourcing setup.ps1 resets its own $Ref parameter in this scope, so keep ours
$requestedRef = $Ref

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
    param([string]$Release)

    $repo = Get-DemoLauncherRepo
    $target = Get-DemoLauncherRepoDir

    if (Test-Path (Join-Path $target ".git")) {
        if (-not (Test-DemoLauncherRemote -Target $target)) {
            $script:failedItems += "update: $repo ($target origin isn't $repo)"
            Write-Err "$target doesn't point at $repo. Check 'git -C `"$target`" remote -v' before using it as a Copilot project."
            return
        }
        if ($Release) {
            Switch-DemoLauncherRelease -Target $target -Ref $Release | Out-Null
            return
        }
        if (-not (Restore-DemoLauncherDefaultBranch -Target $target)) { return }
        Write-Info "Updating $target..."
        Invoke-SafeInstall -Description "update: $repo" -Action {
            Invoke-NativeCommand git -C $target pull --ff-only
        }
        return
    }

    if (Test-Path $target) {
        $script:failedItems += "clone: $repo ($target exists but isn't a git checkout)"
        Write-Err "$target exists but isn't a git checkout. Move it aside and re-run."
        return
    }

    Invoke-NativeCommand gh auth status --active -h github.com | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $script:failedItems += "clone: $repo (GitHub CLI not logged in)"
        Write-Err "GitHub CLI isn't logged in. Run 'gh auth login -h github.com' with the booth account, then re-run."
        return
    }

    New-Item -Path (Split-Path $target) -ItemType Directory -Force | Out-Null
    Write-Info "Cloning $repo into $target..."
    Invoke-SafeInstall -Description "clone: $repo" -Action {
        Invoke-NativeCommand gh repo clone $repo $target
    }
    if ($Release -and $script:failedItems.Count -eq 0 -and (Test-DemoLauncherRemote -Target $target)) {
        Switch-DemoLauncherRelease -Target $target -Ref $Release | Out-Null
    }
}

function Invoke-DemoLauncherMain {
    param(
        [switch]$Uninstall,
        [string]$Ref
    )

    $script:failedItems = @()
    if ($Uninstall) {
        if (Uninstall-DemoLauncherLoader) { return 0 }
        return 1
    }
    if (Test-Path $script:configPath) { Import-Config }

    if (-not (Test-DemoLauncherPrerequisite)) { return 1 }

    $release = Get-BoothRelease -Ref $Ref
    if ($release) { Write-Info "Using release $release of $script:TrustedDemoLauncherRepo" }

    # Send git/gh output to the console so it doesn't become part of the return value
    Sync-DemoLauncherRepo -Release $release | Out-Host

    $target = Get-DemoLauncherRepoDir
    if ($script:failedItems.Count -eq 0) {
        # Also checks the origin of a fresh clone before installing code that runs in every chat
        Install-DemoLauncher
    }

    # Also roll out the pinned Playwright MCP bundle and MCP servers. Only reinstall the
    # bundle when its version changes, and never fail the launcher install over it.
    Install-PlaywrightMcpBundle
    Register-MCPServers

    Write-Summary
    if ($script:failedItems.Count -gt 0) { return 1 }

    if ($release) {
        Write-Success "Demo Launcher is at release $release in $target"
    } else {
        Write-Success "Demo Launcher is up to date at $target"
    }
    Write-Info "Fully quit the GitHub Copilot app (right-click its tray icon and choose Quit), then reopen it."
    Write-Info "Then ask Copilot to `"open the demo launcher`" in any chat."
    Write-Info "Optional, for quick access: add the existing $target folder as a project (don't clone it again) and pin a Current checkout session."
    return 0
}

if ($MyInvocation.InvocationName -ne ".") {
    exit (Invoke-DemoLauncherMain -Uninstall:$Uninstall -Ref $requestedRef)
}
