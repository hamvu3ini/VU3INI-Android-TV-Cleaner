<#
  VU3INI Android TV Cleaner - offline installer builder
  ----------------------------------------------------
  Run ONCE on a Windows 10/11 x64 PC that has internet. It downloads and assembles everything that
  CleanYourTV's Step 2 needs, proves the toolchain builds the launcher with --offline, compiles the
  app, and produces ONE installer:

      output\VU3INI-Android-TV-Cleaner-Setup-<version>.exe

  That Setup.exe needs no internet at all to install or run, on this PC or any other Windows 10/11 x64.

  Bundled into the installer:
    * Python 3.12 (python.org NuGet build, includes venv/pip) + offline wheels for tools\requirements.txt
    * Eclipse Temurin JDK 17 (full JDK, with javac and jlink)
    * Android SDK: platforms;android-34, build-tools;34.0.0, platform-tools, accepted licences
    * Gradle 8.9 distribution, pre-extracted, plus every Maven dependency of the launcher build
      (Android Gradle Plugin 8.5.2, AndroidX, R8, lint, Windows aapt2) in a ready gradle-home
    * A snapshot of github.com/Gathin23/cleanyourtv (all TV lists, tools, launcher source)
    * The VU3INI Android TV Cleaner app itself

  Usage (or just double-click Build-Installer.cmd):
      powershell -ExecutionPolicy Bypass -File build\Build-Installer.ps1 [-WorkDir C:\VU3INI-build] [-Clean]

  Downloads are cached in <WorkDir>\downloads, so a re-run only fetches what is missing.
  Needs about 8 GB free on the WorkDir drive. Takes 20-40 minutes (most of it the final compression).
#>
param(
    [string]$WorkDir = 'C:\VU3INI-build',
    [string]$PythonVersion = '3.12.10',
    [string]$CmdlineToolsZip = 'commandlinetools-win-11076708_latest.zip',
    [string]$RepoUrl = 'https://github.com/Gathin23/cleanyourtv',
    [string]$RepoBranch = 'main',
    [string]$IsccPath = '',
    [string]$OutputFolder = '',
    [switch]$Clean,
    [switch]$Rebuild
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$AppVersion = '2.0'
$AppName    = 'VU3INI Android TV Cleaner'
$Root       = Split-Path -Parent $PSScriptRoot          # the builder folder
$Src        = Join-Path $Root 'src'
$Branding   = Join-Path $Root 'branding'
$OutDir     = if ($OutputFolder) { $OutputFolder } else { Join-Path $Root 'output' }
$Dl         = Join-Path $WorkDir 'downloads'
$Tmp        = Join-Path $WorkDir 'tmp'
$Stage      = Join-Path $WorkDir 'stage'                 # becomes the install folder {app}

function Step($n, $text) { Write-Host ''; Write-Host "[$n] $text" -ForegroundColor Cyan }
function Info($text)     { Write-Host "    $text" }
function Ok($text)       { Write-Host "    OK  $text" -ForegroundColor Green }
function Fail($text)     { Write-Host ''; Write-Host "FAILED: $text" -ForegroundColor Red; throw $text }

# Runs a program with an exact argument string (cmd.exe quoting is under our control), console output
# shown live, optional text written to its stdin. Returns the exit code.
function Invoke-Proc([string]$File, [string]$Arguments, [string]$WorkingDir = (Get-Location).Path, [string]$StdIn = $null) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo $File, $Arguments
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = $WorkingDir
    if ($StdIn) { $psi.RedirectStandardInput = $true }
    $p = [System.Diagnostics.Process]::Start($psi)
    if ($StdIn) { $p.StandardInput.Write($StdIn); $p.StandardInput.Close() }
    $p.WaitForExit()
    return $p.ExitCode
}

# Same, but returns stdout+stderr as text.
function Get-ProcOutput([string]$File, [string]$Arguments, [string]$WorkingDir = (Get-Location).Path) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo $File, $Arguments
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = $WorkingDir
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    return ($out + $errTask.Result)
}

$Cmd = Join-Path $env:WINDIR 'System32\cmd.exe'
$Curl = Join-Path $env:WINDIR 'System32\curl.exe'
$Tar = Join-Path $env:WINDIR 'System32\tar.exe'

function Get-File([string]$Url, [string]$Name, [switch]$Soft) {
    $dest = Join-Path $Dl $Name
    if ((Test-Path $dest) -and (Get-Item $dest).Length -gt 0) { Info "cached: $Name"; return $dest }
    Info "downloading $Name"
    Info "  from $Url"
    $part = "$dest.part"
    $rc = Invoke-Proc $Curl "-L --fail --retry 4 --retry-delay 5 --progress-bar -A VU3INI-ATVC-builder -o `"$part`" `"$Url`""
    if ($rc -ne 0) {
        Remove-Item -Force $part -ErrorAction SilentlyContinue
        if ($Soft) { Write-Host "    download failed ($rc): $Url" -ForegroundColor Yellow; return $null }
        Fail "download failed ($rc): $Url"
    }
    Move-Item -Force $part $dest
    return $dest
}

function Expand-Zip([string]$Zip, [string]$Dest) {
    if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest }
    New-Item -ItemType Directory -Force $Dest | Out-Null
    $rc = Invoke-Proc $Tar "-xf `"$Zip`" -C `"$Dest`""
    if ($rc -ne 0) { Fail "could not extract $Zip" }
}

function Remove-IfExists([string]$Path) { if (Test-Path $Path) { Remove-Item -Recurse -Force $Path } }

$Csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $Csc)) { Fail ".NET Framework 4 C# compiler not found at $Csc" }

$reuse = (-not $Rebuild) -and (-not $Clean) -and (Test-Path (Join-Path $Stage 'bundle-info.txt')) -and
         (Test-Path (Join-Path $Stage "$AppName.exe")) -and (Test-Path (Join-Path $Stage 'gradle-home\wrapper\dists'))
if ($reuse) {
    Step 0 'Reusing the finished bundle from the last run (steps 1-6 already passed; the app is recompiled)'
    Info ('staged ' + (Get-Item (Join-Path $Stage 'bundle-info.txt')).LastWriteTime.ToString('yyyy-MM-dd HH:mm') + ' in ' + $Stage)
    Info 'to rebuild everything from scratch, run:  Build-Installer.bat -Rebuild'
    New-Item -ItemType Directory -Force $WorkDir, $Dl, $Tmp, $OutDir | Out-Null
} else {
# ---------------------------------------------------------------------------------------------- 0
Step 0 'Checking this PC'
if (-not [Environment]::Is64BitOperatingSystem) { Fail 'a 64-bit Windows is required' }
foreach ($t in @($Curl, $Tar)) { if (-not (Test-Path $t)) { Fail "$t not found (Windows 10 1803+ / Windows 11 ship it)" } }
if ($WorkDir -match ' ') { Fail "WorkDir must not contain spaces (Gradle/Android SDK): $WorkDir" }
New-Item -ItemType Directory -Force $WorkDir, $Dl, $Tmp, $OutDir | Out-Null
$drive = (Get-Item $WorkDir).PSDrive
if ($drive.Free -lt 8GB) { Fail ("need about 8 GB free on {0}: (have {1:N1} GB)" -f $drive.Name, ($drive.Free / 1GB)) }
if ($Clean) { Info 'Clean: removing previous temp files (downloads are kept)'; Remove-IfExists $Tmp; New-Item -ItemType Directory -Force $Tmp | Out-Null }
Remove-IfExists $Stage
New-Item -ItemType Directory -Force $Stage | Out-Null
Ok "work folder $WorkDir"

# ---------------------------------------------------------------------------------------------- 1
Step 1 "Python $PythonVersion (NuGet build: full stdlib with venv and pip, no installer, no registry)"
$nupkg = Get-File "https://www.nuget.org/api/v2/package/python/$PythonVersion" "python.$PythonVersion.nupkg"
Expand-Zip $nupkg (Join-Path $Tmp 'python')
Copy-Item -Recurse (Join-Path $Tmp 'python\tools') (Join-Path $Stage 'python')
$Py = Join-Path $Stage 'python\python.exe'
$pyCheck = Get-ProcOutput $Py '-c "import venv, ensurepip, ssl, sqlite3, sys; print(sys.version.split()[0])"'
if (-not ($pyCheck.Trim() -match '^\d+\.\d+\.\d+$')) { Fail "bundled Python is incomplete: $pyCheck" }
$PyVer = $pyCheck.Trim()
Ok "Python $PyVer"

# ---------------------------------------------------------------------------------------------- 2
Step 2 'Eclipse Temurin JDK 17 (full JDK; the launcher build needs javac and jlink, JDK 23+ breaks Gradle 8.9)'
$jdkZip = Get-File 'https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse' 'temurin-jdk17-win-x64.zip'
Expand-Zip $jdkZip (Join-Path $Tmp 'jdk')
$inner = Get-ChildItem (Join-Path $Tmp 'jdk') -Directory | Select-Object -First 1
Move-Item $inner.FullName (Join-Path $Stage 'jdk')
$Jdk = Join-Path $Stage 'jdk'
foreach ($b in 'java.exe', 'javac.exe', 'jlink.exe') { if (-not (Test-Path "$Jdk\bin\$b")) { Fail "JDK missing bin\$b" } }
$JdkVer = ((Get-Content "$Jdk\release" | Where-Object { $_ -match '^JAVA_VERSION=' }) -replace '^JAVA_VERSION="?([^"]+)"?', '$1')
Ok "Temurin $JdkVer"

$env:JAVA_HOME = $Jdk
$env:PATH = "$Jdk\bin;$env:PATH"

# ---------------------------------------------------------------------------------------------- 3
Step 3 'Android SDK: platform 34, build-tools 34.0.0, platform-tools (licences accepted)'
$ctZip = Get-File "https://dl.google.com/android/repository/$CmdlineToolsZip" $CmdlineToolsZip
$ctRoot = Join-Path $Tmp 'sdk-tools'
Expand-Zip $ctZip $ctRoot
New-Item -ItemType Directory -Force (Join-Path $ctRoot 'cmdline-tools-root') | Out-Null
Move-Item (Join-Path $ctRoot 'cmdline-tools') (Join-Path $ctRoot 'cmdline-tools-root\latest')
$sdkm = Join-Path $ctRoot 'cmdline-tools-root\latest\bin\sdkmanager.bat'
$Sdk = Join-Path $Stage 'android-sdk'
New-Item -ItemType Directory -Force $Sdk | Out-Null
$yes = ("y`r`n" * 40)
Info 'accepting SDK licences'
$rc = Invoke-Proc $Cmd "/d /s /c `"`"$sdkm`" --sdk_root=`"$Sdk`" --licenses`"" $Tmp $yes
if ($rc -ne 0) { Fail 'sdkmanager --licenses failed' }
Info 'installing packages (about 250 MB)'
$rc = Invoke-Proc $Cmd "/d /s /c `"`"$sdkm`" --sdk_root=`"$Sdk`" `"platforms;android-34`" `"build-tools;34.0.0`" `"platform-tools`"`"" $Tmp $yes
if ($rc -ne 0) { Fail 'sdkmanager install failed' }
foreach ($p in 'platforms\android-34\android.jar', 'build-tools\34.0.0\aapt2.exe', 'platform-tools\adb.exe', 'licenses\android-sdk-license') {
    if (-not (Test-Path (Join-Path $Sdk $p))) { Fail "SDK is missing $p" }
}
Remove-IfExists (Join-Path $Sdk '.temp')
Remove-IfExists (Join-Path $Sdk '.downloadIntermediates')
Ok 'Android SDK ready'
$env:ANDROID_HOME = $Sdk
$env:ANDROID_SDK_ROOT = $Sdk

# ---------------------------------------------------------------------------------------------- 4
Step 4 "CleanYourTV repository snapshot ($RepoUrl, branch $RepoBranch)"
$Repo = Join-Path $Stage 'cleanyourtv'
$git = Get-Command git.exe -ErrorAction SilentlyContinue
$RepoCommit = ''
$RepoDate = ''
if ($git) {
    $rc = Invoke-Proc $git.Source "clone --depth 1 --branch $RepoBranch `"$RepoUrl`" `"$Repo`""
    if ($rc -ne 0) { Fail 'git clone failed' }
    $RepoCommit = (Get-ProcOutput $git.Source 'rev-parse HEAD' $Repo).Trim()
    $RepoDate = (Get-ProcOutput $git.Source 'log -1 --format=%cs' $Repo).Trim()
    Get-ChildItem -Recurse -Force (Join-Path $Repo '.git') | ForEach-Object { $_.Attributes = 'Normal' }
    Remove-IfExists (Join-Path $Repo '.git')
} else {
    Info 'git not found, using the GitHub zip'
    $zipName = "cleanyourtv-$RepoBranch-" + (Get-Date -Format 'yyyyMMdd') + '.zip'
    $z = Get-File "$RepoUrl/archive/refs/heads/$RepoBranch.zip" $zipName
    Expand-Zip $z (Join-Path $Tmp 'repo')
    $inner = Get-ChildItem (Join-Path $Tmp 'repo') -Directory | Select-Object -First 1
    Move-Item $inner.FullName $Repo
    try {
        $api = $RepoUrl -replace '^https://github.com/', 'https://api.github.com/repos/'
        $c = Invoke-RestMethod "$api/commits/$RepoBranch" -Headers @{ 'User-Agent' = 'VU3INI-ATVC-builder' }
        $RepoCommit = $c.sha
        $RepoDate = ([datetime]$c.commit.committer.date).ToString('yyyy-MM-dd')
    } catch { $RepoCommit = 'unknown'; $RepoDate = (Get-Date -Format 'yyyy-MM-dd') }
}
foreach ($p in 'tools\tv.py', 'tools\disable.ps1', 'tools\restore.ps1', 'tools\requirements.txt', 'launcher\gradlew.bat', 'launcher\build-and-install.ps1') {
    if (-not (Test-Path (Join-Path $Repo $p))) { Fail "repository snapshot is missing $p" }
}
# Make the repo's own build script stay offline: add --offline to its Gradle call.
$bai = Join-Path $Repo 'launcher\build-and-install.ps1'
$text = [IO.File]::ReadAllText($bai)
$pattern = '.\gradlew.bat assembleRelease -q --console=plain'
if ($text.Contains($pattern) -and -not $text.Contains("$pattern --offline")) {
    $text = $text.Replace($pattern, "$pattern --offline")
    [IO.File]::WriteAllText($bai, $text, (New-Object System.Text.UTF8Encoding $false))
    Ok 'patched launcher\build-and-install.ps1 to build with --offline'
} else {
    Write-Host '    note: Gradle line in build-and-install.ps1 changed upstream; not patched (the offline cache still serves it)' -ForegroundColor Yellow
}
$examples = (Get-ChildItem (Join-Path $Repo 'examples') -Directory).Count
Ok "snapshot $RepoCommit ($RepoDate), $examples TV lists"

# ---------------------------------------------------------------------------------------------- 5
Step 5 'Offline Python wheels for tools\requirements.txt, and a test venv'
$Wheels = Join-Path $Stage 'wheels'
New-Item -ItemType Directory -Force $Wheels | Out-Null
$req = Join-Path $Repo 'tools\requirements.txt'
# pip wheel turns any source-only package (adb-shell 0.4.4 has no wheel on PyPI) into a wheel now,
# while there is internet, so the offline install never needs setuptools or a build step.
$rc = Invoke-Proc $Py "-m pip wheel --disable-pip-version-check -r `"$req`" -w `"$Wheels`""
if ($rc -ne 0) { Fail 'pip wheel failed' }
Get-ChildItem $Wheels -File | Where-Object { $_.Name -notlike '*.whl' } | Remove-Item -Force
foreach ($w in 'adb_shell-*.whl', 'rsa-*.whl', 'cryptography-*.whl') {
    if (-not (Get-ChildItem $Wheels -Filter $w)) { Fail "no wheel for $w" }
}
$venvTest = Join-Path $Tmp 'venvtest'
Remove-IfExists $venvTest
if ((Invoke-Proc $Py "-m venv `"$venvTest`"") -ne 0) { Fail 'the bundled Python cannot create a venv' }
$vpy = Join-Path $venvTest 'Scripts\python.exe'
if ((Invoke-Proc $vpy "-m pip install --disable-pip-version-check --no-index --find-links `"$Wheels`" -r `"$req`"") -ne 0) { Fail 'offline wheel install failed' }
if ((Invoke-Proc $vpy '-c "import adb_shell, rsa, cryptography"') -ne 0) { Fail 'packages do not import' }
Remove-IfExists $venvTest
Ok ("{0} wheels, offline venv install verified" -f (Get-ChildItem $Wheels).Count)

# ---------------------------------------------------------------------------------------------- 6
Step 6 'Gradle 8.9 + all launcher build dependencies into a bundled gradle-home'
$GradleHome = Join-Path $Stage 'gradle-home'
$env:GRADLE_USER_HOME = $GradleHome
$Launcher = Join-Path $Repo 'launcher'
"sdk.dir=$($Sdk -replace '\\', '\\')" | Out-File -Encoding ascii (Join-Path $Launcher 'local.properties')
# Gradle's wrapper downloads with Java and a 10 s timeout, which fails on some networks (the redirect to
# GitHub's file servers). Fetch the distribution with curl instead, verify it, and place it exactly where
# the wrapper looks: <GRADLE_USER_HOME>\wrapper\dists\<name>\<base36 MD5 of the URL>\<name>.zip
function Get-WrapperHash([string]$Text) {
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $num = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))
    $digits = '0123456789abcdefghijklmnopqrstuvwxyz'
    $out = ''
    while (@($num | Where-Object { $_ -ne 0 }).Count -gt 0) {
        $rem = 0
        for ($i = 0; $i -lt $num.Length; $i++) {
            $cur = $rem * 256 + $num[$i]
            $num[$i] = [byte][int][Math]::Floor($cur / 36)
            $rem = $cur % 36
        }
        $out = $digits.Substring($rem, 1) + $out
    }
    return $out
}
$wrapperProps = Get-Content (Join-Path $Launcher 'gradle\wrapper\gradle-wrapper.properties')
$distUrl = (($wrapperProps | Where-Object { $_ -match '^distributionUrl=' }) -replace '^distributionUrl=', '').Trim().Replace('\:', ':')
$distSha = (($wrapperProps | Where-Object { $_ -match '^distributionSha256Sum=' }) -replace '^distributionSha256Sum=', '').Trim()
$distZipName = $distUrl.Substring($distUrl.LastIndexOf('/') + 1)
$distName = [IO.Path]::GetFileNameWithoutExtension($distZipName)
$distHash = Get-WrapperHash $distUrl
if ($distUrl -eq 'https://services.gradle.org/distributions/gradle-8.9-bin.zip' -and $distHash -ne '90cnw93cvbtalezasaz0blq0a') {
    Fail "wrapper hash self-test failed ($distHash)"
}
$distZip = Get-File $distUrl $distZipName
if ($distSha) {
    $got = (Get-FileHash $distZip -Algorithm SHA256).Hash.ToLower()
    if ($got -ne $distSha.ToLower()) { Remove-Item -Force $distZip; Fail "Gradle download is corrupt (SHA-256 $got); run again" }
    Ok 'Gradle distribution SHA-256 verified'
}
$distDir = Join-Path $GradleHome "wrapper\dists\$distName\$distHash"
New-Item -ItemType Directory -Force $distDir | Out-Null
Copy-Item -Force $distZip (Join-Path $distDir $distZipName)
Ok "pre-seeded $distName for the wrapper (no Java download needed)"

# Patient network settings for the Maven downloads Gradle still makes (removed again before bundling).
@"
systemProp.org.gradle.internal.http.connectionTimeout=180000
systemProp.org.gradle.internal.http.socketTimeout=180000
org.gradle.internal.repository.max.retries=6
org.gradle.internal.repository.initial.backoff=2000
org.gradle.jvmargs=-Xmx2g -Dfile.encoding=UTF-8 -Djava.net.preferIPv4Stack=true
"@ | Out-File -Encoding ascii (Join-Path $GradleHome 'gradle.properties')
$env:JAVA_TOOL_OPTIONS = '-Djava.net.preferIPv4Stack=true'
Info 'online build to fill the cache (5-15 minutes the first time)'
$rc = Invoke-Proc $Cmd '/d /c gradlew.bat assembleRelease --no-daemon --console=plain' $Launcher
if ($rc -ne 0) { Fail 'online launcher build failed' }
Info 'clean rebuild with --offline to prove nothing else is needed'
$rc = Invoke-Proc $Cmd '/d /c gradlew.bat clean assembleRelease --offline --no-daemon --console=plain' $Launcher
if ($rc -ne 0) { Fail 'OFFLINE launcher build failed: the cache is incomplete' }
$apk = Join-Path $Launcher 'app\build\outputs\apk\release\app-release.apk'
if (-not (Test-Path $apk)) { Fail 'no APK produced' }
Ok ("offline build OK, app-release.apk {0:N0} KB" -f ((Get-Item $apk).Length / 1KB))
Invoke-Proc $Cmd '/d /c gradlew.bat --stop' $Launcher | Out-Null
Start-Sleep -Seconds 3
# Trim: build outputs, daemon logs, temp, locks, and the wrapper zip (the extracted copy + .ok marker stay).
foreach ($p in 'app\build', 'build', '.gradle', 'local.properties', '.kotlin') { Remove-IfExists (Join-Path $Launcher $p) }
foreach ($p in 'daemon', '.tmp', 'caches\build-cache-1', 'gradle.properties') { Remove-IfExists (Join-Path $GradleHome $p) }
Remove-Item Env:\JAVA_TOOL_OPTIONS -ErrorAction SilentlyContinue
Get-ChildItem $GradleHome -Recurse -Force -Filter '*.lck' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem (Join-Path $GradleHome 'wrapper\dists') -Recurse -File | Where-Object { $_.Extension -eq '.zip' } | Remove-Item -Force
$ok = Get-ChildItem (Join-Path $GradleHome 'wrapper\dists') -Recurse -Filter '*.zip.ok'
if (-not $ok) { Fail 'Gradle wrapper .ok marker missing' }
Remove-IfExists (Join-Path $Repo 'tools\adbkey')
Ok 'gradle-home ready'

}   # end of steps 0-6 (skipped when the bundle is reused)

# ---------------------------------------------------------------------------------------------- 7
Step 7 "Compiling $AppName"
$Assets = Join-Path $Stage 'assets'
New-Item -ItemType Directory -Force $Assets | Out-Null
Add-Type -AssemblyName System.Drawing

function New-Badge([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(0, 102, 204))), 2, 2, $size - 4, $size - 4)
    $g.DrawEllipse((New-Object System.Drawing.Pen ([System.Drawing.Color]::White), ([single]($size / 28))), $size * 0.05, $size * 0.05, $size * 0.9, $size * 0.9)
    $f = New-Object System.Drawing.Font 'Segoe UI Black', ([single]($size / 6.2)), ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $g.DrawString('VU3INI', $f, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF 0, 0, $size, $size), $sf)
    $g.Dispose()
    return $bmp
}

$logoSrc = Get-ChildItem $Branding -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^\.(png|jpg|jpeg|bmp)$' } | Select-Object -First 1
if ($logoSrc) {
    $srcImg = [System.Drawing.Image]::FromFile($logoSrc.FullName)
    Info "using your logo: $($logoSrc.Name)"
} else {
    $srcImg = New-Badge 512
    Write-Host '    note: no logo in branding\ - using a plain VU3INI badge (put vu3ini-logo.png next to Build-Installer.bat and run it again)' -ForegroundColor Yellow
}
# Square canvas (logo centred, transparent margins) used for the header image and the icon.
$side = [Math]::Max($srcImg.Width, $srcImg.Height)
$square = New-Object System.Drawing.Bitmap $side, $side
$g = [System.Drawing.Graphics]::FromImage($square)
$g.InterpolationMode = 'HighQualityBicubic'
$g.DrawImage($srcImg, [int](($side - $srcImg.Width) / 2), [int](($side - $srcImg.Height) / 2), $srcImg.Width, $srcImg.Height)
$g.Dispose(); $srcImg.Dispose()
$square.Save((Join-Path $Assets 'vu3ini-logo.png'), [System.Drawing.Imaging.ImageFormat]::Png)

# Multi-size ICO with PNG-compressed images (Windows Vista and later).
$icoPath = Join-Path $Assets 'app.ico'
$sizes = 256, 64, 48, 32, 24, 16
$pngs = @()
foreach ($s in $sizes) {
    $b = New-Object System.Drawing.Bitmap $s, $s
    $gg = [System.Drawing.Graphics]::FromImage($b)
    $gg.InterpolationMode = 'HighQualityBicubic'; $gg.SmoothingMode = 'AntiAlias'; $gg.PixelOffsetMode = 'HighQuality'
    $gg.DrawImage($square, 0, 0, $s, $s); $gg.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $b.Dispose()
    $pngs += , $ms.ToArray()
}
$square.Dispose()
$fs = [System.IO.File]::Create($icoPath)
$w = New-Object System.IO.BinaryWriter $fs
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]; $bytes = $pngs[$i]
    $dim = if ($s -ge 256) { 0 } else { $s }
    $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$bytes.Length); $w.Write([uint32]$offset)
    $offset += $bytes.Length
}
foreach ($bytes in $pngs) { $w.Write($bytes) }
$w.Close(); $fs.Close()

$exe = Join-Path $Stage "$AppName.exe"
$cscArgs = "/nologo /codepage:65001 /target:winexe /platform:anycpu /optimize+ /out:`"$exe`" /win32icon:`"$icoPath`" " +
           "/win32manifest:`"$Src\app.manifest`" /r:System.dll /r:System.Core.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll " +
           "/r:System.Web.Extensions.dll `"$Src\App.cs`" `"$Src\Core.cs`""
if ((Invoke-Proc $Csc $cscArgs) -ne 0) { Fail 'C# compile failed' }
Copy-Item (Join-Path $Src 'Open-CleanYourTV-Shell.ps1') $Stage
Ok "$AppName.exe"

# ---------------------------------------------------------------------------------------------- 8
if (-not $reuse) {
Step 8 'Notices and bundle info'
@"
app_version=$AppVersion
built=$(Get-Date -Format 'yyyy-MM-dd HH:mm')
repo=$RepoUrl
repo_commit=$RepoCommit
repo_date=$RepoDate
python=$PyVer
jdk=Temurin $JdkVer
android_platform=34
android_build_tools=34.0.0
gradle=8.9
android_gradle_plugin=8.5.2
"@ | Out-File -Encoding ascii (Join-Path $Stage 'bundle-info.txt')

@"
VU3INI Android TV Cleaner - third-party components
====================================================
App: (c) Sasanka Boruah, VU3INI - hamvu3ini@gmail.com

CleanYourTV            MIT licence, (c) Gathin23 and contributors   - cleanyourtv\LICENSE
                       https://github.com/Gathin23/cleanyourtv (snapshot $RepoCommit)
Python $PyVer          Python Software Foundation Licence           - python\LICENSE.txt
adb-shell, rsa,        Apache 2.0 / Apache 2.0 / Apache 2.0 or BSD - see the wheels in wheels\
cryptography
Eclipse Temurin $JdkVer GPLv2 with the Classpath Exception          - jdk\legal\
Android SDK            Android Software Development Kit Licence     - android-sdk\licenses\ (accepted when
                       the bundle was built; https://developer.android.com/studio/terms)
Gradle 8.9             Apache 2.0                                   - gradle-home\wrapper\dists\
Maven dependencies     Android Gradle Plugin, AndroidX, R8, lint: Apache 2.0 / Android SDK licence

This app only runs the tools above; it does not modify them, except that
cleanyourtv\launcher\build-and-install.ps1 calls Gradle with --offline.
"@ | Out-File -Encoding ascii (Join-Path $Stage 'THIRD-PARTY-NOTICES.txt')
$stageSize = (Get-ChildItem $Stage -Recurse -Force -File | Measure-Object Length -Sum).Sum
Ok ("stage is {0:N2} GB" -f ($stageSize / 1GB))

} else {
    Step 8 'Updating bundle info'
    $infoPath = Join-Path $Stage 'bundle-info.txt'
    $infoLines = @(Get-Content $infoPath | Where-Object { $_ -notmatch '^(app_version|built)=' })
    (@("app_version=$AppVersion", "built=$(Get-Date -Format 'yyyy-MM-dd HH:mm')") + $infoLines) | Out-File -Encoding ascii $infoPath
    Ok "app_version=$AppVersion"
}

# ---------------------------------------------------------------------------------------------- 9
Step 9 'Building the installer with Inno Setup'
$iscc = $IsccPath
if (-not $iscc) {
    foreach ($c in @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
                     "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", (Join-Path $WorkDir 'innosetup\ISCC.exe'),
                     "${env:ProgramFiles}\Inno Setup 7\ISCC.exe", "$env:LOCALAPPDATA\Programs\Inno Setup 7\ISCC.exe")) {
        if ($c -and (Test-Path $c)) { $iscc = $c; break }
    }
}
if (-not $iscc) {
    # A real, Authenticode-signed Inno Setup installer; the redirecting download.php link can hand back
    # something Windows refuses to start ("file is corrupted and unreadable"), so use direct links.
    $isUrls = @(
        @('https://github.com/jrsoftware/issrc/releases/download/is-6_7_4/innosetup-6.7.4.exe', 'innosetup-6.7.4.exe'),
        @('https://github.com/jrsoftware/issrc/releases/download/is-7_1_1/innosetup-7.1.1-x64.exe', 'innosetup-7.1.1-x64.exe'),
        @('https://jrsoftware.org/download.php/is.exe?site=1', 'innosetup-latest.exe')
    )
    foreach ($old in 'innosetup-6.exe', 'innosetup-6.4.3.exe') { Remove-IfExists (Join-Path $Dl $old) }   # bad files from earlier runs
    $is = $null
    foreach ($pair in $isUrls) {
        $u = $pair[0]
        $cand = Get-File $u $pair[1] -Soft
        if (-not $cand) { continue }
        $bytes = [IO.File]::ReadAllBytes($cand)
        $sig = Get-AuthenticodeSignature $cand
        if ($bytes.Length -gt 2MB -and $bytes[0] -eq 0x4D -and $bytes[1] -eq 0x5A -and $sig.Status -eq 'Valid') {
            Ok ("Inno Setup installer verified ({0:N1} MB, signed by {1})" -f ($bytes.Length / 1MB), $sig.SignerCertificate.Subject.Split(',')[0])
            $is = $cand; break
        }
        Write-Host ("    rejected download from $u (size {0:N0} bytes, signature {1}); trying the next source" -f $bytes.Length, $sig.Status) -ForegroundColor Yellow
        Remove-Item -Force $cand
    }
    if (-not $is) { Fail 'could not download a valid Inno Setup installer; install Inno Setup 6 from jrsoftware.org yourself and run this again' }
    Unblock-File $is -ErrorAction SilentlyContinue
    $isDir = Join-Path $WorkDir 'innosetup'
    Info 'installing Inno Setup (portable, current user) for the build'
    $started = $false
    for ($try = 1; $try -le 3 -and -not $started; $try++) {
        try {
            Invoke-Proc $is "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /CURRENTUSER /PORTABLE=1 /NOICONS /DIR=`"$isDir`"" | Out-Null
            $started = $true
        } catch {
            Write-Host "    could not start the Inno Setup installer (try $try of 3): $($_.Exception.Message)" -ForegroundColor Yellow
            Start-Sleep -Seconds 10   # antivirus may still be scanning the new file
        }
    }
    $iscc = Join-Path $isDir 'ISCC.exe'
    if (-not (Test-Path $iscc)) {
        foreach ($c in @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe")) {
            if (Test-Path $c) { $iscc = $c; break }
        }
    }
    if (-not (Test-Path $iscc)) { Fail 'Inno Setup could not be installed; install it from jrsoftware.org yourself and run this again' }
}
Info "ISCC: $iscc"
Info 'compressing about 1.3 GB with LZMA2 (10-25 minutes)'
$iss = Join-Path $Root 'installer\VU3INI-AndroidTVCleaner.iss'
$rc = Invoke-Proc $iscc "/Q /DStageDir=`"$Stage`" /DOutputDir=`"$OutDir`" /DAppVersion=$AppVersion `"$iss`""
if ($rc -ne 0) { Fail 'Inno Setup compile failed' }
$setup = Join-Path $OutDir "VU3INI-Android-TV-Cleaner-Setup-$AppVersion.exe"
$hash = (Get-FileHash $setup -Algorithm SHA256).Hash
Write-Host ''
Write-Host '==================================================================' -ForegroundColor Green
Write-Host " Done: $setup" -ForegroundColor Green
Write-Host (" Size: {0:N0} MB    SHA-256: {1}" -f ((Get-Item $setup).Length / 1MB), $hash) -ForegroundColor Green
Write-Host ' This single file installs and runs with no internet.' -ForegroundColor Green
Write-Host '==================================================================' -ForegroundColor Green
