param([switch]$CheckOnly,[switch]$MultiCore)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'InstallPaths.psm1') -Force
$install=Get-OnlineCoopInstall $PSScriptRoot
$root=$install.GameRoot; $exe=$install.GameExe
if($CheckOnly){Write-Output $exe; Write-Output ('Mod: '+$install.Kind+' / '+$install.ModId); Write-Output $(if($MultiCore){'CPU mode: normal affinity (multi-core)'}else{'CPU mode: single-core compatibility'}); return}
$utf8=[Text.UTF8Encoding]::new($false)
# Only this mod is forced on; every other entry keeps the player's own setting.
# This mod goes last because SUGAR applies one global path prefix, so the last
# loaded mod owns every file() path and the co-op lobby reads and writes its own
# folder only while it is last.
function Get-ManagedModList([string]$path,[string]$id){
    $entries=New-Object System.Collections.ArrayList
    $seen=@{}
    if(Test-Path -LiteralPath $path -PathType Leaf){
        foreach($line in [IO.File]::ReadAllLines($path)){
            $m=[regex]::Match($line,"\{\s*'([^']+)'\s*,\s*(true|false)")
            if(-not $m.Success){continue}
            $name=$m.Groups[1].Value
            if($seen.ContainsKey($name)){continue}
            $seen[$name]=$true
            [void]$entries.Add([pscustomobject]@{Name=$name;Active=($m.Groups[2].Value -eq 'true')})
        }
    }
    if(-not $seen.ContainsKey($id)){[void]$entries.Add([pscustomobject]@{Name=$id;Active=$true})}
    $text="return {`n"
    foreach($entry in $entries){
        if($entry.Name -eq $id){continue}
        $text += "`t{ '$($entry.Name)', $(if($entry.Active){'true'}else{'false'}) },`n"
    }
    $text += "`t{ '$id', true },`n}"
    return $text
}
$list=Join-Path $root 'mods/modlist.lua'
$managed=Get-ManagedModList $list $install.ModId
[IO.Directory]::CreateDirectory((Join-Path $root 'mods')) | Out-Null
$lan=Join-Path $PSScriptRoot 'lan'; [IO.Directory]::CreateDirectory($lan) | Out-Null
$lock=[IO.FileStream]::new((Join-Path $root 'mods/.onlinecoop-launcher.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
$game=$null; $broker=$null; $backup=$null; $listWritten=$false
$id=[Guid]::NewGuid().ToString('N'); $box=Join-Path $lan ('lobby/'+$id)
$hadList=Test-Path -LiteralPath $list -PathType Leaf
[IO.Directory]::CreateDirectory((Split-Path $list -Parent)) | Out-Null
try {
    if(Get-Process -Name shotgun_king -ErrorAction SilentlyContinue){throw 'Please close the existing game before starting Online Co-op.'}
    [IO.Directory]::CreateDirectory($box) | Out-Null
    if(Test-Path -LiteralPath $list){$backup=[IO.File]::ReadAllBytes($list); [IO.File]::WriteAllBytes((Join-Path $box 'modlist-backup.lua'),$backup)}
    [IO.File]::WriteAllText($list,$managed,$utf8); $listWritten=$true
    [IO.File]::WriteAllText((Join-Path $lan 'probe.txt'),'OFF',$utf8)
    $broker=Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $PSScriptRoot 'Lan-GameBroker.ps1')+'"'),'-Root',('"'+$PSScriptRoot+'"'),'-Session',$id,'-OwnerPID',$PID) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $box 'broker.log') -RedirectStandardError (Join-Path $box 'broker-error.log')
    $until=[DateTime]::UtcNow.AddSeconds(15)
    while(!(Test-Path -LiteralPath (Join-Path $box 'status.txt'))) {
        if($broker.HasExited -or [DateTime]::UtcNow -gt $until){throw 'Online helper could not start; see lan/lobby logs.'}
        Start-Sleep -Milliseconds 100
    }
    $self=[Diagnostics.Process]::GetCurrentProcess(); $old=$self.ProcessorAffinity
    try {
        if(!$MultiCore) {
            [long]$mask=1; while(($old.ToInt64() -band $mask) -eq 0){$mask=$mask -shl 1}
            $self.ProcessorAffinity=[IntPtr]$mask
        }
        # User explicitly launched the game: its window is intended to be visible.
        $game=Start-Process -FilePath $exe -WorkingDirectory $root -PassThru
    } finally {$self.ProcessorAffinity=$old}
    $game.WaitForExit()
} finally {
    if(Test-Path -LiteralPath $box){[IO.File]::WriteAllText((Join-Path $box 'stop.txt'),'stop',$utf8)}
    if($broker -and !$broker.HasExited -and !$broker.WaitForExit(5000)){Stop-Process -Id $broker.Id}
    if($listWritten -and (Test-Path -LiteralPath $list) -and [IO.File]::ReadAllText($list) -eq $managed) {
        if($hadList){[IO.File]::WriteAllBytes($list,$backup)}
        else {Remove-Item -LiteralPath $list}
    }
    $lock.Dispose()
}
