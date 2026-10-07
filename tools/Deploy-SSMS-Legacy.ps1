<#
.SYNOPSIS
    将 Smart Input 手动部署到 32 位的 SQL Server Management Studio 18 / 19 / 20（即“SSMS 2022”这一代）。

.DESCRIPTION
    SSMS 18、19、20 基于 Visual Studio 2017 独立 Shell（VSSDK 15，32 位），不运行 VSIXInstaller。
    需要把为 VSSDK 15 编译的 AnyCPU 程序集、手写的 .pkgdef 与 v1(2010) 清单平铺到
    Common7\IDE\Extensions 下的独立子目录，并清理私有注册表 / MEF 缓存后才会被发现。

    本脚本部署的文件来自 src\SmartInput.Ssms.Legacy\bin\Release（请先运行 build.ps1）。
    SSMS 22（2025，64 位）请改用 Deploy-SSMS22.ps1。

    部署到 Program Files (x86) 需要管理员权限，请用“以管理员身份运行”的 PowerShell 执行：
        powershell -ExecutionPolicy Bypass -File .\Deploy-SSMS-Legacy.ps1

.PARAMETER Version
    要部署的 SSMS 主版本：18、19、20 或 All（默认 All，自动部署到所有检测到的版本）。

.PARAMETER Uninstall
    删除已部署扩展并清理缓存。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Deploy-SSMS-Legacy.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Deploy-SSMS-Legacy.ps1 -Version 20
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Deploy-SSMS-Legacy.ps1 -Uninstall
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('18', '19', '20', 'All')]
    [string]$Version = 'All',
    [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExtensionName = 'SmartInput'
$ProgramFilesX86 = ${env:ProgramFiles(x86)}
if (-not $ProgramFilesX86) { $ProgramFilesX86 = 'C:\Program Files (x86)' }

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw '部署到 Program Files (x86) 需要管理员权限。请用“以管理员身份运行”的 PowerShell 重新执行本脚本。'
    }
}

function Assert-SsmsClosed {
    $processes = Get-Process -Name 'ssms','SsmsApp' -ErrorAction SilentlyContinue
    if ($processes) {
        throw '检测到 SSMS 正在运行。请先完全关闭 SSMS（包括查询窗口），再执行部署。'
    }
}

function Get-LegacyCatalog {
    $all = @('18', '19', '20')
    $versions = if ($Version -eq 'All') { $all } else { @($Version) }
    foreach ($major in $versions) {
        $ide = Join-Path $ProgramFilesX86 "Microsoft SQL Server Management Studio\$major\Common7\IDE"
        [pscustomobject]@{
            Major       = $major
            IdePath     = $ide
            Present     = Test-Path (Join-Path $ide 'Extensions')
            DataBase    = Join-Path $env:LOCALAPPDATA 'Microsoft\SQL Server Management Studio'
            DataPattern = "^$major\."
        }
    }
}

function Clear-LegacyCache {
    param([string]$DataBase, [string]$DataPattern, [string]$IdePath)
    if (Test-Path $DataBase) {
        $dataDir = Get-ChildItem $DataBase -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match $DataPattern } | Select-Object -First 1
        if ($dataDir) {
            foreach ($f in @('privateregistry.bin', 'privateregistry.bin.LOG1', 'privateregistry.bin.LOG2')) {
                $p = Join-Path $dataDir.FullName $f
                if (Test-Path $p) { Write-Host "  删除缓存: $p"; Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
            }
            $cache = Join-Path $dataDir.FullName 'ComponentModelCache'
            if (Test-Path $cache) { Write-Host "  清理 MEF 缓存: $cache"; Remove-Item -LiteralPath $cache -Recurse -Force -ErrorAction SilentlyContinue }
            '' | Set-Content (Join-Path $dataDir.FullName 'extensions.configurationchanged') -Force -ErrorAction SilentlyContinue
        }
    }
    $signal = Join-Path $IdePath "Extensions\extensions.configurationchanged"
    '' | Set-Content $signal -Force -ErrorAction SilentlyContinue
}

Assert-Administrator
Assert-SsmsClosed

$catalog = @(Get-LegacyCatalog | Where-Object { $_.Present })
if ($catalog.Count -eq 0) {
    throw "未在 $ProgramFilesX86 下找到 SSMS 18/19/20 安装。若安装在其它位置，请手动复制 src\SmartInput.Ssms.Legacy\bin\Release 下的文件到对应 Common7\IDE\Extensions\$ExtensionName。"
}

# Files to flatten (SSMS 18-20 needs the assembly(ies), a .pkgdef and a v1 extension.vsixmanifest).
$sourceDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\SmartInput.Ssms.Legacy\bin\Release'
$requiredFiles = @(
    'SmartInput.VisualStudio.dll',
    'SmartInput.Core.dll',
    'SmartInput.VisualStudio.pkgdef',
    'extension.vsixmanifest'
)
if (-not $Uninstall) {
    foreach ($name in $requiredFiles) {
        if (-not (Test-Path (Join-Path $sourceDir $name))) { throw "缺少部署文件: $name（请先运行 build.ps1 完成 Legacy 构建）。" }
    }
}

foreach ($entry in $catalog) {
    $targetDir = Join-Path $entry.IdePath "Extensions\$ExtensionName"
    Write-Host ""
    Write-Host "=== SSMS $($entry.Major) -> $targetDir ==="

    if ($Uninstall) {
        if (Test-Path $targetDir) {
            if ($PSCmdlet.ShouldProcess($targetDir, '删除扩展目录')) { Remove-Item -LiteralPath $targetDir -Recurse -Force }
            Write-Host '  已删除扩展目录。'
        } else { Write-Host '  未发现已部署扩展，跳过。' }
        Clear-LegacyCache -DataBase $entry.DataBase -DataPattern $entry.DataPattern -IdePath $entry.IdePath
        continue
    }

    if ($PSCmdlet.ShouldProcess($targetDir, '重建扩展目录并平铺文件')) {
        if (Test-Path $targetDir) { Remove-Item -LiteralPath $targetDir -Recurse -Force }
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        foreach ($name in $requiredFiles) {
            Copy-Item -LiteralPath (Join-Path $sourceDir $name) -Destination (Join-Path $targetDir $name) -Force
        }
        # Strip Mark-of-the-Web in case the build folder inherited it (SSMS refuses network-sourced DLLs).
        Get-ChildItem $targetDir -Recurse | Unblock-File
    }
    $requiredFiles | ForEach-Object { Write-Host "  平铺: $_" }
    Clear-LegacyCache -DataBase $entry.DataBase -DataPattern $entry.DataPattern -IdePath $entry.IdePath
}

Write-Host ""
if ($Uninstall) {
    Write-Host '卸载完成。下次启动 SSMS 即生效。'
} else {
    Write-Host '部署完成。请启动 SSMS 并打开一个 .sql 查询窗口验证：'
    Write-Host '  - 代码 / [标识符] / "标识符" 区域应为英文；'
    Write-Host '  - -- 注释、/* 块注释 */ 与含汉字的字符串应为中文；'
    Write-Host '  - 编辑器底部状态栏可见 “Smart Input · …”，单击可暂停/恢复。'
    Write-Host '注：SSMS 2018-2022 这一代不提供“工具”菜单暂停命令，请使用底部状态栏按钮或选项页。'
}
