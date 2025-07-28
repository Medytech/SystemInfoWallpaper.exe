# ---------------------------------------------
# Skriptname: SystemInfoWallpaper.ps1
# Beschreibung: Zeigt Netzwerk- und Systeminfos als Bild unten rechts auf dem Desktop an
# Autor: Mark Zimmermann
# Datum: 28.07.2025
# ---------------------------------------------

function Get-SubnetMaskFromLength {
    param([int]$MaskLength)
    $binaryMask = ""
    for ($i = 1; $i -le 32; $i++) {
        $binaryMask += if ($i -le $MaskLength) { "1" } else { "0" }
    }
    $octets = @()
    for ($j = 0; $j -lt 4; $j++) {
        $octet = $binaryMask.Substring($j * 8, 8)
        $octets += [convert]::ToInt32($octet, 2)
    }
    return ($octets -join ".")
}

function Get-NetworkInfo {
    $adap = Get-NetIPConfiguration | Where-Object {
        $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq "Up"
    } | Select-Object -First 1
    if (-not $adap) { return $null }

    $gateway = $adap.IPv4DefaultGateway.NextHop
    $ip      = $adap.IPv4Address.IPAddress
    $subnet  = $adap.IPv4Address.PrefixLength
    $mask    = Get-SubnetMaskFromLength $subnet

    # DNS-Server nur über Get-DnsClientServerAddress abfragen
    $ifaceIdx   = $adap.InterfaceIndex
    $dnsServers = (Get-DnsClientServerAddress -InterfaceIndex $ifaceIdx -AddressFamily IPv4).ServerAddresses
    $dns1 = if ($dnsServers.Count -ge 1 -and $dnsServers[0]) { $dnsServers[0] } else { "None" }
    $dns2 = if ($dnsServers.Count -ge 2 -and $dnsServers[1]) { $dnsServers[1] } else { "None" }

    $dhcpList = $adap.DhcpServer.ServerAddresses
    $dhcp     = if ($dhcpList -and $dhcpList.Count -ge 1 -and $dhcpList[0]) { $dhcpList[0] } else { "None" }

    return @{
        Gateway = $gateway
        IP      = $ip
        Mask    = $mask
        DNS1    = $dns1
        DNS2    = $dns2
        DHCP    = $dhcp
    }
}

function Get-SystemInfo {
    $hostname = $env:COMPUTERNAME
    $user     = $env:USERNAME
    $domain   = $env:USERDOMAIN
    $osRaw    = (Get-CimInstance Win32_OperatingSystem).Caption
    $os       = $osRaw -replace "Microsoft\s*", ""
    return @{
        Hostname = $hostname
        User     = $user
        Domain   = $domain
        OS       = $os
    }
}

function Build-InfoText {
    param($net, $sys)
    return @"
Gateway   : $($net.Gateway)
IP        : $($net.IP)
Maske     : $($net.Mask)
DNS 1     : $($net.DNS1)   (bevorzugt)
DNS 2     : $($net.DNS2)   (alternativ)
DHCP      : $($net.DHCP)
Hostname  : $($sys.Hostname)
Benutzer  : $($sys.User)
Domäne    : $($sys.Domain)
OS        : $($sys.OS)
"@
}

function Create-WallpaperImage {
    param(
        [string]$Text,
        [string]$Path,
        [int]$Width = 1920,
        [int]$Height = 1080,
        [int]$marginRight = 560,
        [int]$marginBottom = 260
    )
    Add-Type -AssemblyName System.Drawing
    $bgColor = [System.Drawing.Color]::FromArgb(255, 200, 200, 200)
    $bmp     = New-Object System.Drawing.Bitmap $Width, $Height
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    $graphics.Clear($bgColor)
    $font   = New-Object System.Drawing.Font "Consolas", 14, ([System.Drawing.FontStyle]::Regular)
    $brush  = [System.Drawing.Brushes]::Black
    $lines  = $Text -split "`n"
    $lineHeight  = $graphics.MeasureString("A", $font).Height
    $blockHeight = $lines.Count * $lineHeight

    # Abstand von unten und von rechts
    $startY   = $Height - $blockHeight - $marginBottom
    $maxWidth = ($lines | ForEach-Object { $graphics.MeasureString($_, $font).Width } | Measure-Object -Maximum).Maximum
    $startX   = $Width - $maxWidth - $marginRight

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $graphics.DrawString($lines[$i], $font, $brush, $startX, $startY + $i * $lineHeight)
    }
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Bmp)
    $graphics.Dispose()
    $bmp.Dispose()
}

function Set-Wallpaper {
    param([string]$Path)
    Add-Type @"
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
    $ok = [Wallpaper]::SystemParametersInfo(20, 0, $Path, 3)
    if (-not $ok) {
        Write-Host "Wallpaper-API fehlgeschlagen, versuche Registry-Methode..."
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\" -Name WallPaper -Value $Path
        Start-Sleep -Milliseconds 500
        RUNDLL32.EXE user32.dll,UpdatePerUserSystemParameters
    }
}

function Set-NetworkWallpaper {
    $network = Get-NetworkInfo
    $system  = Get-SystemInfo
    if (-not $network) {
        Write-Host "Kein aktives Netzwerk gefunden!"
        return
    }
    $infoText = Build-InfoText $network $system
    $wallpaperPath = "$env:TEMP\netinfo_wallpaper.bmp"
    Create-WallpaperImage -Text $infoText -Path $wallpaperPath
    Set-Wallpaper -Path $wallpaperPath
    Write-Host "Wallpaper gesetzt: $wallpaperPath"
}

# Hauptaufruf
Set-NetworkWallpaper
