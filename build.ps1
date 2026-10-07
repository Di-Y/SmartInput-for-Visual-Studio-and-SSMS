param(
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Release',
    [switch]$SkipRestore,
    [string]$MSBuildPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Push-Location $PSScriptRoot
try {
    if (-not $MSBuildPath) {
        $vswherePath = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
        if (-not (Test-Path -LiteralPath $vswherePath)) { throw 'vswhere was not found. Pass MSBuild.exe with -MSBuildPath.' }
        $MSBuildPath = & $vswherePath -latest -products '*' -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
    }
    if (-not $MSBuildPath -or -not (Test-Path -LiteralPath $MSBuildPath)) { throw 'MSBuild was not found. VS 2022 17.14+ or compatible build tools and the .NET Framework 4.8 targeting pack are required.' }
    if (-not $SkipRestore) {
        & $MSBuildPath 'SmartInput.sln' /t:Restore /p:RestoreConfigFile=NuGet.Config /nr:false /v:minimal /nologo
        if ($LASTEXITCODE -ne 0) { throw "Restore failed: $LASTEXITCODE" }
    }
    & $MSBuildPath 'SmartInput.sln' "/p:Configuration=$Configuration" /nr:false /v:minimal /nologo
    if ($LASTEXITCODE -ne 0) { throw "Build failed: $LASTEXITCODE" }
    # The solution maps the Tests project to Debug|x86 for BOTH solution configurations, so the
    # test executable is built into bin\Debug regardless of -Configuration. Locate the freshly
    # built executable robustly instead of assuming bin\<Configuration> (which only worked before
    # when a stale bin\Release copy happened to exist).
    $testBinDir = Join-Path $PSScriptRoot 'tests\SmartInput.Tests\bin'
    $testPath = Join-Path $testBinDir "$Configuration\SmartInput.Tests.exe"
    if (-not (Test-Path -LiteralPath $testPath)) {
        $newest = Get-ChildItem -LiteralPath $testBinDir -Recurse -Filter 'SmartInput.Tests.exe' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($newest) { $testPath = $newest.FullName }
    }
    if (-not (Test-Path -LiteralPath $testPath)) { throw 'SmartInput.Tests.exe was not found; build the solution before running tests.' }
    Write-Host "Running tests: $testPath"
    & $testPath
    if ($LASTEXITCODE -ne 0) { throw "Tests failed: $LASTEXITCODE" }
    & (Join-Path $PSScriptRoot 'tools\Verify-Package.ps1') -Configuration $Configuration
    & (Join-Path $PSScriptRoot 'tools\Verify-LegacyPackage.ps1') -Configuration $Configuration
    Write-Host ""
    Write-Host "Build succeeded."
    Write-Host "  Visual Studio 2022/2026 + SSMS 22 (2025, x64): src\SmartInput.VisualStudio\bin\$Configuration\SmartInput.VisualStudio.vsix"
    Write-Host "  SSMS 18/19/20 (32-bit) flat payload          : src\SmartInput.Ssms.Legacy\bin\$Configuration\"
    Write-Host "Deploy (run as administrator):"
    Write-Host "  SSMS 22       : tools\Deploy-SSMS22.ps1"
    Write-Host "  SSMS 18/19/20 : tools\Deploy-SSMS-Legacy.ps1"
    Write-Host 'The extension was not installed, VS/SSMS was not launched, and system input-method settings were not changed.'
}
finally { Pop-Location }
