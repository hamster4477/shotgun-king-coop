param([switch]$CheckOnly,[switch]$UiCheckOnly)
$ErrorActionPreference='Stop'
$loading=$null
trap {
 if($loading){$loading.Dispose()}
 $details=$_.ToString()+[Environment]::NewLine+$_.ScriptStackTrace
 $log=Join-Path $env:TEMP 'onlinecoop-steam-setup-error.txt'
 try {[IO.File]::WriteAllText($log,$details,[Text.UTF8Encoding]::new($true))} catch {}
 if(!$CheckOnly -and !$UiCheckOnly){
  Add-Type -AssemblyName System.Windows.Forms
  [Windows.Forms.MessageBox]::Show("设置启动失败 / Setup failed:`r`n$details`r`n日志 / Log: $log",'Online Co-op') | Out-Null
 } else {Write-Error $details -ErrorAction Continue}
 exit 1
}
if($CheckOnly){
 Import-Module (Join-Path $PSScriptRoot 'SteamLaunchOptions.psm1') -Force
 Get-CoopSteamLaunchOption $PSScriptRoot; Get-CoopSteamLaunchOption $PSScriptRoot -MultiCore; exit
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
# Display feedback before compiling the VDF parser and scanning Steam accounts.
if(!$UiCheckOnly){
 $loading=New-Object Windows.Forms.Form
 $loading.Text='Steam 启动设置 / Steam launch setup'
 $loading.ClientSize=New-Object Drawing.Size(480,90)
 $loading.StartPosition='CenterScreen'; $loading.ControlBox=$false
 $notice=New-Object Windows.Forms.Label
 $notice.Text="正在加载设置，请稍候……`r`nLoading settings, please wait..."
 $notice.SetBounds(20,20,440,60); $loading.Controls.Add($notice)
 $loading.Show(); [Windows.Forms.Application]::DoEvents()
}
Import-Module (Join-Path $PSScriptRoot 'SteamLaunchOptions.psm1') -Force
$form=New-Object Windows.Forms.Form
$form.Text='Steam 启动设置 / Steam launch setup'
$form.ClientSize=New-Object Drawing.Size(760,616)
$form.StartPosition='CenterScreen'
$form.FormBorderStyle='FixedDialog'; $form.MaximizeBox=$false
function LabelAt($text,$x,$y,$w,$h){$c=New-Object Windows.Forms.Label; $c.Text=$text; $c.SetBounds($x,$y,$w,$h); $form.Controls.Add($c)}
function BoxAt($x,$y,$w,$h){$c=New-Object Windows.Forms.TextBox; $c.SetBounds($x,$y,$w,$h); $form.Controls.Add($c); return $c}
function ButtonAt($text,$x,$y,$w){$c=New-Object Windows.Forms.Button; $c.Text=$text; $c.SetBounds($x,$y,$w,36); $form.Controls.Add($c); return $c}
LabelAt 'Steam 安装目录 / Steam installation' 16 14 700 24
$root=BoxAt 16 40 620 24; $root.ReadOnly=$true
$root.Text=Get-CoopSteamLocation $PSScriptRoot
$browse=ButtonAt '浏览 / Browse' 644 35 100
LabelAt '账号：昵称 + ID / Account: nickname + ID' 16 80 350 24
$accounts=New-Object Windows.Forms.ComboBox; $accounts.DropDownStyle='DropDownList'; $accounts.SetBounds(16,106,728,28); $accounts.DisplayMember='Display'; $accounts.DropDownWidth=728; $form.Controls.Add($accounts)
$single=New-Object Windows.Forms.CheckBox; $single.Text='单核兼容模式 / Single-core compatibility'; $single.SetBounds(16,136,728,30); $form.Controls.Add($single)
LabelAt '将使用的启动选项 / Generated launch options' 16 186 720 24
$options=BoxAt 16 212 728 76; $options.Multiline=$true; $options.ReadOnly=$true
LabelAt '当前启动选项（应用时替换）/ Current launch options (replaced on Apply)' 16 300 728 24
$current=BoxAt 16 326 728 68; $current.Multiline=$true; $current.ReadOnly=$true
LabelAt "应用将正常退出 Steam，备份并修改所选账号的本游戏配置，再重启 Steam。请先结束游戏。`r`nApply closes Steam normally, backs up this game's setting for the selected account, then restarts Steam. Finish your games first." 16 410 728 65
$status=New-Object Windows.Forms.Label; $status.SetBounds(16,484,728,70); $form.Controls.Add($status)
$copy=ButtonAt '复制 / Copy' 16 566 150
$apply=ButtonAt '应用并重启 Steam / Apply and restart Steam' 180 566 390
$close=ButtonAt '关闭 / Close' 584 566 160
$script:busy=$false
function RefreshOption {$options.Text=Get-CoopSteamLaunchOption $PSScriptRoot -MultiCore:(!$single.Checked)}
function RefreshAccount {
 $apply.Enabled=$false; $current.Text=''
 if($accounts.SelectedIndex -ge 0){try {$current.Text=Read-CoopSteamLaunchOption $root.Text ([string]$accounts.SelectedItem.Id); $apply.Enabled=$true; $status.Text=''}catch{$status.Text=$_.Exception.Message}}
}
function RefreshAccounts {
 $accounts.Items.Clear()
 if($root.Text){foreach($item in @(Get-CoopSteamAccountDetails $root.Text | Sort-Object -Property @{Expression='IsActive';Descending=$true},@{Expression='IsRecent';Descending=$true},Id)){$null=$accounts.Items.Add($item)}}
 foreach($item in $accounts.Items){if($item.IsActive){$accounts.SelectedItem=$item; break}}
 if($accounts.SelectedIndex -lt 0 -and $accounts.Items.Count -eq 1){$accounts.SelectedIndex=0}
 RefreshAccount
 if($accounts.SelectedIndex -lt 0){$status.Text='无法确认当前账号，请按昵称选择；最近登录不一定是当前账号。也可直接复制启动选项。 / Current account unknown. Select by nickname; last login may differ. Copy is also available.'}
}
$accounts.Add_SelectedIndexChanged({RefreshAccount})
$single.Add_CheckedChanged({RefreshOption})
$browse.Add_Click({$d=New-Object Windows.Forms.OpenFileDialog; $d.Filter='Steam|steam.exe'; if($d.ShowDialog() -eq 'OK'){$root.Text=Split-Path $d.FileName -Parent; RefreshAccounts}; $d.Dispose()})
$copy.Add_Click({[Windows.Forms.Clipboard]::SetText($options.Text); $status.Text='已复制，请粘贴到 Steam 游戏属性的启动选项。 / Copied. Paste into the game Launch Options in Steam Properties.'})
$close.Add_Click({$form.Close()})
$form.Add_FormClosing({param($sender,$e) if($script:busy){$e.Cancel=$true}})
$apply.Add_Click({
 if($script:busy){return}
 $script:busy=$true
 foreach($c in @($browse,$accounts,$single,$copy,$apply,$close)){$c.Enabled=$false}
 try {
  $result=Invoke-CoopSteamConfiguration $root.Text ([string]$accounts.SelectedItem.Id) $options.Text -Progress {param($message) $status.Text=$message; [Windows.Forms.Application]::DoEvents()}
  $status.Text='已应用并启动 Steam。 / Applied; Steam restarted.'
  if($result.Backup){$status.Text+="`r`n备份 / Backup: "+$result.Backup}
  $current.Text=$options.Text
 } catch {[Windows.Forms.MessageBox]::Show($_.Exception.Message,'设置失败 / Setup failed') | Out-Null; $status.Text='未完成，请检查提示。 / Not completed; check the error message.'}
 finally {$script:busy=$false; foreach($c in @($browse,$accounts,$single,$copy,$apply,$close)){$c.Enabled=$true}}
})
RefreshOption; RefreshAccounts
if($loading){$loading.Dispose(); $loading=$null}
if($UiCheckOnly){
 if(!$options.Text -or !$form.Controls.Count){throw 'GUI initialization failed'}
 foreach($item in $accounts.Items){
  if($item.Id -notmatch '^\d+$' -or $accounts.GetItemText($item) -cne $item.Display){throw 'Account display/ID binding failed'}
 }
  if($single.Checked -or !$options.Text.Contains('Start Online Co-op Multi Core.vbs')){throw 'Default must be multi-core'}
 $single.Checked=$true
 if(!$options.Text.Contains('Start Online Co-op.vbs')){throw 'Checked must select single-core'}
 $single.Checked=$false
 if(!$options.Text.Contains('Start Online Co-op Multi Core.vbs')){throw 'Unchecked must select multi-core'}
 Write-Output ('GUI initialized; CPU toggle verified; Steam accounts: '+$accounts.Items.Count)
 $form.Dispose(); exit
}
$null=$form.ShowDialog(); $form.Dispose()
