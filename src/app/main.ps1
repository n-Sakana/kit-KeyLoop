# KeyLoop -- send a harmless key while idle (keep the session awake).
param(
    [string]$Target = "$PWD",
    [int]$Idle = 0,
    [int]$MaxRun = -1,
    [string]$Key = ""
)
. (Join-Path $PSScriptRoot "..\..\common\ui.ps1")

function ConvertTo-KeyByte {
    param([string]$Text)
    $hex = $Text -replace '^0x', ''
    if ($hex -notmatch '^[0-9A-Fa-f]{1,2}$') { throw "invalid key" }
    return [Convert]::ToByte($hex, 16)
}

[byte]$KeyByte = 0
if ($Key -ne "") {
    try { $KeyByte = ConvertTo-KeyByte $Key }
    catch { Write-Err "Invalid key code: $Key"; exit 1 }
}

if (-not ("Native" -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Native {
    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LASTINPUTINFO lii);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    public const uint KEYEVENTF_KEYUP = 0x0002;
    public static uint IdleMs() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(lii);
        GetLastInputInfo(ref lii);
        unchecked { return (uint)Environment.TickCount - lii.dwTime; }
    }
    public static void SendKey(byte vk) {
        keybd_event(vk, 0, 0, UIntPtr.Zero);
        keybd_event(vk, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }
}
"@
}

$Host.UI.RawUI.WindowTitle = "KeyLoop"
Start-UI -Title "KeyLoop"

# Interactive fallback (Custom / no-arg launch)
if ($Idle -le 0) {
    $Idle = Read-Int -Prompt "Idle threshold (sec)" -Default 120
}
if ($MaxRun -lt 0) {
    $MaxRun = Read-Int -Prompt "Max runtime (sec, 0=unlimited)" -Default 0
}
if ($KeyByte -eq 0) {
    $opts = @("None-key 0x07 (safe, no side effect)", "F15 0x7E", "ScrollLock 0x91", "Enter code manually")
    $sel = Read-Choice -Prompt "Key to send" -Options $opts -DefaultIndex 0
    switch ($sel) {
        $opts[0] { $KeyByte = 0x07 }
        $opts[1] { $KeyByte = 0x7E }
        $opts[2] { $KeyByte = 0x91 }
        $opts[3] {
            $hex = Read-Value -Prompt "Virtual key code (e.g. 0x07)" -Default "0x07"
            try { $KeyByte = ConvertTo-KeyByte $hex }
            catch { Write-Warn "Invalid key code; using 0x07."; $KeyByte = 0x07 }
        }
    }
}

$runStr = if ($MaxRun -gt 0) { "$MaxRun`s" } else { "unlimited" }
Write-Dim ("Key=0x{0:X2}  Idle>={1}s  MaxRun={2}  (Ctrl+C to stop)" -f $KeyByte, $Idle, $runStr)
Write-Host ""

$threshMs  = [uint32]($Idle * 1000)
$startTick = [Environment]::TickCount
$lastSend  = $startTick - [int]$threshMs
$count     = 0

try {
    while ($true) {
        if ($MaxRun -gt 0) {
            $runSec = ([Environment]::TickCount - $startTick) / 1000
            if ($runSec -ge $MaxRun) {
                Write-Ok ("Max runtime reached ({0}s)" -f $MaxRun)
                break
            }
        }

        $idleMs  = [Native]::IdleMs()
        $sinceMs = [Environment]::TickCount - $lastSend

        if ($idleMs -ge $threshMs -and $sinceMs -ge $threshMs) {
            [Native]::SendKey($KeyByte)
            $lastSend = [Environment]::TickCount
            $count++
            Write-Step ("Sent 0x{0:X2} (total={1})" -f $KeyByte, $count)
        }

        Start-Sleep -Seconds 1
    }
}
finally {
    Stop-UI
    Write-Dim ("Total sent: {0}" -f $count)
}
