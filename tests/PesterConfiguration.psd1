@{
    # Pester 6 configuration for adman.
    #
    # CI uses this configuration for both Windows PowerShell 5.1 (Desktop) and
    # PowerShell 7.6 LTS (Core). Import-PowerShellDataFile is used in both legs.
    # Quick run (mocked, never touches a domain):
    #   Invoke-Pester -Path tests -Output Normal -TagFilter Unit
    # Full suite (incl. coverage + JUnit for CI):
    #   Invoke-Pester -Configuration (Import-PowerShellDataFile tests/PesterConfiguration.psd1)

    Run          = @{
        Path = 'tests'
        Exit = $false
    }

    Filter       = @{
        Tag = 'Unit'
    }

    CodeCoverage = @{
        Enabled             = $true
        Path                = @('Public/**/*.ps1', 'Private/**/*.ps1')
        UseBreakpoints      = $false   # profiler-based coverage (Pester 6 default)
        OutputFormat        = 'JaCoCo'
        OutputPath          = 'tests/coverage.xml'
        CoveragePercentTarget = 0
    }

    Output       = @{
        Verbosity = 'Detailed'
    }

    TestResult   = @{
        Enabled      = $true
        OutputFormat = 'JUnitXml'
        OutputPath   = 'tests/TestResults.xml'
    }

    Should       = @{
        ErrorAction = 'Stop'
    }
}
