function Resolve-OnlineCoopEndpoint([string]$Text, [switch]$AllowHostname) {
    $value=$Text.Trim()
    if ($value -notmatch '^(?<host>[A-Za-z0-9.-]{1,253})(?::(?<port>\d{1,5}))?$') {
        throw 'Enter IPv4 or hostname:port / 请输入 IPv4 或域名:端口'
    }
    $address=$Matches.host; $portText=$Matches.port
    if ($address -match '^[0-9.]+$') {
        if ($address -notmatch '^\d{1,3}(?:\.\d{1,3}){3}$') { throw 'Invalid IPv4 / IPv4 无效' }
        $octets=@($address.Split('.') | ForEach-Object { [int]$_ })
        if (@($octets | Where-Object { $_ -gt 255 }).Count) { throw 'Invalid IPv4 / IPv4 无效' }
        $address=$octets -join '.'
    } else {
        if (!$AllowHostname) { throw 'Local binding requires IPv4 / 本地监听需填写 IPv4' }
        foreach($label in $address.TrimEnd('.').Split('.')) {
            if ($label -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$') { throw 'Invalid hostname / 域名无效' }
        }
        $address=$address.ToLowerInvariant().TrimEnd('.')
    }
    $port=27841
    if ($portText) { $port=[int]$portText }
    $minimum=if($AllowHostname){1}else{1024}
    if ($port -lt $minimum -or $port -gt 65535) { throw "Port must be $minimum-65535 / 端口超出范围" }
    return [pscustomobject]@{ Address=$address; Port=$port }
}
