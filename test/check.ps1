[CmdletBinding()]
param([switch]$Registry)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
function Assert-True([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }
foreach ($file in Get-ChildItem -LiteralPath $root -Filter '*.ps1' -Recurse -File) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    Assert-True (@($errors).Count -eq 0) ('Parse errors in ' + $file.FullName + ': ' + ($errors | Out-String))
}
. (Join-Path $root 'common\menu.ps1')
Assert-True ($script:App.Id -ceq 'KeyLoop') 'Internal application name must be KeyLoop.'
Assert-True ($script:App.Name -ceq 'KeyLoop') 'Display name must be KeyLoop.'
Assert-True ($script:App.MenuKey -ceq 'KeyLoop') 'Registry verb must be KeyLoop.'
Assert-True ([IO.File]::Exists((Join-Path $root 'KeyLoop.cmd'))) 'KeyLoop launcher is missing.'
$plan = @(Get-MenuPlan)
Assert-True ($plan.Count -eq 2) 'Exactly two background contexts are required.'
$expected = @('Software\Classes\Directory\Background\shell\', 'Software\Classes\DesktopBackground\shell\')
for ($i = 0; $i -lt 2; $i++) {
    Assert-True ($plan[$i].Path -eq ($expected[$i] + $script:App.MenuKey)) 'Unexpected context registration.'
    Assert-True ($plan[$i].Label -ceq 'KeyLoop') 'Wrong menu label.'
    Assert-True ($plan[$i].Children.Count -le 16) 'Submenu exceeds 16 rows.'
    $commands = @($plan[$i].Command) + @($plan[$i].Children | ForEach-Object { $_.Command })
    foreach ($command in $commands) {
        Assert-True ($command -notmatch '%[1Vv]') 'A background-only tool must not consume a selected target.'
        if ($command) { Assert-True ($command.StartsWith('"')) 'Executable must be quoted.' }
    }
}
$entry = Join-Path $root 'src\app\main.ps1'
Assert-True ([IO.File]::Exists($entry)) 'Standalone entry is missing.'
$source = Join-Path $root 'src\app\KeyLoop.cs'
Assert-True ([IO.File]::Exists($source)) 'KeyLoop.cs is missing.'
Assert-True ($plan[0].Children.Count -eq 2) 'Default and Custom actions must be preserved.'
Assert-True ($plan[0].Children[0].Command.EndsWith('-Key 0x07 -Idle 120 -MaxRun 0')) 'Default arguments changed.'
Assert-True ($plan[0].Children[0].Command.Contains('-STA')) 'STA flag is missing.'
foreach ($child in $plan[0].Children) {
    Assert-True ($child.Command.StartsWith('"' + (Join-Path $env:SystemRoot 'System32\conhost.exe') + '" ')) 'The menu must open KeyLoop in conhost.'
}
Write-Output 'STRUCTURE_OK'

# A cached launch must not call cmdlets: autoloading their modules costs about 0.4 s at startup.
# Add-Type runs only when the compiled DLL is not cached yet.
$ast = [System.Management.Automation.Language.Parser]::ParseFile($entry, [ref]$null, [ref]$null)
$defined = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
foreach ($call in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
    $name = $call.GetCommandName()
    Assert-True (($defined -contains $name) -or $name -eq 'Set-StrictMode' -or $name -eq 'Add-Type') ('Startup path calls a cmdlet: ' + $name)
}

# Pure logic in KeyLoop.cs. No key is sent.
Add-Type -TypeDefinition ([IO.File]::ReadAllText($source))
Assert-True ([KeyLoop.Keys]::Parse('0x07') -eq 7) 'Key code 0x07 must parse.'
Assert-True ([KeyLoop.Keys]::Parse('7e') -eq 0x7E) 'Key code without 0x must parse.'
foreach ($bad in @('', '0x00', '0xFF', '0x100', 'zz', '7 e')) {
    $code = 0
    Assert-True (-not [KeyLoop.Keys]::TryParse($bad, [ref]$code)) ('Invalid key code accepted: ' + $bad)
}
Assert-True ([KeyLoop.Settings]::ParseSeconds('120', 1, 'x') -eq 120) 'Seconds must parse.'
foreach ($bad in @('0', '-1', 'abc', '12345678', '')) {
    $value = 0
    Assert-True (-not [KeyLoop.Settings]::TryParseSeconds($bad, 1, [ref]$value)) ('Invalid seconds accepted: ' + $bad)
}
Assert-True ([KeyLoop.Keys]::Format(0x07) -ceq 'Unassigned  0x07') 'Default key label changed.'
Assert-True ([KeyLoop.Keys]::Format(0x7E) -ceq 'F15  0x7E') 'F15 label changed.'
Assert-True ([KeyLoop.Keys]::Format(0xA0) -ceq 'Left Shift  0xA0') 'Left Shift label changed.'
$c = [KeyLoop.Countdown]::Compute(5000, 200000, 120000)
Assert-True ($c.RemainingMs -eq 115000 -and -not $c.Due -and -not $c.Active) 'Countdown from idle time is wrong.'
$c = [KeyLoop.Countdown]::Compute(200000, 30000, 120000)
Assert-True ($c.RemainingMs -eq 90000 -and -not $c.Due) 'Countdown after a send is wrong.'
Assert-True ([KeyLoop.Countdown]::Compute(120000, 120000, 120000).Due) 'Key must be due at the threshold.'
Assert-True ([KeyLoop.Countdown]::Compute(300, 60000, 120000).Active) 'Recent input must show as active.'
Assert-True (-not [KeyLoop.Countdown]::Compute(300, 400, 120000).Active) 'Our own send must not show as active.'
Assert-True ([KeyLoop.Settings]::Clock(3725) -eq '01:02:05') 'Clock format changed.'
Assert-True ([KeyLoop.Ui]::TextWidth([string][char]0x9001 + ' 12') -eq 5) 'Wide characters must count as two cells.'
$lines = @(
    [KeyLoop.Ui]::Join([KeyLoop.Seg]::new('KeyLoop'), [KeyLoop.Ui]::Badge('Key sent', 'White', 'Green')),
    [KeyLoop.Ui]::Join([KeyLoop.Seg]::new('Next send in'), [KeyLoop.Seg]::new('86400 s'))
)
foreach ($line in $lines) {
    $width = 0
    foreach ($s in $line) { $width += [KeyLoop.Ui]::TextWidth($s.Text) }
    Assert-True ($width -eq [KeyLoop.Ui]::Width - 2) 'Right-aligned values must end at the same column.'
}
Write-Output 'LOGIC_OK'
if ($Registry) {
    # Disposable, uniquely named verbs. The real user's app registrations are never touched.
    $script:App.MenuKey += '.Test.' + [Guid]::NewGuid().ToString('N')
    $testKey = $script:App.MenuKey
    $testPlan = @(Get-MenuPlan)
    try {
        Install-StandaloneMenu
        Install-StandaloneMenu
        foreach ($item in $testPlan) {
            $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($item.Path)
            Assert-True ($null -ne $key) 'Install did not create a context.'
            try {
                Assert-True ($key.GetValue('MUIVerb') -ceq 'KeyLoop') 'Wrong registered menu label.'
                Assert-True ($key.GetValue('InstallRoot') -eq $root) 'Wrong install owner.'
                if ($item.Children.Count -gt 0) {
                    foreach ($child in $item.Children) {
                        $commandKey = $key.OpenSubKey('shell\' + $child.Id + '\command')
                        try { Assert-True ($commandKey.GetValue('') -eq $child.Command) 'Wrong action command.' } finally { $commandKey.Dispose() }
                    }
                }
                else {
                    $commandKey = $key.OpenSubKey('command')
                    try { Assert-True ($commandKey.GetValue('') -eq $item.Command) 'Wrong launch command.' } finally { $commandKey.Dispose() }
                }
            }
            finally { $key.Dispose() }
        }
        # uninstall.ps1 lists the verb across both contexts, backs it up, then deletes only it.
        . (Join-Path $root 'common\uninstall.ps1')
        Assert-True ($testKey -like 'KeyLoop.Test.*') 'Refusing to remove a real registration.'
        $found = @(Get-Registrations | Where-Object { $_.KeyName -ceq $testKey })
        Assert-True ($found.Count -eq 1 -and $found[0].Paths.Count -eq 2 -and $found[0].DisplayName -ceq 'KeyLoop') 'Uninstall list is wrong.'
        Assert-True (@($found[0].CommandPaths) -contains $entry) 'Uninstall list must show the command path.'
        $backupRoot = Join-Path ([IO.Path]::GetTempPath()) ('KeyLoopCheck_' + [Guid]::NewGuid().ToString('N'))
        try {
            $backup = Backup-Registration $found[0] $backupRoot
            Assert-True (@(Get-ChildItem -LiteralPath $backup -Filter '*.reg').Count -eq 2) 'Backup must hold one .reg per context.'
            Assert-True (Test-Path -LiteralPath (Join-Path $backup 'manifest.txt')) 'Backup manifest is missing.'
            Remove-Registration $found[0]
        }
        finally { Remove-Item -LiteralPath $backupRoot -Recurse -Force -ErrorAction SilentlyContinue }
        foreach ($item in $testPlan) {
            Assert-True ($null -eq [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($item.Path)) 'Selected registration survived removal.'
        }
        $failed = $false
        try { Assert-RegistrationPath 'Software\Classes\Directory\Background\shell' } catch { $failed = $true }
        Assert-True $failed 'A context key itself must never be deleted.'
        Write-Output 'REGISTRY_OK'
    }
    finally {
        foreach ($item in $testPlan) { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($item.Path, $false) }
        Send-MenuChanged
    }
}
# No KeyLoop key event is performed by this test.
