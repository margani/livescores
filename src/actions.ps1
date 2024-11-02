[CmdletBinding()]
param (
    [Parameter()][string]$Action
)

$ScriptDir = Split-Path -parent $MyInvocation.MyCommand.Path
Import-Module $ScriptDir\helpers.psm1 -Force

$ProgressPreference = 'SilentlyContinue'

$actions = @{
    "repair-data"         = {
        Repair-Data
    }

    "get-today-events"    = {
        Update-Leagues
        Send-TodayEvents
    }

    "get-event-incidents" = {
        Send-TodayFullTimeEvents
        Send-AllFullTimeEvents
        Send-EventsHighlights
    }

    "send-league-tables" = {
        Send-LeagueTables
    }
}

if ($null -eq $actions[$Action]) {
    Write-Host "Unknown action: $Action, pass -Action <action>"
    Exit
}

Write-Host "[$Action] Executing action"
$actions[$Action].Invoke()
Write-Host "[$Action] Action completed"
