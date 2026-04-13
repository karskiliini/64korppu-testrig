# 64korppu — Windows-puolen asennus (WSL2 test rig)
#
# Aja PowerShellissä järjestelmänvalvojana:
#   Invoke-WebRequest -Uri "https://raw.githubusercontent.com/karskiliini/64korppu-testrig/main/windows-setup.ps1" -OutFile "$env:TEMP\windows-setup.ps1"; & "$env:TEMP\windows-setup.ps1"
#
# Asentaa: Tailscale, usbipd-win, OpenSSH Server
# Konfiguroi SSH:n käyttämään WSL Ubuntua oletusshellina

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

function Write-Step($num, $total, $msg) {
    Write-Host "[$num/$total] " -ForegroundColor Yellow -NoNewline
    Write-Host $msg
}
function Write-OK($msg) {
    Write-Host "[OK] " -ForegroundColor Green -NoNewline
    Write-Host $msg
}
function Write-Warn($msg) {
    Write-Host "[!] " -ForegroundColor Red -NoNewline
    Write-Host $msg
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  64korppu Test Rig — Windows Setup (WSL2)" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

$totalSteps = 6

# ── 1. Tarkista WSL2 ───────────────────────────────────────

Write-Step 1 $totalSteps "Tarkistetaan WSL2..."

$wslStatus = wsl --status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Warn "WSL2 ei ole asennettu. Asennetaan..."
    wsl --install -d Ubuntu-24.04
    Write-Host ""
    Write-Warn "WSL asennettu. Kaynnista kone uudelleen ja aja tama skripti uudelleen."
    exit 1
}

# Päivitä WSL-kernel
Write-Host "  Paivitetaan WSL-kernel..." -ForegroundColor Gray
wsl --update 2>&1 | Out-Null
Write-OK "WSL2 kaytossa"

# ── 2. usbipd-win ──────────────────────────────────────────

Write-Step 2 $totalSteps "Asennetaan usbipd-win (USB-passthrough)..."

$usbipdInstalled = Get-Command usbipd -ErrorAction SilentlyContinue
if ($usbipdInstalled) {
    Write-OK "usbipd-win jo asennettu"
} else {
    Write-Host "  Asennetaan winget:lla..." -ForegroundColor Gray
    winget install --exact --silent dorssel.usbipd-win --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "winget-asennus epaonnistui. Lataa manuaalisesti:"
        Write-Host "  https://github.com/dorssel/usbipd-win/releases" -ForegroundColor Yellow
    } else {
        Write-OK "usbipd-win asennettu"
        Write-Host ""
        Write-Warn "usbipd-win vaatii koneen uudelleenkaynnistyksen ensimmaisella kerralla."
        Write-Host "  Kaynnista kone uudelleen ja aja tama skripti uudelleen." -ForegroundColor Yellow
        Write-Host "  (Jos olet jo kaynnistanyt uudelleen, jatka painamalla Enter)" -ForegroundColor Yellow
        Read-Host
    fi
}

# ── 3. Tailscale ───────────────────────────────────────────

Write-Step 3 $totalSteps "Asennetaan Tailscale..."

$tailscaleInstalled = Get-Command tailscale -ErrorAction SilentlyContinue
if (-not $tailscaleInstalled) {
    # Tarkista myös vakiopolku
    $tailscaleInstalled = Test-Path "C:\Program Files\Tailscale\tailscale.exe"
}

if ($tailscaleInstalled) {
    Write-OK "Tailscale jo asennettu"
} else {
    Write-Host "  Asennetaan winget:lla..." -ForegroundColor Gray
    winget install --exact --silent Tailscale.Tailscale --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "winget-asennus epaonnistui. Lataa manuaalisesti:"
        Write-Host "  https://tailscale.com/download/windows" -ForegroundColor Yellow
    } else {
        Write-OK "Tailscale asennettu"
    }
}

# Yhdistä Tailscaleen
Write-Host "  Tarkistetaan Tailscale-yhteys..." -ForegroundColor Gray
$tsExe = "C:\Program Files\Tailscale\tailscale.exe"
if (Test-Path $tsExe) {
    $tsStatus = & $tsExe status 2>&1
    if ($tsStatus -match "stopped" -or $LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "  Kaynnistetaan Tailscale — avaa selaimessa nakyva linkki:" -ForegroundColor Yellow
        & $tsExe up
    }
    $tsIP = & $tsExe ip -4 2>&1
    if ($tsIP -match "^\d+\.\d+\.\d+\.\d+$") {
        Write-OK "Tailscale yhdistetty (IP: $tsIP)"
    }
} else {
    Write-Warn "Kaynnista Tailscale-sovellus ja kirjaudu sisaan"
}

# ── 4. OpenSSH Server ──────────────────────────────────────

Write-Step 4 $totalSteps "OpenSSH-palvelin..."

$sshCapability = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
if ($sshCapability.State -eq 'Installed') {
    Write-OK "OpenSSH Server jo asennettu"
} else {
    Write-Host "  Asennetaan OpenSSH Server..." -ForegroundColor Gray
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
    Write-OK "OpenSSH Server asennettu"
}

# Käynnistä ja aseta automaattiseksi
Start-Service sshd -ErrorAction SilentlyContinue
Set-Service -Name sshd -StartupType Automatic

# Salli palomuuri
$fwRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
if (-not $fwRule) {
    New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH Server (sshd)" `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
}

Write-OK "SSH-palvelin kaynnissa (portti 22)"

# ── 5. SSH → WSL bash ──────────────────────────────────────

Write-Step 5 $totalSteps "Konfiguroidaan SSH kayttamaan WSL:aa..."

# Aseta WSL bash oletusshellksi SSH-yhteyksille
$wslPath = "C:\Windows\System32\wsl.exe"
if (Test-Path $wslPath) {
    $currentShell = (Get-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -ErrorAction SilentlyContinue).DefaultShell
    if ($currentShell -ne $wslPath) {
        New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value $wslPath -PropertyType String -Force | Out-Null
        Write-OK "SSH default shell → WSL ($wslPath)"
    } else {
        Write-OK "SSH default shell on jo WSL"
    }
} else {
    Write-Warn "wsl.exe ei loytynyt!"
}

# authorized_keys — kopioi WSL:stä jos löytyy
$winSSHDir = "$env:USERPROFILE\.ssh"
if (-not (Test-Path $winSSHDir)) {
    New-Item -ItemType Directory -Path $winSSHDir -Force | Out-Null
}
$authKeysPath = "$winSSHDir\authorized_keys"
if (-not (Test-Path $authKeysPath)) {
    New-Item -ItemType File -Path $authKeysPath -Force | Out-Null
}

Write-OK "authorized_keys: $authKeysPath"

# ── 6. Arduino USB-liitäntä ────────────────────────────────

Write-Step 6 $totalSteps "Arduino USB-tunnistus..."

$usbipdExe = Get-Command usbipd -ErrorAction SilentlyContinue
if ($usbipdExe) {
    Write-Host ""
    Write-Host "  Kytketyt USB-laitteet:" -ForegroundColor Gray
    usbipd list 2>&1 | ForEach-Object { Write-Host "    $_" }

    # Etsi Arduino (CH340/FTDI/ATmega16U2)
    $devices = usbipd list 2>&1
    $arduinoLine = $devices | Where-Object { $_ -match "1a86:7523|0403:6001|2341:0043" }

    if ($arduinoLine) {
        $busId = ($arduinoLine -split "\s+")[0]
        Write-Host ""
        Write-OK "Arduino loytyi (BUS-ID: $busId)"
        Write-Host ""
        Write-Host "  Liita Arduino WSL:aan:" -ForegroundColor Yellow
        Write-Host "    usbipd bind --busid $busId" -ForegroundColor White
        Write-Host "    usbipd attach --wsl --auto-attach --busid $busId" -ForegroundColor White
        Write-Host ""
        Write-Host "  --auto-attach pitaa yhteyden yllä myos" -ForegroundColor Gray
        Write-Host "  Arduino-resetin yli (avrdude flash)." -ForegroundColor Gray

        # Tarjoa automaattinen bind+attach
        Write-Host ""
        $response = Read-Host "  Liitetaanko Arduino nyt WSL:aan? (k/e)"
        if ($response -eq "k" -or $response -eq "K" -or $response -eq "y") {
            usbipd bind --busid $busId 2>&1 | Out-Null
            Start-Process -FilePath "usbipd" -ArgumentList "attach --wsl --auto-attach --busid $busId" -NoNewWindow
            Start-Sleep -Seconds 2
            Write-OK "Arduino liitetty WSL:aan (auto-attach paalla)"
        }
    } else {
        Write-Warn "Arduinoa ei loytynyt. Kytke se USB:lla ja aja:"
        Write-Host "    usbipd list" -ForegroundColor White
        Write-Host "    usbipd bind --busid <BUS-ID>" -ForegroundColor White
        Write-Host "    usbipd attach --wsl --auto-attach --busid <BUS-ID>" -ForegroundColor White
    }
} else {
    Write-Warn "usbipd ei viela kaytettavissa (kaynnista kone uudelleen ensin)"
}

# ── Valmis ──────────────────────────────────────────────────

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  Windows-setup valmis!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""

# Näytä yhteenveto
$tsExe = "C:\Program Files\Tailscale\tailscale.exe"
$tsIP = "???"
if (Test-Path $tsExe) {
    $tsIP = & $tsExe ip -4 2>&1
}
$winUser = $env:USERNAME

Write-Host "  Laheta nama tiedot veljellesi:" -ForegroundColor White
Write-Host ""
Write-Host "  ┌─────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "  │  Tailscale IP:   $tsIP" -ForegroundColor Cyan
Write-Host "  │  Kayttaja:       $winUser" -ForegroundColor Cyan
Write-Host "  └─────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""
Write-Host "  SSH-avain lisataan tiedostoon:" -ForegroundColor Gray
Write-Host "    $authKeysPath" -ForegroundColor White
Write-Host ""

# Tarkista onko WSL-puolen install.sh ajettu
$wslCheck = wsl --exec bash -c "test -f ~/tools/health.sh && echo ok" 2>&1
if ($wslCheck -ne "ok") {
    Write-Host "  Seuraava vaihe: aja WSL-terminaalissa:" -ForegroundColor Yellow
    Write-Host '    curl -fsSL https://raw.githubusercontent.com/karskiliini/64korppu-testrig/main/install.sh | bash' -ForegroundColor White
    Write-Host ""
} else {
    Write-Host "  WSL-puoli on jo asennettu. Tarkista:" -ForegroundColor Green
    Write-Host "    wsl --exec ~/tools/health.sh" -ForegroundColor White
    Write-Host ""
}

Write-Host "  Arduino-liitanta (kun Nano on kytketty):" -ForegroundColor Gray
Write-Host "    usbipd list" -ForegroundColor White
Write-Host "    usbipd bind --busid <BUS-ID>" -ForegroundColor White
Write-Host "    usbipd attach --wsl --auto-attach --busid <BUS-ID>" -ForegroundColor White
Write-Host ""
