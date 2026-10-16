# Explorer and desktop background context menu support.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:StandaloneRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$script:App = [IO.File]::ReadAllText((Join-Path $script:StandaloneRoot 'app.json')) | ConvertFrom-Json
if ($script:App.Id -ne 'KeyLoop') { throw 'Unknown standalone application.' }

function Get-MenuPlan {
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $entry = Join-Path $script:StandaloneRoot 'src\app\main.ps1'
    $baseCommand = '"{0}" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "{1}"' -f $powershell, $entry
    $command = ''
    $children = @(
        [pscustomobject]@{ Id = '01-default'; Label = 'Default'; Command = $baseCommand + ' -Key 0x07 -Idle 120 -MaxRun 0' },
        [pscustomobject]@{ Id = '02-custom'; Label = 'Custom...'; Command = $baseCommand }
    )
    # This menu has one option level; every option consumes one row.
    if ($children.Count -gt 16) { throw 'A submenu must contain at most 16 rows.' }
    # Use the same canonical verb in both background classes. No selection is passed.
    foreach ($context in @('Software\Classes\Directory\Background\shell', 'Software\Classes\DesktopBackground\shell')) {
        [pscustomobject]@{
            Path = $context + '\' + $script:App.MenuKey
            Label = $script:App.Name
            Command = $command
            Children = $children
        }
    }
}

function Set-MenuString {
    param($Key, [string]$Name, [string]$Value)
    $Key.SetValue($Name, $Value, [Microsoft.Win32.RegistryValueKind]::String)
}

function Send-MenuChanged {
    if (-not ('StandaloneMenuNotify' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class StandaloneMenuNotify {
    [DllImport("shell32.dll")]
    public static extern void SHChangeNotify(uint eventId, uint flags, IntPtr item1, IntPtr item2);
}
'@
    }
    [StandaloneMenuNotify]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
}

function Install-StandaloneMenu {
    if ($env:OS -ne 'Windows_NT') { throw 'Windows is required.' }
    $entry = Join-Path $script:StandaloneRoot 'src\app\main.ps1'
    if (-not [IO.File]::Exists($entry)) { throw ('Application entry not found: ' + $entry) }
    if (-not [IO.File]::Exists((Join-Path $script:StandaloneRoot 'common\ui.ps1'))) {
        throw 'The local KeyLoop UI helper is missing.'
    }
    foreach ($item in @(Get-MenuPlan)) {
        # Delete only this application's canonical verb, never the containing shell key.
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($item.Path, $false)
        $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($item.Path)
        try {
            Set-MenuString $key 'MUIVerb' $item.Label
            Set-MenuString $key 'InstallRoot' $script:StandaloneRoot
            if (@($item.Children).Count -gt 0) {
                Set-MenuString $key 'SubCommands' ''
                foreach ($child in $item.Children) {
                    $childKey = $key.CreateSubKey('shell\' + $child.Id)
                    try {
                        Set-MenuString $childKey 'MUIVerb' $child.Label
                        $commandKey = $childKey.CreateSubKey('command')
                        try { Set-MenuString $commandKey '' $child.Command } finally { $commandKey.Dispose() }
                    }
                    finally { $childKey.Dispose() }
                }
            }
            else {
                $commandKey = $key.CreateSubKey('command')
                try { Set-MenuString $commandKey '' $item.Command } finally { $commandKey.Dispose() }
            }
        }
        finally { $key.Dispose() }
    }
    Send-MenuChanged
    Write-Host ($script:App.Name + ': installed for Explorer background and desktop background (current user).')
}

function Uninstall-StandaloneMenu {
    foreach ($item in @(Get-MenuPlan)) {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($item.Path)
        if ($null -eq $key) { continue }
        try { $owner = [string]$key.GetValue('InstallRoot', '') } finally { $key.Dispose() }
        # An uninstaller from an old/moved copy must not remove a newer installation.
        if (-not [string]::Equals($owner, $script:StandaloneRoot, [StringComparison]::OrdinalIgnoreCase)) {
            Write-Warning ('Not owned by this copy; left unchanged: HKCU\' + $item.Path)
            continue
        }
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($item.Path, $false)
    }
    Send-MenuChanged
    Write-Host ($script:App.Name + ': menu removal finished. Application files and output were not deleted.')
}
