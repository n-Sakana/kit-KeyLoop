# KeyLoop -- send a key at intervals while the PC has no input.
param(
    [string]$Idle = '',
    [string]$MaxRun = '',
    [string]$Key = '',
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest = @()
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# Loads the screens and send loop from KeyLoop.cs. Compiling takes about 1 s, so the DLL is
# cached under %LOCALAPPDATA%\KeyLoop, one file per source version. Nothing here calls a cmdlet
# on the cached path: autoloading cmdlet modules adds about 0.4 s.
function Import-KeyLoop {
    if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
        throw 'PowerShell is running in Constrained Language mode, so KeyLoop cannot start.'
    }
    $source = [IO.File]::ReadAllText([IO.Path]::Combine($PSScriptRoot, 'KeyLoop.cs'))
    $hash = [Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($source))
    $dir = [IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'), 'KeyLoop')
    $dll = [IO.Path]::Combine($dir, 'KeyLoop-' + [BitConverter]::ToString($hash, 0, 8).Replace('-', '') + '.dll')
    try {
        if ([IO.File]::Exists($dll)) { [void][Reflection.Assembly]::LoadFile($dll); return }
    }
    catch { try { [IO.File]::Delete($dll) } catch { } }   # damaged cache: rebuild it
    try {
        [void][IO.Directory]::CreateDirectory($dir)
        $temp = $dll + '.' + $PID + '.tmp'
        Add-Type -TypeDefinition $source -OutputAssembly $temp -OutputType Library
        try { [IO.File]::Move($temp, $dll) } catch { [IO.File]::Delete($temp) }   # another launch got there first
        foreach ($old in [IO.Directory]::GetFiles($dir, 'KeyLoop-*.dll')) {
            if ($old -ne $dll) { try { [IO.File]::Delete($old) } catch { } }   # in use by a running KeyLoop
        }
        [void][Reflection.Assembly]::LoadFile($dll)
    }
    catch {
        # The cache is not writable: compile in memory instead.
        Add-Type -TypeDefinition $source
    }
}

# Keeps the window open so the reason stays readable when launched from the menu.
# Exit code 2 tells KeyLoop.cmd that the error was already shown.
function Show-Failure($ErrorRecord) {
    $e = $ErrorRecord.Exception
    while ($e -is [Management.Automation.MethodInvocationException] -and $null -ne $e.InnerException) { $e = $e.InnerException }
    try {
        [Console]::ResetColor()
        [Console]::WriteLine()
        [Console]::ForegroundColor = 'Red'
        [Console]::WriteLine('  Error: ' + $e.Message)
        [Console]::ResetColor()
        [Console]::WriteLine()
        [Console]::WriteLine('  Press any key to close.')
        while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) }
        [void][Console]::ReadKey($true)
    }
    catch { }
}

try {
    if (@($Rest).Count -gt 0) { throw ('Unknown argument: ' + ($Rest -join ' ')) }
    Import-KeyLoop
    [KeyLoop.App]::Run($Idle, $MaxRun, $Key)
}
catch {
    Show-Failure $_
    exit 2
}
exit 0
