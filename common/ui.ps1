# common/ui.ps1 -- shared UI helpers (ASCII only)
# Console UI + interactive input + shared file logging + output path helper.

$script:UI = @{
    Head = "Cyan"; Step = "White"; Ok = "Green"
    Warn = "Yellow"; Err = "Red"; Dim = "DarkGray"; Spin = "Cyan"
}
$script:UIState = @{ Total = 0; Index = 0; StartTime = $null; Title = "" }
$script:LogPath = ""

# ---- Session ----
function Start-UI {
    param([string]$Title, [int]$Total = 0)
    $script:UIState.Title = $Title
    $script:UIState.Total = $Total
    $script:UIState.Index = 0
    $script:UIState.StartTime = Get-Date
    Write-Host ""
    Write-Host ("=== {0} ===" -f $Title) -ForegroundColor $script:UI.Head
    Write-Host ""
}
function Stop-UI {
    param([string]$OutPath = "")
    $elapsed = 0.0
    if ($script:UIState.StartTime) {
        $elapsed = ((Get-Date) - $script:UIState.StartTime).TotalSeconds
    }
    Write-Host ""
    if ($OutPath) { Write-Host ("Output: {0}" -f $OutPath) -ForegroundColor $script:UI.Ok }
    if ($script:LogPath) { Write-Host ("Log:    {0}" -f $script:LogPath) -ForegroundColor $script:UI.Dim }
    Write-Host ("Finished in {0:N1}s" -f $elapsed) -ForegroundColor $script:UI.Dim
}

# ---- Steps ----
function Write-Step {
    param([string]$Msg)
    $script:UIState.Index++
    if ($script:UIState.Total -gt 0) {
        Write-Host ("[{0}/{1}] {2}" -f $script:UIState.Index, $script:UIState.Total, $Msg) -ForegroundColor $script:UI.Step
    } else {
        Write-Host ("- {0}" -f $Msg) -ForegroundColor $script:UI.Step
    }
}
function Write-Ok   { param([string]$Msg) Write-Host ("  OK   {0}" -f $Msg) -ForegroundColor $script:UI.Ok }
function Write-Warn { param([string]$Msg) Write-Host ("  WARN {0}" -f $Msg) -ForegroundColor $script:UI.Warn }
function Write-Err  { param([string]$Msg) Write-Host ("  ERR  {0}" -f $Msg) -ForegroundColor $script:UI.Err }
function Write-Dim  { param([string]$Msg) Write-Host ("       {0}" -f $Msg) -ForegroundColor $script:UI.Dim }

# ---- Progress ----
function Show-Progress {
    param([string]$Activity, [int]$Current, [int]$Total, [string]$Status = "")
    if ($Total -le 0) { return }
    $pct = [math]::Min(100, [int](($Current / $Total) * 100))
    Write-Progress -Activity $Activity -Status ("{0} ({1}/{2})" -f $Status, $Current, $Total) -PercentComplete $pct
}
function Clear-Progress {
    param([string]$Activity = "Done")
    Write-Progress -Activity $Activity -Completed
}

# ---- Spinner (manual) ----
$script:SpinFrames = @('|','/','-','\')
$script:SpinIndex = 0
$script:SpinStart = $null
$script:SpinMsg = ""
function Start-Spinner {
    param([string]$Message)
    $script:SpinIndex = 0
    $script:SpinStart = [System.Diagnostics.Stopwatch]::StartNew()
    $script:SpinMsg = $Message
}
function Tick-Spinner {
    $f = $script:SpinFrames[$script:SpinIndex % $script:SpinFrames.Count]
    $sec = if ($script:SpinStart) { $script:SpinStart.Elapsed.TotalSeconds } else { 0 }
    Write-Host ("`r  {0} {1} ({2:N1}s)" -f $f, $script:SpinMsg, $sec) -NoNewline -ForegroundColor $script:UI.Spin
    $script:SpinIndex++
}
function End-Spinner {
    param([string]$FinalMsg = "")
    $sec = if ($script:SpinStart) { $script:SpinStart.Elapsed.TotalSeconds } else { 0 }
    $msg = if ($FinalMsg) { $FinalMsg } else { $script:SpinMsg }
    Write-Host ("`r  OK   {0} ({1:N1}s){2}" -f $msg, $sec, (' ' * 10)) -ForegroundColor $script:UI.Ok
    if ($script:SpinStart) { $script:SpinStart.Stop() }
}

# ---- Input helpers ----
function Read-Value {
    param([string]$Prompt, [string]$Default = "")
    $hint = if ($Default -ne "") { " [$Default]" } else { "" }
    Write-Host ("  ? {0}{1}: " -f $Prompt, $hint) -ForegroundColor $script:UI.Step -NoNewline
    $inp = Read-Host
    if ([string]::IsNullOrWhiteSpace($inp)) { return $Default }
    return $inp
}
function Read-Int {
    param([string]$Prompt, [int]$Default)
    while ($true) {
        $v = Read-Value -Prompt $Prompt -Default "$Default"
        $n = 0
        if ([int]::TryParse($v, [ref]$n)) { return $n }
        Write-Warn "Enter a number."
    }
}
function Read-Choice {
    param([string]$Prompt, [string[]]$Options, [int]$DefaultIndex = 0)
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $mark = if ($i -eq $DefaultIndex) { "*" } else { " " }
        Write-Host ("   {0} [{1}] {2}" -f $mark, $i, $Options[$i]) -ForegroundColor $script:UI.Dim
    }
    $sel = Read-Int -Prompt $Prompt -Default $DefaultIndex
    if ($sel -ge 0 -and $sel -lt $Options.Count) { return $Options[$sel] }
    return $Options[$DefaultIndex]
}
function Confirm-Yes {
    param([string]$Prompt, [bool]$Default = $true)
    $def = if ($Default) { "Y/n" } else { "y/N" }
    Write-Host ("  ? {0} [{1}]: " -f $Prompt, $def) -ForegroundColor $script:UI.Step -NoNewline
    $inp = Read-Host
    if ([string]::IsNullOrWhiteSpace($inp)) { return $Default }
    return ($inp -match '^[Yy]')
}

