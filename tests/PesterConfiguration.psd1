@{
    # Pester 6 configuration for adman.
    #
    # Quick run (mocked, never touches a domain):
    #   Invoke-Pester -Path tests -Output Normal -TagFilter Unit
    # Full suite (incl. coverage + JUnit for CI):
    #   Invoke-Pester -Configuration (Import-PowerShellDataFile tests/PesterConfiguration.psd1)
    #   (Import-PowerShellDataFile is available on PowerShell 7+/CI; on 5.1 use the quick run.)

    Run          = @{
        Path = 'tests'
        Exit = $false
    }

    Filter       = @{
        Tag = 'Unit'
    }

    CodeCoverage = @{
        Enabled             = $true
        Path                = @('Public/*.ps1', 'Private/*.ps1')
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
