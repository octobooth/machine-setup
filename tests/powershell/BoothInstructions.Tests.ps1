Describe 'Copilot booth instructions' {
    BeforeAll {
        . (Join-Path (Get-Location) 'setup.ps1')

        Mock Write-Info { }
        Mock Write-Success { }
        Mock Write-Warn { }
        Mock Write-Err { }
        Mock Write-Host { }

        $script:originalCopilotHome = $env:COPILOT_HOME
        $script:originalSource = $script:BoothInstructionsSource

        function Get-ExpectedBlock {
            $text = [System.IO.File]::ReadAllText($script:BoothInstructionsSource) -replace "`r`n", "`n"
            return $script:BoothInstructionsBegin + "`n" + $text.TrimEnd() + "`n" + $script:BoothInstructionsEnd + "`n"
        }
    }

    BeforeEach {
        $script:failedItems = @()
        $env:COPILOT_HOME = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:BoothInstructionsSource = $script:originalSource
        $script:target = Join-Path $env:COPILOT_HOME 'copilot-instructions.md'
    }

    AfterAll {
        $env:COPILOT_HOME = $script:originalCopilotHome
        $script:BoothInstructionsSource = $script:originalSource
    }

    It 'source steers away from npm and pip' {
        $text = [System.IO.File]::ReadAllText($script:BoothInstructionsSource)
        $text | Should -Match 'npm install'
        $text | Should -Match 'pip install'
        $text | Should -Match 'index\.html'
        $text | Should -Match 'Cloud session'
    }

    It 'creates the file and its folder as UTF-8 without a BOM' {
        Install-BoothInstruction

        $script:failedItems | Should -BeNullOrEmpty
        $bytes = [System.IO.File]::ReadAllBytes($script:target)
        $bytes[0] | Should -Not -Be 0xEF
        [System.IO.File]::ReadAllText($script:target) | Should -BeExactly (Get-ExpectedBlock)
    }

    It "keeps the user's instructions and appends the block" {
        New-Item -Path $env:COPILOT_HOME -ItemType Directory -Force | Out-Null
        [System.IO.File]::WriteAllText($script:target, "My rule`nAnother rule")

        Install-BoothInstruction

        [System.IO.File]::ReadAllText($script:target) | Should -BeExactly ("My rule`nAnother rule`n`n" + (Get-ExpectedBlock))
    }

    It 'is idempotent' {
        New-Item -Path $env:COPILOT_HOME -ItemType Directory -Force | Out-Null
        [System.IO.File]::WriteAllText($script:target, "My rule`n")

        Install-BoothInstruction
        $first = [System.IO.File]::ReadAllText($script:target)
        Install-BoothInstruction

        [System.IO.File]::ReadAllText($script:target) | Should -BeExactly $first
        Should -Invoke Write-Success -ParameterFilter { $Message -like '*up to date*' } -Times 1 -Exactly
    }

    It 'replaces only the managed block and keeps CRLF line endings' {
        New-Item -Path $env:COPILOT_HOME -ItemType Directory -Force | Out-Null
        $old = "Before`r`n$($script:BoothInstructionsBegin)`r`nold booth text`r`n$($script:BoothInstructionsEnd)`r`nAfter`r`n"
        [System.IO.File]::WriteAllText($script:target, $old)

        Install-BoothInstruction

        $expected = ("Before`n" + (Get-ExpectedBlock) + "After`n") -replace "`n", "`r`n"
        [System.IO.File]::ReadAllText($script:target) | Should -BeExactly $expected
    }

    It 'leaves the file alone when markers are unmatched' {
        New-Item -Path $env:COPILOT_HOME -ItemType Directory -Force | Out-Null
        $before = "Mine`n$($script:BoothInstructionsBegin)`nmore of mine`n"
        [System.IO.File]::WriteAllText($script:target, $before)

        Install-BoothInstruction

        $script:failedItems.Count | Should -Be 1
        [System.IO.File]::ReadAllText($script:target) | Should -BeExactly $before
    }

    It 'fails when the source file is missing' {
        $script:BoothInstructionsSource = Join-Path $TestDrive 'missing.md'

        Install-BoothInstruction

        $script:failedItems.Count | Should -Be 1
        Test-Path -LiteralPath $script:target | Should -BeFalse
    }
}
