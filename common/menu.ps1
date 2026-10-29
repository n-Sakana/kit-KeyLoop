# Explorer and desktop background context menu support.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:StandaloneRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$script:App = [IO.File]::ReadAllText((Join-Path $script:StandaloneRoot 'app.json')) | ConvertFrom-Json
if ($script:App.Id -ne 'KeyLoop') { throw 'Unknown standalone application.' }

function Get-MenuPlan {
    # conhost.exe opens the classic console window even where Windows Terminal is the default
    # terminal; only that window can be shrunk to the KeyLoop screen.
    $conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $entry = Join-Path $script:StandaloneRoot 'src\app\main.ps1'
    $baseCommand = '"{0}" "{1}" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "{2}"' -f $conhost, $powershell, $entry
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
    foreach ($file in @($entry, (Join-Path $script:StandaloneRoot 'src\app\KeyLoop.cs'))) {
        if (-not [IO.File]::Exists($file)) { throw ('KeyLoop file not found: ' + $file) }
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
}
