param([string]$Root=$PSScriptRoot,[Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{32}$')][string]$Session,[int]$OwnerPID=0)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Lan-Endpoint.ps1')
$utf8=[Text.UTF8Encoding]::new($false)
$box=Join-Path $Root ('lan/lobby/'+$Session)
[IO.Directory]::CreateDirectory($box) | Out-Null
function Read-Shared([string]$Path) {
    $reader=$null; $stream=$null
    try {
        $stream=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        $reader=[IO.StreamReader]::new($stream); return $reader.ReadToEnd()
    } catch [IO.IOException] { return '' }
    finally { if($reader){$reader.Dispose()} elseif($stream){$stream.Dispose()} }
}
function Write-Atomic([string]$Path,[string]$Text) {
    $tmp=$Path+'.tmp'
    [IO.File]::WriteAllText($tmp,$Text,$utf8)
    for($attempt=0;;$attempt++) {
        try {
            if([IO.File]::Exists($Path)){ [IO.File]::Replace($tmp,$Path,[NullString]::Value) }
            else { [IO.File]::Move($tmp,$Path) }
            return
        } catch [IO.IOException] {
            if($attempt -ge 39){throw}
            Start-Sleep -Milliseconds 10
        }
    }
}
$addresses=@()
foreach($nic in [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
    if($nic.OperationalStatus -ne 'Up'){continue}
    foreach($a in $nic.GetIPProperties().UnicastAddresses) {
        if($a.Address.AddressFamily -eq 'InterNetwork') {
            $ip=$a.Address.ToString()
            if($ip -ne '127.0.0.1' -and !$ip.StartsWith('169.254.') -and $addresses -notcontains $ip){$addresses+=$ip}
        }
    }
}
$addresses+='127.0.0.1'
$script:bridge=$null; $script:bridgeBox=$null
$state='ready'; $invite='-'; $errorCode='none'; $lastStatus=''; $sequence=0; $bridgeDue=$null
function Stop-OwnedBridge {
    if($script:bridgeBox){[IO.File]::WriteAllText((Join-Path $script:bridgeBox 'stop.txt'),'stop',$utf8)}
    if($script:bridge -and !$script:bridge.HasExited) {
        if(!$script:bridge.WaitForExit(2000)){Stop-Process -Id $script:bridge.Id; $script:bridge.WaitForExit()}
    }
    $script:bridge=$null; $script:bridgeBox=$null
}
function Start-OwnedBridge([string]$Role,[string]$Address,[int]$Port,[string]$Key) {
    $script:oldConfig=Read-Shared (Join-Path $Root 'lan/config.txt')
    $bridgeArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $PSScriptRoot 'Start-LanBridge.ps1')+'"'),'-Role',$Role,'-Address',$Address,'-Port',$Port,'-RoomKey',$Key,'-MaxSeconds','86400','-RuntimeRoot',('"'+$Root+'"'))
    $script:bridgeBox=$null
    $script:bridge=Start-Process powershell.exe -ArgumentList $bridgeArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $box ('bridge-'+$sequence+'.log')) -RedirectStandardError (Join-Path $box ('bridge-'+$sequence+'-error.log'))
    $script:bridgeDue=[DateTime]::UtcNow.AddSeconds(20)
}
try {
    Write-Atomic (Join-Path $Root 'lan/config.txt') 'OFF'
    Write-Atomic (Join-Path $Root 'lan/lobby-config.txt') ('LB1|'+$Session+'|END')
    while(!(Test-Path -LiteralPath (Join-Path $box 'stop.txt'))) {
        if($OwnerPID -gt 0 -and !(Get-Process -Id $OwnerPID -ErrorAction SilentlyContinue)){break}
        $request=Read-Shared (Join-Path $box ('request-'+($sequence+1)+'.txt'))
        if($request -match '^LB1\|(\d+)\|(hostmapped|host|client|cancel)\|([A-Za-z0-9.-]{1,253})\|(\d+)\|([a-fA-F0-9]*|-)\|END$' -and [int]$Matches[1] -eq $sequence+1) {
            $sequence++; $role=$Matches[2]; $address=$Matches[3]; $portText=$Matches[4]; $key=$Matches[5]
            try {
                if($role -eq 'cancel') {
                    Stop-OwnedBridge; $state='ready'; $invite='-'; $errorCode='none'
                    Write-Atomic (Join-Path $Root 'lan/config.txt') 'OFF'
                } else {
                    if($script:bridge -and !$script:bridge.HasExited){throw 'busy'}
                    Stop-OwnedBridge
                    $mapped=$role -eq 'hostmapped'
                    if($mapped){$role='host'}
                    $ep=Resolve-OnlineCoopEndpoint ($address+':'+$portText) -AllowHostname:($role -eq 'client')
                    if($role -eq 'host') {
                        if($addresses -notcontains $ep.Address){throw 'address'}
                        if($role -eq 'host'){$key=[Guid]::NewGuid().ToString('N')}
                        # Default port collisions are handled before publishing the invitation.
                        $found=$false
                        for($offset=0;$offset -lt 10 -and $ep.Port -le 65535;$offset++) {
                            $probe=$null
                            try { $probe=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse($ep.Address),$ep.Port); $probe.Start(); $found=$true; break }
                            catch [Net.Sockets.SocketException] { if($mapped){throw 'port'}; $ep.Port++ }
                            finally { if($probe){$probe.Stop()} }
                        }
                        if(!$found){throw 'port'}
                    } elseif($key -notmatch '^[a-fA-F0-9]{32}$') { throw 'invite' }
                    $state='starting'; $errorCode='none'; $invite='-'
                        Start-OwnedBridge $role $ep.Address $ep.Port $key
                        $invite=$ep.Address+':'+$ep.Port+':'+$key.ToLowerInvariant()
                }
            } catch {
                if($_.Exception.Message -ne 'busy'){Stop-OwnedBridge; Write-Atomic (Join-Path $Root 'lan/config.txt') 'OFF'}
                $state='error'; $errorCode='invalid'
                if($_.Exception.Message -in @('busy','address','port','invite')){$errorCode=$_.Exception.Message}
            }
        }
        if($script:bridge) {
            $cfg=Read-Shared (Join-Path $Root 'lan/config.txt')
            if(!$script:bridgeBox -and $cfg -ne $oldConfig -and $cfg -match '^OC[23]\|([a-f0-9]{32})\|(host|client)\|END$') {
                $script:bridgeBox=Join-Path $Root ('lan/'+$Matches[1])
            }
            if($script:bridgeBox) {
                $status=Read-Shared (Join-Path $script:bridgeBox 'status.txt')
                if($status -match '^OC1\|[a-f0-9]{32}\|(waiting|connected|error|stopped)\|END$') {
                    $state=$Matches[1]
                    if($state -eq 'error'){$errorCode='connect'}
                }
            }
            if($script:bridge.HasExited -or ($state -eq 'starting' -and [DateTime]::UtcNow -gt $bridgeDue)) {
                if($state -ne 'stopped'){$state='error'; $errorCode='connect'}
            }
        }
        if($script:bridge -and $state -in @('error','stopped')) {
            Stop-OwnedBridge; Write-Atomic (Join-Path $Root 'lan/config.txt') 'OFF'; $invite='-'
        }
        $beat=[Math]::Floor(([DateTime]::UtcNow-[DateTime]'2020-01-01').TotalSeconds)
        $value='LB1|'+$state+'|'+($addresses -join ',')+'|'+$invite+'|'+$errorCode+'|'+$sequence+'|'+$beat+'|END'
        if($value -ne $lastStatus){Write-Atomic (Join-Path $box 'status.txt') $value; $lastStatus=$value}
        Start-Sleep -Milliseconds 100
    }
} finally { Stop-OwnedBridge }
