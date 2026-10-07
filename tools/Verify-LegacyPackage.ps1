param([ValidateSet('Debug', 'Release')][string]$Configuration = 'Release')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Verifies the 32-bit SSMS 18/19/20 (VSSDK 15) payload that Deploy-SSMS-Legacy.ps1 flattens.
$root = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $root "src\SmartInput.Ssms.Legacy\bin\$Configuration"
$required = @(
    'SmartInput.VisualStudio.dll',
    'SmartInput.Core.dll',
    'SmartInput.VisualStudio.pkgdef',
    'extension.vsixmanifest'
)
foreach ($name in $required) {
    if (-not (Test-Path (Join-Path $dir $name))) { throw "Legacy payload is missing: $name" }
}

# 1) The package DLL must bind to the VS 2017 shell's 15.x reference assemblies (never 16/17),
#    otherwise the 32-bit SSMS shell cannot resolve them at load time.
$dll = Join-Path $dir 'SmartInput.VisualStudio.dll'
$asm = [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($dll)
$wrong = @($asm.GetReferencedAssemblies() |
    Where-Object { $_.Name -like 'Microsoft.VisualStudio.*' -and $_.Version.Major -ne 15 })
if ($wrong.Count -gt 0) {
    throw ('Legacy package references non-VSSDK15 assemblies: ' +
        (($wrong | ForEach-Object { "$($_.Name) $($_.Version)" }) -join ', '))
}

# 2) It must be pure MSIL (AnyCPU) so the 32-bit isolated shell can load it.
$module = $asm.GetModules()[0]
[System.Reflection.PortableExecutableKinds]$pe = [System.Reflection.PortableExecutableKinds]::NotAPortableExecutableImage
[System.Reflection.ImageFileMachine]$machine = [System.Reflection.ImageFileMachine]::I386
$module.GetPEKind([ref]$pe, [ref]$machine)
if (-not ($pe -band [System.Reflection.PortableExecutableKinds]::ILOnly)) {
    throw "Legacy package is not ILOnly/AnyCPU (PEKind=$pe)."
}

# 3) pkgdef registers the package, points at our DLL, and auto-loads at shell startup.
$pkgdef = Get-Content -LiteralPath (Join-Path $dir 'SmartInput.VisualStudio.pkgdef') -Raw
foreach ($need in @(
    '[$RootKey$\Packages\{a11d90fc-8f3d-493a-a227-d7a59c26eae8}]',
    '"CodeBase"="$PackageFolder$\SmartInput.VisualStudio.dll"',
    '[$RootKey$\AutoLoadPackages\{adfc4e64-0397-11d1-9f4e-00a0c911004f}]'
)) {
    if (-not $pkgdef.Contains($need)) { throw "Legacy pkgdef is missing: $need" }
}

# 4) v1 (2010) manifest targets the ssms isolated shell and exposes the MEF editor component.
$manifest = Get-Content -LiteralPath (Join-Path $dir 'extension.vsixmanifest') -Raw
foreach ($need in @(
    '<IsolatedShell Version="1.0">ssms</IsolatedShell>',
    '<MefComponent>SmartInput.VisualStudio.dll</MefComponent>',
    '<VsPackage>SmartInput.VisualStudio.pkgdef</VsPackage>'
)) {
    if (-not $manifest.Contains($need)) { throw "Legacy v1 manifest is missing: $need" }
}

$vsAssemblies = @($asm.GetReferencedAssemblies() |
    Where-Object { $_.Name -like 'Microsoft.VisualStudio.*' } |
    ForEach-Object { "$($_.Name) $($_.Version)" })
Write-Host "PASS Legacy SSMS 18-20 payload: AnyCPU, VSSDK 15 bindings, pkgdef, v1 manifest ($($required.Count) files)"
$vsAssemblies | Sort-Object | ForEach-Object { Write-Host "  ref $_" }
