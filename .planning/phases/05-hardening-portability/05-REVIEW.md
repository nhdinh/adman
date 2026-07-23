---
phase: 05-hardening-portability
reviewed: 2026-07-23T18:30:00Z
depth: standard
files_reviewed: 11
files_reviewed_list:
  - Public/Set-AdmanUserPassword.ps1
  - Public/New-AdmanUser.ps1
  - Public/Set-AdmanLocalUser.ps1
  - Private/Workflow/Get-AdmanOffboardingState.ps1
  - Public/Start-AdmanUserOnboarding.ps1
  - Public/Config/Export-AdmanConfig.ps1
  - tests/Workflow.OffboardingState.Tests.ps1
  - Public/Start-Adman.ps1
  - build/Sign-AdmanModule.ps1
  - .github/workflows/ci.yml
  - Private/Config/Initialize-AdmanConfig.ps1
findings:
  critical: 0
  warning: 4
  info: 3
  total: 7
status: issues_found
---

# Phase 05: Code Review Report (Re-review)

**Reviewed:** 2026-07-23T18:30:00Z
**Depth:** standard
**Files Reviewed:** 11
**Status:** issues_found

## Summary

This is a verification re-review of the files changed during the Phase 05 review/fix cycle. Most of the prior cycle's findings have been addressed correctly: the generated-password display was moved before follow-up sub-operations in `Set-AdmanUserPassword`, password-source `ValidateSet` now accepts `'Ask'`, offboarding-state sorting defends against bad `tsUtc`, onboarding preflight rejects the full invalid `sAMAccountName` character set, audit integrity is verified before restore records are consumed, the timestamp URL uses the standard HTTP endpoint, CI self-signed trust is set up for `AllSigned`, and the onboarding workflow now validates `ParentOuDn` against managed scope before confirmation.

However, four warnings and three info items remain. The most significant is that `Start-Adman.ps1` still calls the CSV/HTML renderer with a null path when the operator cancels or repeatedly enters an invalid directory, because the prior `WR-07` fix was incomplete. Two other issues are regressions or incomplete follow-through from the earlier fixes: `Export-AdmanConfig` can corrupt paths that happen to start with the module root but are not actually underneath it, and the offboarding-state test still pollutes `$env:PSModulePath`.

## Critical Issues

No critical issues found in the reviewed files.

## Warnings

### WR-01: `Start-Adman.ps1` still calls the CSV/HTML renderer with a null path on cancel or repeated invalid input

**File:** `Public/Start-Adman.ps1:225-245, 251-270`
**Issue:** The prior `WR-07` finding is not fully fixed. When the operator enters `B` inside the CSV or HTML path prompt, the code sets `$formatResolved = $true` and `$pathResolved = $true`, but it leaves `$renderer` set to `Export-AdmanReportCsv` / `Export-AdmanReportHtml` and never sets `$rendererParams['Path']`. Because `$formatResolved` is true, the outer format loop exits and falls through to `if ($null -ne $renderer)`, which calls the renderer with a null `$Path`. The same thing happens after two invalid path attempts, where `if (-not $pathResolved) { continue }` continues an already-exiting outer loop. This produces an avoidable error or undefined file behavior instead of returning cleanly to the menu.
**Fix:** Clear `$renderer` whenever the path is not resolved. For example, in the CSV case:

```powershell
if ($outPath -match '^[Bb]$') {
    $formatResolved = $true
    $pathResolved   = $true
    $renderer       = $null
    continue
}
```

And after the inner path loop:

```powershell
if (-not $pathResolved) {
    $renderer = $null
    continue
}
```

Apply the same change to the HTML case.

### WR-02: `Export-AdmanConfig` path relativization corrupts paths that merely start with the module root

**File:** `Public/Config/Export-AdmanConfig.ps1:45-52`
**Issue:** The `WR-04` fix relativizes `AuditDir` and `ReportDir` by checking `$p.StartsWith($moduleRoot)`. A configured path such as `C:\...\adman-reports\reports` starts with the module root string but is not inside the module directory. The substring + `TrimStart` would turn it into an invalid relative fragment (for example `-reports\reports`), and the next import would resolve it to a different directory under the module root. This silently corrupts portable backups when an admin chooses an external path that happens to share the module-root prefix.
**Fix:** Verify that the remainder begins with a path separator before relativizing:

```powershell
foreach ($key in @('AuditDir', 'ReportDir')) {
    $p = $exportCfg.$key
    if ($p -is [string] -and $p.StartsWith($moduleRoot)) {
        $remainder = $p.Substring($moduleRoot.Length)
        if ($remainder.StartsWith('\') -or $remainder.StartsWith('/')) {
            $exportCfg.$key = $remainder.TrimStart('\', '/')
        }
    }
}
```

### WR-03: Offboarding-state test still pollutes the process-wide PSModulePath

**File:** `tests/Workflow.OffboardingState.Tests.ps1:32`
**Issue:** The prior `IN-05` finding is not fixed. `BeforeAll` prepends a stub PSFramework path to `$env:PSModulePath`, but `AfterAll` only removes the `Resolve-AdmanTarget` global stub. The modified module path persists for later test files in the same Pester run, which can cause ordering-dependent failures if a later test unexpectedly resolves the stub instead of the real PSFramework (or the reverse).
**Fix:** Save and restore the original path in `AfterAll`:

```powershell
BeforeAll {
    $script:OriginalPSModulePath = $env:PSModulePath
    # ... existing stub setup ...
}

AfterAll {
    $env:PSModulePath = $script:OriginalPSModulePath
    Remove-Item -Path Function:\Resolve-AdmanTarget -ErrorAction SilentlyContinue
}
```

### WR-04: `Sign-AdmanModule.ps1` exclusion regex matches directory-name substrings

**File:** `build/Sign-AdmanModule.ps1:80-81`
**Issue:** The signing exclusion pattern `\(tests|\.github|\.githooks)\` matches any directory path that contains those substrings, not just the top-level directories `tests`, `.github`, and `.githooks`. A legitimate directory such as `adman-tests\` or `mygithooks\` would have its `.ps1` files silently excluded from signing. Under `AllSigned`, unsigned module files fail to load, so this regex could break a deployment that organizes scripts in directories whose names happen to contain those words.
**Fix:** Anchor the pattern to a path separator at the start of the matched segment, or explicitly exclude only the known top-level directories:

```powershell
Where-Object { $_.FullName -notmatch '(^|\\)(tests|\.github|\.githooks)\\' }
```

## Info

### IN-01: `Start-Adman.ps1` menu dispatch does not restrict `Get-Command` to adman functions

**File:** `Public/Start-Adman.ps1:171-175`
**Issue:** The menu verb is validated with `Get-Command -Name $Verb -ErrorAction SilentlyContinue`. If `$Verb` matches an alias, external executable, or function from another module, the call proceeds. In practice the menu definition should only contain adman verbs, but the guard is weaker than it claims.
**Fix:** Restrict the lookup to functions exported by the adman module:

```powershell
$cmd = Get-Command -Name $Verb -Module adman -CommandType Function -ErrorAction SilentlyContinue
```

### IN-02: `Export-AdmanConfig` `TrimStart` can over-trim multiple leading separators

**File:** `Public/Config/Export-AdmanConfig.ps1:50`
**Issue:** `TrimStart('\', '/')` removes every leading backslash or slash, not a single separator. If the path remainder were ever `\\server\share` (unlikely after the substring operation, but possible if the original value was a UNC path rooted under the module root), it would over-strip. Combined with `WR-02`, this is another reason to verify the separator before trimming.
**Fix:** After fixing `WR-02`, remove only the single leading separator or use a regex replace for the exact prefix.

### IN-03: `Initialize-AdmanConfig` still reassigns `$moduleRoot` redundantly

**File:** `Private/Config/Initialize-AdmanConfig.ps1:422`
**Issue:** The prior `IN-07` finding is not fixed. `$moduleRoot` is resolved at line 312 and reassigned at line 422 immediately before path absolutization. This is harmless duplication but adds noise and increases the chance of future drift if one of the two resolution expressions is changed.
**Fix:** Remove the duplicate assignment at line 422 and use the existing `$moduleRoot` variable.

---

_Reviewed: 2026-07-23T18:30:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
