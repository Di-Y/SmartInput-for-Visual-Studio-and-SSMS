<#
.SYNOPSIS
    将 Smart Input 手动部署到 SQL Server Management Studio 22（即 SSMS 2025，64 位）。

.DESCRIPTION
    SSMS 18 及更高版本不运行 VSIXInstaller，第三方扩展需要把文件平铺到
    Common7\IDE\Extensions 下的独立子目录，并清理 MEF / 私有注册表缓存后才会被发现。
    本脚本把现代包（VSSDK 17，x64）构建出的 .vsix（本质是 zip）解压并平铺为
    SSMS 22 所需的文件，然后清理缓存。

    部署到 Program Files 需要管理员权限。请用“以管理员身份运行”的 PowerShell 执行：
        powershell -ExecutionPolicy Bypass -File .\Deploy-SSMS22.ps1

.PARAMETER SsmsIdeDir
    SSMS 22 的 Common7\IDE 目录。默认自动探测常见安装位置。

.PARAMETER VsixPath
    现代包 VSIX 路径。默认使用 src\SmartInput.VisualStudio\bin\Release 下的产物。

.PARAMETER ExtensionName
    Extensions 下的子目录名，默认 SmartInput。

.PARAMETER Uninstall
    删除已部署的扩展并清理缓存。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Deploy-SSMS22.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Deploy-SSMS22.ps1 -Uninstall
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$SsmsIdeDir,
    [string]$VsixPath,
    [string]$ExtensionName = 'SmartInput',
    [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw '部署到 Program Files 需要管理员权限。请用“以管理员身份运行”的 PowerShell 重新执行本脚本。'
    }
}

function Find-Ssms22IdeDir {
    $candidates = @(
        Join-Path ${env:ProgramFiles} 'Microsoft SQL Server Management Studio\22\Release\Common7\IDE',
        Join-Path ${env:ProgramFiles} 'Microsoft SQL Server Management Studio\22\Common7\IDE'
    )
    foreach ($candidate in $candidates) {
        if (Test-Path (Join-Path $candidate 'Extensions')) { return $candidate }
    }
    return $null
}

function Assert-SsmsClosed {
    $processes = Get-Process -Name 'ssms','SsmsApp' -ErrorAction SilentlyContinue
    if ($processes) {
        throw '检测到 SSMS 正在运行。请先完全关闭 SSMS（包括查询窗口），再执行部署。'
    }
}

function Clear-Ssms22Cache {
    # SSMS 22 的私有注册表与 MEF 组件缓存按版本目录存放。
    $roots = @(Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Microsoft\SSMS') -Directory -Filter '22.0_*' -ErrorAction SilentlyContinue)
    foreach ($root in $roots) {
        foreach ($name in @('privateregistry.bin', 'privateregistry.bin.LOG1', 'privateregistry.bin.LOG2')) {
            $file = Join-Path $root.FullName $name
            if (Test-Path $file) {
                Write-Host "删除私有注册表缓存: $file"
                Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
            }
        }
        $cache = Join-Path $root.FullName 'ComponentModelCache'
        if (Test-Path $cache) {
            Write-Host "清理 MEF 组件缓存: $cache"
            Remove-Item -LiteralPath $cache -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Assert-Administrator
Assert-SsmsClosed

if (-not $SsmsIdeDir) { $SsmsIdeDir = Find-Ssms22IdeDir }
if (-not $SsmsIdeDir -or -not (Test-Path $SsmsIdeDir)) {
    throw '未能自动定位 SSMS 22 的 Common7\IDE 目录，请用 -SsmsIdeDir 显式指定。'
}
$extensionsDir = Join-Path $SsmsIdeDir 'Extensions'
$targetDir = Join-Path $extensionsDir $ExtensionName
Write-Host "SSMS IDE 目录 : $SsmsIdeDir"
Write-Host "扩展目标目录 : $targetDir"

if ($Uninstall) {
    if (Test-Path $targetDir) {
        if ($PSCmdlet.ShouldProcess($targetDir, '删除扩展目录')) { Remove-Item -LiteralPath $targetDir -Recurse -Force }
        Write-Host '已删除扩展目录。'
    } else {
        Write-Host '未发现已部署的扩展目录，无需删除。'
    }
    Clear-Ssms22Cache
    Write-Host '卸载完成。下次启动 SSMS 即生效。'
    return
}

if (-not $VsixPath) {
    $workspace = Split-Path -Parent $PSScriptRoot
    $VsixPath = Join-Path $workspace 'src\SmartInput.VisualStudio\bin\Release\SmartInput.VisualStudio.vsix'
}
if (-not (Test-Path $VsixPath)) { throw "找不到 VSIX：$VsixPath；请先运行 build.ps1 完成构建。" }

# SSMS 22 需要平铺的文件（VSIX 本质为 zip，根目录已平铺，Asset Path 为实际文件名）。
$requiredFiles = @(
    'SmartInput.VisualStudio.dll',
    'SmartInput.Core.dll',
    'SmartInput.VisualStudio.pkgdef',
    'extension.vsixmanifest',
    'manifest.json',
    'catalog.json'
)

Add-Type -AssemblyName System.IO.Compression.FileSystem
$staging = Join-Path ([System.IO.Path]::GetTempPath()) ('smartinput-ssms22-' + [Guid]::NewGuid().ToString('N'))
try {
    if ($PSCmdlet.ShouldProcess($staging, '解压 VSIX 到临时目录')) {
        New-Item -ItemType Directory -Path $staging -Force | Out-Null
        [System.IO.Compression.ZipFile]::ExtractToDirectory($VsixPath, $staging)
    }
    foreach ($name in $requiredFiles) {
        if (-not (Test-Path (Join-Path $staging $name))) { throw "VSIX 中缺少部署所需文件: $name" }
    }

    if ($PSCmdlet.ShouldProcess($targetDir, '重建扩展目录')) {
        if (Test-Path $targetDir) { Remove-Item -LiteralPath $targetDir -Recurse -Force }
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        foreach ($name in $requiredFiles) {
            Copy-Item -LiteralPath (Join-Path $staging $name) -Destination (Join-Path $targetDir $name) -Force
        }
        # Strip Mark-of-the-Web if the build folder inherited it (SSMS refuses network-sourced DLLs).
        Get-ChildItem $targetDir -Recurse | Unblock-File
    }
    Write-Host '已平铺以下文件：'
    $requiredFiles | ForEach-Object { Write-Host "  $_" }
}
finally {
    if (Test-Path $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
}

Clear-Ssms22Cache

# 通知 SSMS 扩展目录发生变化，触发重新扫描。
$signal = Join-Path $extensionsDir 'extensions.configurationchanged'
if ($PSCmdlet.ShouldProcess($signal, '写入扩展变更标记')) {
    New-Item -ItemType File -Path $signal -Force | Out-Null
    (Get-Item $signal).LastWriteTime = Get-Date
}

Write-Host ''
Write-Host '部署完成。请启动 SSMS 22 并打开一个 .sql 查询窗口验证：'
Write-Host '  - 代码 / [标识符] / "标识符" 区域应为英文；'
Write-Host '  - -- 注释、/* 块注释 */ 与含汉字的字符串应为中文；'
Write-Host '  - “工具”菜单应出现 Smart Input 暂停命令。'
