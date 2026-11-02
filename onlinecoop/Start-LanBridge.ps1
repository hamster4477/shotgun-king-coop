param(
    [ValidateSet('host','client')][string]$Role='host',
    [string]$Address='127.0.0.1',
    [ValidateRange(1,65535)][int]$Port=27841,
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Fa-f0-9]{32}$')][string]$RoomKey,
    [ValidateRange(10,86400)][int]$MaxSeconds=1800,
    [string]$RuntimeRoot=$PSScriptRoot
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Lan-Endpoint.ps1')
$endpoint=Resolve-OnlineCoopEndpoint ($Address+':'+$Port) -AllowHostname:($Role -eq 'client')
$Address=$endpoint.Address; $Port=$endpoint.Port
Add-Type -Path (Join-Path $PSScriptRoot 'lan/LanTransport.cs')
$result=[OnlineCoopLan]::Run($RuntimeRoot,$Role,$Address,$Port,$RoomKey,$MaxSeconds)
exit $result
