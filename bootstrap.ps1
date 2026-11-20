<#
.SYNOPSIS
    Downloads the complete machine-setup archive and runs setup on Windows.
.PARAMETER Ref
    main for development, or a release tag such as v1 or v1.2.0 for both
    machine-setup and repo-setup-scripts. Defaults to BOOTH_RELEASE, then main.
#>
param([string]$Ref)

function Invoke-SetupBootstrap {
    param([string]$Ref)

    $ErrorActionPreference = 'Stop'
    if (-not $Ref) {
        $Ref = if ($env:BOOTH_RELEASE) { $env:BOOTH_RELEASE } else { 'main' }
    }
    if ($Ref -ceq 'main') {
        $archiveRef = 'heads/main'
    } elseif ($Ref -cmatch '^v[0-9]+(\.[0-9]+\.[0-9]+)?$') {
        $archiveRef = "tags/$Ref"
    } else {
        throw "Invalid ref '$Ref': use main or a release tag such as v1 or v1.2.0."
    }

    $workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("machine-setup-" + [guid]::NewGuid().ToString())
    $savedRelease = $env:BOOTH_RELEASE
    $savedProtocol = [Net.ServicePointManager]::SecurityProtocol
    New-Item -ItemType Directory -Path $workDir | Out-Null
    try {
        [Net.ServicePointManager]::SecurityProtocol = $savedProtocol -bor [Net.SecurityProtocolType]::Tls12
        $archive = Join-Path $workDir 'setup.zip'
        $source = Join-Path $workDir 'source'
        Write-Host "Downloading machine-setup at $Ref..."
        Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/octobooth/machine-setup/archive/refs/$archiveRef.zip" -OutFile $archive
        Expand-Archive -LiteralPath $archive -DestinationPath $source
        $roots = @(Get-ChildItem -LiteralPath $source -Directory)
        if ($roots.Count -ne 1 -or
            -not (Test-Path -LiteralPath (Join-Path $roots[0].FullName 'setup.ps1') -PathType Leaf) -or
            -not (Test-Path -LiteralPath (Join-Path $roots[0].FullName 'config.json') -PathType Leaf)) {
            throw 'Downloaded archive is missing setup.ps1 or config.json; setup was not started.'
        }

        $setup = Join-Path $roots[0].FullName 'setup.ps1'
        $setupArgs = @()
        $env:BOOTH_RELEASE = $null
        if ($Ref -cne 'main') {
            $env:BOOTH_RELEASE = $Ref
            $setupArgs = @('-Ref', $Ref)
        }
        Write-Host "Running machine-setup at $Ref. Answer the setup and sign-in prompts in this terminal."
        # A child process preserves interactive stdin and isolates setup's exit statements.
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $setup @setupArgs
        $status = $LASTEXITCODE
        if ($status -ne 0) {
            Write-Host "Setup failed (exit $status). Fix the reported problem and rerun the bootstrap."
        }
    }
    finally {
        $env:BOOTH_RELEASE = $savedRelease
        [Net.ServicePointManager]::SecurityProtocol = $savedProtocol
        Remove-Item -LiteralPath $workDir -Recurse -Force
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-SetupBootstrap -Ref $Ref
        exit $LASTEXITCODE
    }
    catch {
        Write-Error $_
        exit 1
    }
}
