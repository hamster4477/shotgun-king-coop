Set-StrictMode -Version 2
Import-Module (Join-Path $PSScriptRoot 'InstallPaths.psm1')

# Edit only the selected app's value. Keep every other VDF byte as written by Steam.
if (-not ('OnlineCoopSteam.Vdf' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Text;
namespace OnlineCoopSteam {
 public sealed class Node {
  public string Key, Value; public int Start, Length, Close;
  public List<Node> Children;
 }
 public sealed class Vdf {
  string text; int pos;
  void Space() {
   while(pos<text.Length) {
    if(char.IsWhiteSpace(text[pos])) {pos++; continue;}
    if(pos+1<text.Length && text[pos]=='/' && text[pos+1]=='/') {
     while(pos<text.Length && text[pos]!='\n') pos++; continue;
    }
    break;
   }
  }
  string Quoted() {
   Space(); if(pos>=text.Length || text[pos++]!='"') throw new FormatException("Expected quoted VDF value");
   var b=new StringBuilder();
   while(pos<text.Length) {
    char c=text[pos++]; if(c=='"') return b.ToString();
    if(c=='\\') {
     if(pos>=text.Length) break;
     c=text[pos++];
     if(c=='n') b.Append('\n'); else if(c=='r') b.Append('\r'); else if(c=='t') b.Append('\t');
     else if(c=='"' || c=='\\') b.Append(c); else {b.Append('\\'); b.Append(c);}
    } else b.Append(c);
   }
   throw new FormatException("Unclosed VDF string");
  }
  List<Node> Entries(int depth, bool nested) {
   if(depth>64) throw new FormatException("VDF nesting limit");
   var nodes=new List<Node>();
   while(true) {
    Space();
    if(pos>=text.Length) {if(nested) throw new FormatException("Unclosed VDF block"); return nodes;}
    if(text[pos]=='}') {if(!nested) throw new FormatException("Unexpected VDF close"); return nodes;}
    var n=new Node(); n.Key=Quoted(); Space();
    if(pos<text.Length && text[pos]=='{') {pos++; n.Children=Entries(depth+1,true); n.Close=pos++;}
    else {n.Start=pos; n.Value=Quoted(); n.Length=pos-n.Start;}
    nodes.Add(n);
   }
  }
  public static List<Node> Parse(string source) {
   if(source.Length>16000000) throw new FormatException("VDF size limit");
   return new Vdf {text=source}.Entries(0,false);
  }
  static Node Find(List<Node> nodes,string key) {
   Node found=null;
   foreach(var n in nodes) if(String.Equals(n.Key,key,StringComparison.OrdinalIgnoreCase)) {
    if(found!=null) throw new FormatException("Duplicate VDF key: "+key); found=n;
   }
   return found;
  }
  static readonly string[] Path={"UserLocalConfigStore","Software","Valve","Steam","apps","1972440","LaunchOptions"};
  public static string Read(string source) {
   var nodes=Parse(source);
   for(int i=0;i<Path.Length;i++) {
    var n=Find(nodes,Path[i]); if(n==null) return "";
    if(i==Path.Length-1) {if(n.Children!=null) throw new FormatException("LaunchOptions is a block"); return n.Value;}
    if(n.Children==null) throw new FormatException("Expected VDF block: "+Path[i]); nodes=n.Children;
   }
   return "";
  }
  static string Quote(string s) {return "\""+s.Replace("\\","\\\\").Replace("\"","\\\"").Replace("\r","\\r").Replace("\n","\\n").Replace("\t","\\t")+"\"";}
  static string Make(int i,string value,string nl) {
   string indent=new string('\t',i);
   if(i==Path.Length-1) return indent+Quote(Path[i])+"\t\t"+Quote(value)+nl;
   return indent+Quote(Path[i])+nl+indent+"{"+nl+Make(i+1,value,nl)+indent+"}"+nl;
  }
  public static string Set(string source,string value) {
   var nodes=Parse(source); Node parent=null;
   string nl=source.Contains("\r\n") ? "\r\n" : "\n";
   for(int i=0;i<Path.Length;i++) {
    var n=Find(nodes,Path[i]);
    if(n==null) {
     if(parent==null) throw new FormatException("Missing UserLocalConfigStore root");
     int at=parent.Close, line=source.LastIndexOf('\n',Math.Max(0,at-1))+1;
     bool blank=true; for(int j=line;j<at;j++) if(!char.IsWhiteSpace(source[j])) blank=false;
     if(blank) at=line;
     string result=source.Insert(at,(blank ? "" : nl)+Make(i,value,nl));
     if(Read(result)!=value) throw new FormatException("VDF insertion validation failed"); return result;
    }
    if(i==Path.Length-1) {
     if(n.Children!=null) throw new FormatException("LaunchOptions is a block");
     return source.Substring(0,n.Start)+Quote(value)+source.Substring(n.Start+n.Length);
    }
    if(n.Children==null) throw new FormatException("Expected VDF block: "+Path[i]);
    parent=n; nodes=n.Children;
   }
   throw new FormatException("Invalid VDF path");
  }
 }
}
'@
}

function Get-CoopSteamLaunchOption {
 param([Parameter(Mandatory)][string]$ModRoot,[switch]$MultiCore)
 $mod=[IO.Path]::GetFullPath($ModRoot)
 $hostExe=Join-Path $env:WINDIR 'System32/wscript.exe'
 $name=if($MultiCore){'Start Online Co-op Multi Core.vbs'}else{'Start Online Co-op.vbs'}
 $script=Join-Path $mod $name
 $install=Get-OnlineCoopInstall $mod
 foreach($path in @($hostExe,$script,$install.GameExe)) {
  if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw "File missing / 文件不存在: $path"}
 }
 return '"'+$hostExe+'" "'+$script+'" %command%'
}
function Get-CoopSteamProcess { @(Get-Process -Name steam -ErrorAction SilentlyContinue) }
function Get-CoopSteamLocation {
 param([string]$ModRoot)
 $candidates=@()
 foreach($p in @(Get-CoopSteamProcess)) {try {if($p.Path){$candidates+=Split-Path $p.Path -Parent}} catch {}}
 $registry=Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
 if($registry -and $registry.PSObject.Properties['SteamPath']) {$candidates+=$registry.SteamPath}
 $candidates+=@(Get-OnlineCoopSteamRoots)
 $ancestor=Get-Item -LiteralPath $ModRoot
 while($ancestor){$candidates+=$ancestor.FullName; $ancestor=$ancestor.Parent}
 foreach($candidate in $candidates) {
  if(Test-Path -LiteralPath (Join-Path $candidate 'steam.exe') -PathType Leaf){return [IO.Path]::GetFullPath($candidate)}
 }
 return $null
}
function Get-CoopSteamAccounts {
 param([Parameter(Mandatory)][string]$SteamRoot)
 $userdata=Join-Path $SteamRoot 'userdata'
 if(!(Test-Path -LiteralPath $userdata)){return}
 Get-ChildItem -LiteralPath $userdata -Directory | Where-Object {
  $_.Name -match '^\d+$' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'config/localconfig.vdf') -PathType Leaf)
 } | ForEach-Object {$_.Name}
}
function Get-CoopSteamActiveAccount {
 param([string]$SteamRoot)
 # Do not label stale registry data, or an account from another Steam install, as current.
 $active=Get-ItemProperty 'HKCU:\Software\Valve\Steam\ActiveProcess' -ErrorAction SilentlyContinue
 if(!$active -or !$active.PSObject.Properties['ActiveUser'] -or !$active.ActiveUser){return ''}
 foreach($p in @(Get-CoopSteamProcess)) {
  try {
   if($p.Path -and [IO.Path]::GetFullPath((Split-Path $p.Path -Parent)) -eq [IO.Path]::GetFullPath($SteamRoot)) {
    return ([uint32]$active.ActiveUser).ToString()
   }
  } catch {}
 }
 return ''
}
function Get-CoopSteamAccountDetails {
 param([string]$SteamRoot,[string]$ActiveAccount)
 if(!$PSBoundParameters.ContainsKey('ActiveAccount')){$ActiveAccount=Get-CoopSteamActiveAccount $SteamRoot}
 $profiles=@{}
 $login=Join-Path $SteamRoot 'config/loginusers.vdf'
 if(Test-Path -LiteralPath $login -PathType Leaf) {
  try {
   $nodes=[OnlineCoopSteam.Vdf]::Parse((Read-CoopSteamConfig $login).Text)
   foreach($users in $nodes) {if($users.Key -eq 'users') {
    foreach($user in $users.Children) {
     $steamId=[uint64]0
     if(![uint64]::TryParse($user.Key,[ref]$steamId) -or $steamId -le 76561197960265728L -or $steamId -gt 76561202255233023L){continue}
     $id=($steamId-76561197960265728L).ToString()
     $fields=@{}
     foreach($field in $user.Children){if($null -eq $field.Children){$fields[$field.Key]=$field.Value}}
     $profiles[$id]=$fields
    }
   }}
  } catch { $profiles=@{} } # Metadata is optional; configuration remains usable with IDs.
 }
 foreach($id in @(Get-CoopSteamAccounts $SteamRoot)) {
  $name='未知昵称 / Unknown nickname'; $recent=$false
  if($profiles.ContainsKey($id)) {
   $profile=$profiles[$id]
   if($profile['PersonaName']){$name=[string]$profile['PersonaName']}
   $recent=$profile['MostRecent'] -eq '1'
  }
  $name=($name -replace '[\r\n\t\x00-\x1f]',' ')
  $isActive=$id -eq $ActiveAccount
  $tag=if($isActive){'[当前登录 / Current] '}elseif($recent){'[最近登录 / Last login] '}else{''}
  [pscustomobject]@{Id=$id;Display=$tag+$name+'  ('+$id+')';IsActive=$isActive;IsRecent=$recent}
 }
}
function Get-CoopSteamConfigPath {
 param([string]$SteamRoot,[string]$Account)
 if($Account -notmatch '^\d+$'){throw 'Select a Steam account / 请选择 Steam 账号'}
 if(!(Test-Path -LiteralPath (Join-Path $SteamRoot 'steam.exe') -PathType Leaf)){throw 'Invalid Steam folder / Steam 目录无效'}
 $path=[IO.Path]::GetFullPath((Join-Path $SteamRoot "userdata/$Account/config/localconfig.vdf"))
 if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw 'Steam account configuration missing / Steam 账号配置不存在'}
 return $path
}
function Read-CoopSteamConfig {
 param([string]$Path)
 $bytes=[IO.File]::ReadAllBytes($Path)
 $bom=$bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
 $offset=if($bom){3}else{0}; $encoding=[Text.UTF8Encoding]::new($bom,$true)
 [pscustomobject]@{Bytes=$bytes;Encoding=$encoding;Text=$encoding.GetString($bytes,$offset,$bytes.Length-$offset)}
}
function Read-CoopSteamLaunchOption {
 param([string]$SteamRoot,[string]$Account)
 $data=Read-CoopSteamConfig (Get-CoopSteamConfigPath $SteamRoot $Account)
 [OnlineCoopSteam.Vdf]::Read($data.Text)
}
function Set-CoopSteamLaunchOption {
 param([string]$SteamRoot,[string]$Account,[string]$Value)
 if(@(Get-CoopSteamProcess).Count){throw 'Steam is still running / Steam 仍在运行，未写入'}
 $path=Get-CoopSteamConfigPath $SteamRoot $Account
 $data=Read-CoopSteamConfig $path
 $updated=[OnlineCoopSteam.Vdf]::Set($data.Text,$Value)
 if($updated -eq $data.Text){return [pscustomobject]@{Changed=$false;Backup=$null}}
 $tag=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N')
 $temp=$path+'.onlinecoop-'+$tag+'.tmp'; $backup=$path+'.onlinecoop-'+$tag+'.bak'
 try {
  [IO.File]::WriteAllText($temp,$updated,$data.Encoding)
  if([OnlineCoopSteam.Vdf]::Read((Read-CoopSteamConfig $temp).Text) -ne $Value){throw 'Validation failed / 写入验证失败'}
  if(@(Get-CoopSteamProcess).Count){throw 'Steam restarted; configuration untouched / Steam 已重新启动，未写入配置'}
  if([Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) -ne [Convert]::ToBase64String($data.Bytes)) {
   throw 'Configuration changed; retry / 配置已发生变化，请重试'
  }
  # Atomic replacement also preserves the exact previous file as a backup.
  [IO.File]::Replace($temp,$path,$backup)
  return [pscustomobject]@{Changed=$true;Backup=$backup}
 } finally {if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp}}
}
function Request-CoopSteamExit {
 param([string]$Exe)
 Start-Process -FilePath $Exe -ArgumentList '-shutdown' -WindowStyle Hidden | Out-Null
}
function Start-CoopSteam {
 param([string]$Exe)
 # The user selected Apply and restart Steam: the reopened window is intentional.
 Start-Process -FilePath $Exe | Out-Null
}
function Invoke-CoopSteamConfiguration {
 param([string]$SteamRoot,[string]$Account,[string]$Value,[scriptblock]$Progress={},[int]$TimeoutSeconds=45)
 $exe=Join-Path $SteamRoot 'steam.exe'
 $null=Get-CoopSteamConfigPath $SteamRoot $Account
 # Validate before closing Steam, then re-read after its final settings flush.
 $null=[OnlineCoopSteam.Vdf]::Set((Read-CoopSteamConfig (Get-CoopSteamConfigPath $SteamRoot $Account)).Text,$Value)
 $running=@(Get-CoopSteamProcess); $wasRunning=$running.Count -gt 0; $stopped=$false; $written=$false
 foreach($p in $running) {
  if(!$p.Path -or [IO.Path]::GetFullPath($p.Path) -ine [IO.Path]::GetFullPath($exe)) {
   throw 'A different Steam installation is running / 正在运行的是另一个 Steam 安装目录'
  }
 }
 try {
  if($wasRunning) {
   & $Progress '正在退出 Steam，请处理 Steam 自身提示…… / Closing Steam; respond to any Steam prompts...'
   Request-CoopSteamExit $exe
   $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
   while(@(Get-CoopSteamProcess).Count) {
    if([DateTime]::UtcNow -ge $deadline){throw 'Steam did not exit; nothing written. Close it and retry. / Steam 未退出，未写入；请退出后重试。'}
    Start-Sleep -Milliseconds 200
    & $Progress '等待 Steam 保存配置并退出…… / Waiting for Steam to save settings and exit...'
   }
  }
  $stopped=$true
  & $Progress '正在备份并应用启动选项…… / Backing up and applying launch options...'
  $result=Set-CoopSteamLaunchOption $SteamRoot $Account $Value
  $written=$true
  return $result
 } finally {
  if($stopped -and ($wasRunning -or $written)) {
   & $Progress '正在重新打开 Steam…… / Reopening Steam...'
   try {Start-CoopSteam $exe} catch {throw "Steam restart failed; check the saved setting / Steam 重启失败，请检查已保存的设置: $_"}
  }
 }
}
Export-ModuleMember -Function *-CoopSteam*
