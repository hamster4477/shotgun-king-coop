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
$adapters=@{}
$broadcasts=@('127.0.0.1','255.255.255.255')
$savedAdapter=Read-Shared (Join-Path $Root 'lan/last-host-adapter.txt')
$preferred=$null
foreach($nic in [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
    if($nic.OperationalStatus -ne 'Up'){continue}
    foreach($a in $nic.GetIPProperties().UnicastAddresses) {
        if($a.Address.AddressFamily -eq 'InterNetwork') {
            $ip=$a.Address.ToString()
            if($ip -ne '127.0.0.1' -and !$ip.StartsWith('169.254.') -and $addresses -notcontains $ip){
                $addresses+=$ip
                $name=$nic.Name -replace '[|\r\n\x00-\x1f]',' '
                if($name.Length -gt 20){$name=$name.Substring(0,20)}
                $adapters[$ip]=@{Id=$nic.Id; Name=$name}
                if($nic.Id -eq $savedAdapter.Trim()){$preferred=$ip}
                if($a.IPv4Mask){
                    $bytes=$a.Address.GetAddressBytes(); $mask=$a.IPv4Mask.GetAddressBytes()
                    for($i=0;$i -lt 4;$i++){$bytes[$i]=$bytes[$i] -bor (255 -bxor $mask[$i])}
                    $broadcasts+=([Net.IPAddress]::new($bytes)).ToString()
                }
            }
        }
    }
}
if($preferred){$addresses=@($preferred)+@($addresses | Where-Object {$_ -ne $preferred})}
$addresses+='127.0.0.1'
$adapterLines=@($addresses | ForEach-Object {if($adapters.ContainsKey($_)){$_+'|'+$adapters[$_].Name}})
Write-Atomic (Join-Path $box 'adapters.txt') ($adapterLines -join "`n")
$discovery=$null
try {
    Add-Type -Path (Join-Path $PSScriptRoot 'lan/LanDiscovery.cs')
    $discovery=[OnlineCoopDiscovery]::new([string[]]@($broadcasts | Select-Object -Unique))
} catch { Write-Warning 'LAN discovery unavailable; invitation codes remain available.' }
Write-Atomic (Join-Path $box 'rooms.txt') ''
$lastRooms=''; $remembered=$false; $mapped=$false; $role=''
$script:bridge=$null; $script:bridgeBox=$null
$state='ready'; $invite='-'; $errorCode='none'; $lastStatus=''; $sequence=0; $bridgeDue=$null
$script:tunnel=$null; $script:tunnelBox=$null; $script:tunnelDue=$null
$script:steamRole=$null; $script:steamPort=0; $script:steamKey=$null
function Stop-OwnedBridge {
    # The Steam tunnel owns the client bridge start, so it must go first.
    if($script:tunnelBox){[IO.File]::WriteAllText((Join-Path $script:tunnelBox 'stop.txt'),'stop',$utf8)}
    if($script:tunnel -and !$script:tunnel.HasExited -and !$script:tunnel.WaitForExit(3000)){Stop-Process -Id $script:tunnel.Id}
    $script:tunnel=$null; $script:tunnelBox=$null; $script:steamRole=$null

    if($script:bridgeBox){[IO.File]::WriteAllText((Join-Path $script:bridgeBox 'stop.txt'),'stop',$utf8)}
    if($script:bridge -and !$script:bridge.HasExited) {
        if(!$script:bridge.WaitForExit(2000)){Stop-Process -Id $script:bridge.Id; $script:bridge.WaitForExit()}
    }
    $script:bridge=$null; $script:bridgeBox=$null
}
function Start-OwnedTunnel([string]$Role,[int]$Port,[string]$Lobby) {
    # Optional developer transport: a headless Steam P2P tunnel carrying the same
    # authenticated TCP bridge. Both players need this folder and the SKCOOPS1
    # metadata; the public LAN package deliberately ships neither.
    $exe=Join-Path $PSScriptRoot 'steam-p2p/onlinecoop-steam-tunnel.exe'
    if(!(Test-Path -LiteralPath $exe) -or !(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'steam-p2p/steam_api64.dll'))){throw 'steammissing'}
    $script:tunnelBox=Join-Path $box ('steam-'+$sequence)
    [IO.Directory]::CreateDirectory($script:tunnelBox) | Out-Null
    $tunnelArgs=@('--role',$Role,'--port',$Port,'--lobby',$Lobby,'--status',('"'+(Join-Path $script:tunnelBox 'status.txt')+'"'),'--stop',('"'+(Join-Path $script:tunnelBox 'stop.txt')+'"'))
    $script:tunnel=Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -ArgumentList $tunnelArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $script:tunnelBox 'stdout.log') -RedirectStandardError (Join-Path $script:tunnelBox 'stderr.log')
    $script:tunnelDue=[DateTime]::UtcNow.AddSeconds(120)
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
        if($request -match '^LB1\|(\d+)\|(steamhost|steamclient|hostmapped|host|client|cancel)\|([A-Za-z0-9.-]{1,253})\|(\d+)\|([a-fA-F0-9]*|-)\|END$' -and [int]$Matches[1] -eq $sequence+1) {
            $sequence++; $role=$Matches[2]; $address=$Matches[3]; $portText=$Matches[4]; $key=$Matches[5]
            try {
                if($role -eq 'cancel') {
                    Stop-OwnedBridge; $state='ready'; $invite='-'; $errorCode='none'
                    Write-Atomic (Join-Path $Root 'lan/config.txt') 'OFF'
                } else {
                    if(($script:bridge -and !$script:bridge.HasExited) -or ($script:tunnel -and !$script:tunnel.HasExited)){throw 'busy'}
                    Stop-OwnedBridge
                    $steam=$role -in @('steamhost','steamclient')
                    $lobby='0'
                    if($steam){
                        if($role -eq 'steamclient'){
                            [UInt64]$lobbyNumber=0
                            if($address -notmatch '^[0-9]{17,20}$' -or ![UInt64]::TryParse($address,[ref]$lobbyNumber) -or $key -notmatch '^[a-fA-F0-9]{32}$'){throw 'invite'}
                            $lobby=$address
                        }
                        $role=if($role -eq 'steamhost'){'host'}else{'client'}
                        $address='127.0.0.1'
                    }
                    $mapped=$role -eq 'hostmapped'
                    if($mapped){$role='host'}
                    $ep=Resolve-OnlineCoopEndpoint ($address+':'+$portText) -AllowHostname:($role -eq 'client')
                    if($role -eq 'host' -or $steam) {
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
                    $state='starting'; $errorCode='none'; $invite='-'; $remembered=$false
                    if($steam){
                        $script:steamRole=$role; $script:steamPort=$ep.Port; $script:steamKey=$key
                        if($role -eq 'host'){
                            Start-OwnedBridge $role $ep.Address $ep.Port $key
                        }
                        Start-OwnedTunnel $role $ep.Port $lobby
                    } else {
                        Start-OwnedBridge $role $ep.Address $ep.Port $key
                        $invite=$ep.Address+':'+$ep.Port+':'+$key.ToLowerInvariant()
                    }
                }
            } catch {
                if($_.Exception.Message -ne 'busy'){Stop-OwnedBridge; Write-Atomic (Join-Path $Root 'lan/config.txt') 'OFF'}
                $state='error'; $errorCode='invalid'
                if($_.Exception.Message -in @('busy','address','port','invite','steammissing')){$errorCode=$_.Exception.Message}
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
                    if($state -eq 'connected' -and $role -eq 'host' -and !$mapped -and !$remembered -and $adapters.ContainsKey($ep.Address)){
                        Write-Atomic (Join-Path $Root 'lan/last-host-adapter.txt') $adapters[$ep.Address].Id
                        $remembered=$true
                    }
                }
            }
            if($script:bridge.HasExited -or ($state -eq 'starting' -and [DateTime]::UtcNow -gt $bridgeDue)) {
                if($state -ne 'stopped'){$state='error'; $errorCode='connect'}
            }
        }
        if($script:bridge -and $state -in @('error','stopped')) {
            $detail=Read-Shared (Join-Path $box ('bridge-'+$sequence+'-error.log'))
            if($script:bridgeBox){$detail+=(Read-Shared (Join-Path $script:bridgeBox 'error.txt'))}
            if($detail -match '10013'){$errorCode='denied'}
            elseif($detail -match '10061|actively refused'){$errorCode='refused'}
            elseif($detail -match 'Room key, role or protocol mismatch'){$errorCode='mismatch'}
            elseif($detail -match 'Connection timeout|10060'){$errorCode='timeout'}
            elseif($detail -match 'No such host|11001|11004'){$errorCode='dns'}
            elseif($detail -match 'Heartbeat timeout|Peer disconnected'){$errorCode='disconnected'}
            elseif($detail -match 'Handshake timeout'){$errorCode='handshake'}
            Stop-OwnedBridge; Write-Atomic (Join-Path $Root 'lan/config.txt') 'OFF'; $invite='-'
        }
        if($script:tunnel) {
            # The tunnel reports its own lobby id; the host publishes it, and the
            # guest only opens the TCP bridge once the tunnel is ready.
            $ts=Read-Shared (Join-Path $script:tunnelBox 'status.txt')
            if($ts -match '^SP1\|(starting|waiting|ready|error|stopped)\|([0-9]+)\|(none|steam|port|connect)\|END$') {
                $tstate=$Matches[1]; $tid=$Matches[2]; $terr=$Matches[3]
                if($tstate -eq 'error' -or $tstate -eq 'stopped') {
                    Stop-OwnedBridge; Write-Atomic (Join-Path $Root 'lan/config.txt') 'OFF'
                    $state='error'; $errorCode=if($terr -eq 'steam'){'steam'}else{'connect'}; $invite='-'
                } elseif($tid -ne '0') {
                    if($script:steamRole -eq 'host'){$invite='steam:'+$tid+':'+$script:steamKey.ToLowerInvariant()}
                    if($tstate -eq 'ready' -and $script:steamRole -eq 'client' -and !$script:bridge){
                        Start-OwnedBridge 'client' '127.0.0.1' $script:steamPort $script:steamKey
                    }
                    if(!$script:bridgeBox){$state='starting'}
                }
            }
            if($script:tunnel -and ($script:tunnel.HasExited -or (($ts -notmatch '^SP1\|(waiting|ready)\|[1-9][0-9]*\|none\|END$') -and [DateTime]::UtcNow -gt $script:tunnelDue))){
                Stop-OwnedBridge; Write-Atomic (Join-Path $Root 'lan/config.txt') 'OFF'
                $state='error'; $errorCode='steam'; $invite='-'
            }
        }
        if($discovery){
            $advertise=if($role -eq 'host' -and !$mapped -and $state -eq 'waiting'){$invite}else{''}
            try {
                $rooms=$discovery.Poll($advertise,((Read-Shared (Join-Path $box 'discover.txt')) -eq 'ON'))
                if($rooms -ne $lastRooms){Write-Atomic (Join-Path $box 'rooms.txt') $rooms; $lastRooms=$rooms}
            } catch {
                $discovery.Dispose(); $discovery=$null
                Write-Atomic (Join-Path $box 'rooms.txt') ''
                Write-Warning 'LAN discovery stopped; invitation codes remain available.'
            }
        }
        $beat=[Math]::Floor(([DateTime]::UtcNow-[DateTime]'2020-01-01').TotalSeconds)
        $value='LB1|'+$state+'|'+($addresses -join ',')+'|'+$invite+'|'+$errorCode+'|'+$sequence+'|'+$beat+'|END'
        if($value -ne $lastStatus){Write-Atomic (Join-Path $box 'status.txt') $value; $lastStatus=$value}
        Start-Sleep -Milliseconds 100
    }
} finally { Stop-OwnedBridge; if($discovery){$discovery.Dispose()} }
