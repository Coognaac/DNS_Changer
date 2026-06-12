<#
  DNS Manager Script
  Save as: C:\Tools\dns-manager.ps1
  Run PowerShell as Administrator before executing.
#>

# --- Check for Administrator Privileges ---
function Test-IsElevated {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsElevated)) {
    Write-Host "⚠️  Please run this script as Administrator!" -ForegroundColor Yellow
    exit 1
}

# --- Function: Get Active Network Adapter ---
function Get-ActiveAdapter {
    $adapters = Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' } -ErrorAction SilentlyContinue
    if (-not $adapters) {
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } -ErrorAction SilentlyContinue
    }
    if (-not $adapters) {
        Write-Host "❌ No active network adapters found." -ForegroundColor Red
        return $null
    }

    if ($adapters.Count -gt 1) {
        Write-Host "Multiple active adapters found:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $adapters.Count; $i++) {
            Write-Host "[$i] $($adapters[$i].Name) - $($adapters[$i].InterfaceDescription)"
        }
        $sel = Read-Host "Enter the adapter number"
        if ($sel -notmatch '^\d+$' -or [int]$sel -lt 0 -or [int]$sel -ge $adapters.Count) {
            Write-Host "❌ Invalid selection." -ForegroundColor Red
            return $null
        }
        return $adapters[[int]$sel].Name
    } else {
        return $adapters[0].Name
    }
}

# --- Function: Validate IPv4 Address ---
function Test-IPv4($ip) {
    return $ip -match '^([0-9]{1,3}\.){3}[0-9]{1,3}$'
}

# --- Function: Set Custom DNS ---
function Set-CustomDNS {
    $adapterName = Get-ActiveAdapter
    if (-not $adapterName) { return }

    $primary = Read-Host "Enter Primary DNS (e.g., 8.8.8.8)"
    if (-not (Test-IPv4 $primary)) {
        Write-Host "❌ Invalid Primary DNS address." -ForegroundColor Red
        return
    }

    $secondary = Read-Host "Enter Secondary DNS (optional, press Enter to skip)"
    if ($secondary -and -not (Test-IPv4 $secondary)) {
        Write-Host "❌ Invalid Secondary DNS address." -ForegroundColor Red
        return
    }

    $servers = @($primary)
    if ($secondary) { $servers += $secondary }

    Write-Host "Setting DNS for adapter '${adapterName}' to: $($servers -join ', ')" -ForegroundColor Cyan
    try {
        Set-DnsClientServerAddress -InterfaceAlias $adapterName -ServerAddresses $servers -ErrorAction Stop
        Write-Host "✅ DNS successfully updated." -ForegroundColor Green
    } catch {
        Write-Host "⚠️ Failed with Set-DnsClientServerAddress, trying netsh..." -ForegroundColor Yellow
        try {
            netsh interface ip set dns name="$adapterName" static $primary
            if ($secondary) { netsh interface ip add dns name="$adapterName" $secondary index=2 }
            Write-Host "✅ DNS updated using netsh." -ForegroundColor Green
        } catch {
            Write-Host "❌ Failed to set DNS: $_" -ForegroundColor Red
        }
    }

    try {
        ipconfig /flushdns | Out-Null
        Write-Host "🧹 DNS cache flushed." -ForegroundColor DarkGreen
    } catch {
        Write-Host "⚠️ Could not flush DNS cache." -ForegroundColor Yellow
    }
}

# --- Function: Reset DNS to DHCP ---
function Reset-DNS-DHCP {
    $adapterName = Get-ActiveAdapter
    if (-not $adapterName) { return }

    Write-Host "Resetting DNS to DHCP for adapter '${adapterName}'..." -ForegroundColor Yellow
    try {
        Set-DnsClientServerAddress -InterfaceAlias $adapterName -ResetServerAddresses -ErrorAction Stop
        Write-Host "✅ DNS successfully reset to DHCP." -ForegroundColor Green
    } catch {
        Write-Host "⚠️ Failed with Set-DnsClientServerAddress, trying netsh..." -ForegroundColor Yellow
        try {
            netsh interface ip set dns name="$adapterName" dhcp
            Write-Host "✅ DNS reset to DHCP using netsh." -ForegroundColor Green
        } catch {
            Write-Host "❌ Failed to reset DNS: $_" -ForegroundColor Red
        }
    }

    try {
        ipconfig /flushdns | Out-Null
        Write-Host "🧹 DNS cache flushed." -ForegroundColor DarkGreen
    } catch {
        Write-Host "⚠️ Could not flush DNS cache." -ForegroundColor Yellow
    }
}

# --- Function: Show Current DNS ---
function Show-CurrentDNS {
    $adapterName = Get-ActiveAdapter
    if (-not $adapterName) { return }

    Write-Host "Current DNS for adapter ${adapterName}:" -ForegroundColor Cyan
    try {
        $dns = Get-DnsClientServerAddress -InterfaceAlias $adapterName -AddressFamily IPv4 | Select-Object -ExpandProperty ServerAddresses
        if ($dns) {
            $dns | ForEach-Object { Write-Host "→ $_" -ForegroundColor Green }
        } else {
            Write-Host "No DNS servers configured (probably using DHCP)." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "❌ Failed to retrieve DNS information." -ForegroundColor Red
    }
}

# --- Main Menu ---
do {
    Write-Host ""
    Write-Host "===== DNS Manager Menu =====" -ForegroundColor Cyan
    Write-Host "1. Set custom DNS (Primary & Secondary)"
    Write-Host "2. Reset DNS to DHCP"
    Write-Host "3. Show current DNS"
    Write-Host "4. Exit"
    $choice = Read-Host "Enter your choice (1-4)"

    switch ($choice) {
        1 { Set-CustomDNS }
        2 { Reset-DNS-DHCP }
        3 { Show-CurrentDNS }
        4 { Write-Host "Exiting..." -ForegroundColor Yellow }
        default { Write-Host "Invalid choice, please try again." -ForegroundColor Red }
    }
} while ($choice -ne '4')
