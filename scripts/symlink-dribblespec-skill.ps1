param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [switch]$Force
)

$source = Join-Path $RepoRoot ".agents\skills\dribblespec"
$targetRoot = Join-Path $HOME ".agents\skills"
$target = Join-Path $targetRoot "dribblespec"

if (-not (Test-Path $source -PathType Container)) {
    throw "Skill source directory not found: $source"
}

New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null

if (Test-Path $target) {
    $item = Get-Item $target -Force
    $sourceResolved = (Resolve-Path $source).Path
    $targetResolved = $null

    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        $linkTarget = $item.Target
        if ($linkTarget -is [array]) {
            $linkTarget = $linkTarget[0]
        }

        if ([string]::IsNullOrWhiteSpace($linkTarget) -eq $false) {
            try {
                $targetResolved = (Resolve-Path $linkTarget).Path
            }
            catch {
                $targetResolved = $linkTarget
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($targetResolved)) {
        try {
            $targetResolved = (Resolve-Path $target).Path
        }
        catch {
            $targetResolved = $null
        }
    }

    $sourceNormalized = $sourceResolved.TrimEnd('\\')
    $targetNormalized = if ($targetResolved) { $targetResolved.TrimEnd('\\') } else { $null }

    if ($targetNormalized -and [string]::Compare($targetNormalized, $sourceNormalized, $true) -eq 0) {
        Write-Output "Skill link already points to repo-local dribblespec skill."
        exit 0
    }

    if (-not $Force) {
        throw "Target exists and points elsewhere: $target (use -Force to replace)"
    }

    Remove-Item $target -Recurse -Force
}

try {
    New-Item -ItemType SymbolicLink -Path $target -Target $source -Force -ErrorAction Stop | Out-Null
    Write-Output "Created symbolic link: $target -> $source"
}
catch {
    New-Item -ItemType Junction -Path $target -Target $source -Force -ErrorAction Stop | Out-Null
    Write-Output "Created junction: $target -> $source"
}
