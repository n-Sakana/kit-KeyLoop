[CmdletBinding()]
param([switch]$PlanOnly)
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'menu.ps1')
    if ($PlanOnly) { @(Get-MenuPlan) | ConvertTo-Json -Depth 6; exit 0 }
    Install-StandaloneMenu
    Write-Host ''
    Write-Host '  KeyLoop was added to the right-click menu of folder backgrounds and the desktop.' -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ''
    Write-Host ('  Error: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
