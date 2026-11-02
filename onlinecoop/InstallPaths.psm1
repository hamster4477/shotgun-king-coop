# Shared path discovery for local mods and Steam Workshop items. Never executes Lua/VDF.
function Get-OnlineCoopSteamRoots {
    $roots=@()
    foreach($key in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        $entry=Get-ItemProperty $key -ErrorAction SilentlyContinue
        if($entry){foreach($name in @('SteamPath','InstallPath')){if($entry.PSObject.Properties[$name]){$roots+=[string]$entry.$name}}}
    }
    foreach($process in @(Get-Process -Name steam -ErrorAction SilentlyContinue)) {
        try{if($process.Path){$roots+=Split-Path $process.Path -Parent}}catch{}
    }
    $roots | Where-Object {$_ -and (Test-Path -LiteralPath (Join-Path $_ 'steam.exe') -PathType Leaf)} | Select-Object -Unique
}
function Get-OnlineCoopGameFromLibrary([string]$SteamApps) {
    $manifest=Join-Path $SteamApps 'appmanifest_1972440.acf'
    if(!(Test-Path -LiteralPath $manifest -PathType Leaf)){return}
    $text=[IO.File]::ReadAllText($manifest)
    if($text -notmatch '"appid"\s+"1972440"'){return}
    if($text -notmatch '"installdir"\s+"([^"\\/:]+)"'){return}
    $name=$Matches[1]
    if($name -in @('.','..')){return}
    $root=[IO.Path]::GetFullPath((Join-Path (Join-Path $SteamApps 'common') $name))
    if(Test-Path -LiteralPath (Join-Path $root 'shotgun_king.exe') -PathType Leaf){return $root}
}
function Get-OnlineCoopInstall {
    param([Parameter(Mandatory)][string]$ModRoot,[string[]]$SteamRoots)
    $mod=[IO.Path]::GetFullPath($ModRoot).TrimEnd('\','/')
    $dir=Get-Item -LiteralPath $mod
    $game=$null; $apps=$null; $kind=$null; $id=$dir.Name
    if($dir.Parent.Name -eq 'mods' -and (Test-Path -LiteralPath (Join-Path $dir.Parent.Parent.FullName 'shotgun_king.exe') -PathType Leaf)) {
        $game=$dir.Parent.Parent.FullName; $kind='local'
    } elseif($id -match '^\d+$' -and $dir.Parent.Name -eq '1972440' -and $dir.Parent.Parent.Name -eq 'content' -and $dir.Parent.Parent.Parent.Name -eq 'workshop' -and $dir.Parent.Parent.Parent.Parent.Name -eq 'steamapps') {
        $kind='workshop'; $apps=$dir.Parent.Parent.Parent.Parent.FullName
        $game=Get-OnlineCoopGameFromLibrary $apps
    } else {
        throw 'Install in game/mods/onlinecoop, or use the subscribed Workshop item folder directly. / 请放入游戏 mods/onlinecoop，或直接使用订阅的工坊项目目录。'
    }
    if($id -notmatch '^[A-Za-z0-9_. -]+$'){throw 'Unsupported mod folder name / 不支持此模组目录名'}
    if(!$game) {
        if(!$PSBoundParameters.ContainsKey('SteamRoots')){$SteamRoots=@(Get-OnlineCoopSteamRoots)}
        $libraries=@(); if($apps){$libraries+=$apps}
        foreach($steam in $SteamRoots) {
            $libraries+=Join-Path $steam 'steamapps'
            foreach($vdf in @((Join-Path $steam 'steamapps/libraryfolders.vdf'),(Join-Path $steam 'config/libraryfolders.vdf'))) {
                if(Test-Path -LiteralPath $vdf -PathType Leaf) {
                    foreach($m in [regex]::Matches([IO.File]::ReadAllText($vdf),'"(?:path|\d+)"\s+"((?:\\.|[^"\\])*)"')) {
                        $path=$m.Groups[1].Value.Replace('\\','\')
                        if([IO.Path]::IsPathRooted($path)){$libraries+=Join-Path $path 'steamapps'}
                    }
                }
            }
        }
        $found=@($libraries | Select-Object -Unique | ForEach-Object {Get-OnlineCoopGameFromLibrary $_} | Select-Object -Unique)
        if($found.Count -eq 1){$game=$found[0]}
        elseif($found.Count -gt 1){throw 'Multiple game installations found. Keep the Workshop item in its game Steam library. / 找到多个游戏安装，请将工坊项目保留在对应游戏的 Steam 库。'}
    }
    if(!$game){throw 'Shotgun King installation not found. Install the game through Steam first. / 未找到霰弹国王安装，请先通过 Steam 安装游戏。'}
    [pscustomobject]@{GameRoot=$game;GameExe=(Join-Path $game 'shotgun_king.exe');ModRoot=$mod;Kind=$kind;ModId=$id;ModList=(Join-Path $game 'mods/modlist.lua');ManagedModList=("return {{'"+$id+"',true}}");RuntimeRoot=$mod}
}
Export-ModuleMember -Function Get-OnlineCoop*
