# VU3INI Android TV Cleaner - CleanYourTV PowerShell
# Opens a PowerShell in the bundled cleanyourtv folder with the bundled JDK, Android SDK, Gradle cache
# and Python venv on the environment, so the repo's own scripts run offline exactly as its README shows.
param([string]$TvHost = '')

$App = Split-Path -Parent $MyInvocation.MyCommand.Path
$Repo = Join-Path $App 'cleanyourtv'

$env:JAVA_HOME        = Join-Path $App 'jdk'
$env:ANDROID_HOME     = Join-Path $App 'android-sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:GRADLE_USER_HOME = Join-Path $App 'gradle-home'
$env:PYTHONUTF8       = '1'
$env:PYTHONNOUSERSITE = '1'
$env:PIP_NO_INDEX     = '1'
$env:PATH = @(
    (Join-Path $Repo 'tools\venv\Scripts'),
    (Join-Path $env:JAVA_HOME 'bin'),
    (Join-Path $env:ANDROID_HOME 'platform-tools'),
    $env:PATH
) -join ';'
if ($TvHost) { $env:TV_HOST = $TvHost }

Set-Location $Repo
$Host.UI.RawUI.WindowTitle = 'VU3INI Android TV Cleaner - CleanYourTV PowerShell'

if (-not (Test-Path 'tools\venv\Scripts\python.exe')) {
    Write-Host 'Step 2 is not finished: open VU3INI Android TV Cleaner and press "Run Step 2 setup" first.' -ForegroundColor Red
}

$tv = if ($env:TV_HOST) { $env:TV_HOST } else { '<not set: $env:TV_HOST = "192.168.1.50">' }
Write-Host ''
Write-Host ' VU3INI Android TV Cleaner  -  CleanYourTV, offline toolchain loaded' -ForegroundColor Cyan
Write-Host " TV_HOST = $tv" -ForegroundColor Cyan
Write-Host ''
Write-Host ' Step 3  probe the TV:      tools\venv\Scripts\python.exe -I tools\tv.py --probe'
Write-Host ' Step 4  review the list:   notepad examples\oneplus-tv-<yours>\debloat.txt'
Write-Host '         (OnePlus folders:  oneplus-tv-cebu, oneplus-tv-dosa, oneplus-tv-dubai, oneplus-tv-y1)'
Write-Host ' Step 5  debloat:           .\tools\disable.ps1 examples\oneplus-tv-<yours>\debloat.txt'
Write-Host ' Step 6  new home screen:   .\launcher\build-and-install.ps1'
Write-Host ' Step 7  run Step 5 again (now the stock launcher lines apply), then reboot the TV'
Write-Host ' Step 8  after disabling debugging + reboot:  tools\venv\Scripts\python.exe -I tools\adb-closed.py $env:TV_HOST'
Write-Host ' Undo:   .\tools\restore.ps1 examples\oneplus-tv-<yours>\debloat.txt'
Write-Host ''
