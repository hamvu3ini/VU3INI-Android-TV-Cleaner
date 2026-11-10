@echo off
rem ===========================================================================
rem  VU3INI Android TV Cleaner - offline installer builder (single batch file)
rem  by Sasanka Boruah, VU3INI - hamvu3ini@gmail.com
rem
rem  Run ONCE on a Windows 10/11 x64 PC with internet. It produces
rem      output\VU3INI-Android-TV-Cleaner-Setup-2.0.exe
rem  which installs and runs with NO internet (Python 3.12, Temurin JDK 17,
rem  Android SDK 34, Gradle 8.9 + offline cache, CleanYourTV repo, the app).
rem
rem  Your VU3INI logo is built in; a vu3ini-logo.png next to this file replaces it.
rem  Needs about 8 GB free on C: (work folder C:\VU3INI-build). 20-40 minutes.
rem  A re-run reuses the finished bundle and only redoes the installer step.
rem  Options:  -Rebuild (start from scratch, e.g. after adding a logo)   -WorkDir D:\VU3INI-build
rem
rem  Everything below "exit /b" is the embedded source; cmd never executes it.
rem ===========================================================================
setlocal
title VU3INI Android TV Cleaner - installer builder
echo.
echo  VU3INI Android TV Cleaner - offline installer builder
echo  -----------------------------------------------------
set "SELF=%~f0"
set "DEST=%~dp0VU3INI-ATVC-builder-files"
if exist "%DEST%" rmdir /s /q "%DEST%"
echo  Unpacking the embedded source files...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:SELF); $m=[regex]::Matches($t,'(?ms)^#####FILE (\S+)\r?\n(.*?)^#####END\r?$'); foreach($x in $m){ $p=Join-Path $env:DEST $x.Groups[1].Value; [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($p)); [IO.File]::WriteAllText($p,$x.Groups[2].Value,(New-Object Text.UTF8Encoding $false)) }; $b=[regex]::Matches($t,'(?ms)^#####B64FILE (\S+)\r?\n(.*?)^#####END\r?$'); foreach($x in $b){ $p=Join-Path $env:DEST $x.Groups[1].Value; [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($p)); [IO.File]::WriteAllBytes($p,[Convert]::FromBase64String(($x.Groups[2].Value -replace '\s',''))) }; if($m.Count -lt 7){ Write-Host ('only '+$m.Count+' embedded files found'); exit 1 }; Write-Host ('  '+($m.Count+$b.Count)+' files unpacked')"
if errorlevel 1 (
  echo  Unpacking failed. Make sure this .bat file was not altered.
  pause
  exit /b 1
)
if exist "%~dp0vu3ini-logo.png" (
  copy /y "%~dp0vu3ini-logo.png" "%DEST%\branding\vu3ini-logo.png" >nul
  echo  Using your logo: vu3ini-logo.png
) else (
  echo  Using the VU3INI logo built into this file.
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%DEST%\build\Build-Installer.ps1" -OutputFolder "%~dp0output" %*
set "RC=%errorlevel%"
echo.
if "%RC%"=="0" (
  echo  Finished. Your offline installer is in: "%~dp0output"
  rmdir /s /q "%DEST%" 2>nul
) else (
  echo  The build stopped with an error - see the messages above.
  echo  Unpacked sources were kept in "%DEST%" for checking.
)
echo.
pause
exit /b %RC%

#####FILE build\Build-Installer.ps1
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
#####END
#####FILE src\App.cs
// VU3INI Android TV Cleaner - the wizard.
// Guides through CleanYourTV (https://github.com/Gathin23/cleanyourtv) from start to finish, offline:
//   1 Prepare the TV   2 Set up tools   3 Connect   4 Brand & model   5 What to keep
//   6 Clean the TV     7 Home screen    8 Finish & secure        + Maintenance & undo
// Everything runs the repo's own scripts with the bundled Python, JDK 17, Android SDK 34 and Gradle;
// nobody has to edit a file.
//
// C# 5 (the compiler built into Windows): no $"", ?. , nameof, expression bodies.
// Author: Sasanka Boruah, VU3INI  <hamvu3ini@gmail.com>

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

[assembly: System.Reflection.AssemblyTitle("VU3INI Android TV Cleaner")]
[assembly: System.Reflection.AssemblyProduct("VU3INI Android TV Cleaner")]
[assembly: System.Reflection.AssemblyCompany("VU3INI")]
[assembly: System.Reflection.AssemblyCopyright("Sasanka Boruah, VU3INI")]
[assembly: System.Reflection.AssemblyVersion("2.0.0.0")]
[assembly: System.Reflection.AssemblyFileVersion("2.0.0.0")]

namespace Vu3ini.AndroidTvCleaner
{
    internal static class Program
    {
        [STAThread]
        private static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            bool fromInstaller = false;
            foreach (string a in args) { if (a == "--setup") fromInstaller = true; }
            Application.Run(new MainForm(fromInstaller));
        }
    }

    internal sealed class CheckResult
    {
        public bool Ok;
        public string Detail;
        public CheckResult(bool ok, string detail) { Ok = ok; Detail = detail; }
    }

    internal sealed class BrandItem
    {
        public string Name;
        public int Count;
        public BrandItem(string n, int c) { Name = n; Count = c; }
        public override string ToString() { return Name + "  (" + Count + (Count == 1 ? " tested TV)" : " tested TVs)"); }
    }

    internal delegate bool Work();

    internal sealed class MainForm : Form
    {
        public const string AppName = "VU3INI Android TV Cleaner";
        public const string AppVersion = "2.0";
        public const string Email = "hamvu3ini@gmail.com";

        private const int P_PREP = 0, P_SETUP = 1, P_CONNECT = 2, P_MODEL = 3, P_KEEP = 4, P_CLEAN = 5, P_HOME = 6, P_FINISH = 7, P_MAINT = 8;
        private const int WizardSteps = 8;
        private static readonly string[] NavNames = new string[] {
            "Prepare the TV", "Set up tools", "Connect to the TV", "Brand and model", "What to keep",
            "Clean the TV", "New home screen", "Finish and secure", "Maintenance and undo", "About" };

        private static readonly Color Navy = Color.FromArgb(18, 53, 91);
        private static readonly Color Blue = Color.FromArgb(0, 102, 204);
        private static readonly Color Green = Color.FromArgb(0, 128, 60);
        private static readonly Color Red = Color.FromArgb(190, 30, 30);
        private static readonly Color Orange = Color.FromArgb(200, 110, 0);
        private static readonly Color Muted = Color.FromArgb(100, 100, 100);

        // Installed folder layout (the builder creates exactly this).
        private readonly string appDir, pyBase, jdk, sdk, gradleHome, repo, wheels, venvDir, venvPy, launcherDir, marker;
        private readonly string dataDir, listsDir, themeOut;
        private readonly Settings st;
        private readonly bool fromInstaller;

        // State
        private List<ExampleInfo> examples = new List<ExampleInfo>();
        private TvInfo tv;
        private ExampleInfo chosenExample;
        private string chosenSource = "";      // full path of the tested (or audit) list the user picked
        private string chosenLabel = "";
        private List<ListEntry> entries;
        private readonly bool[] done = new bool[WizardSteps];
        private int current = -1;
        private volatile bool busy;
        private bool setupAutoRan;
        private bool suppressEvents;

        // Shell
        private ListBox nav;
        private Panel host;
        private readonly Control[] pages = new Control[9];
        private Button btnBack, btnNext;
        private RichTextBox log;
        private ProgressBar busyBar;
        private Label statusLbl;
        private readonly List<Control> wraps = new List<Control>();

        // Step 1
        private CheckBox p1Dev, p1Usb, p1Net, p1Privacy, p1Confirm;
        private TextBox p1Ip;
        private Label p1PingResult;
        // Step 2
        private ListView checks;
        private Button btnSetup;
        private Label p2Result;
        // Step 3
        private Label p3Ip, p3Result;
        private ListView p3Info;
        // Step 4
        private ComboBox p4Brand, p4Variant;
        private ListView p4Models;
        private Label p4Suggest, p4Using;
        private Button p4UseSuggestion;
        private TextBox p4Notes;
        private ExampleInfo suggested;
        // Step 5
        private ListView p5List;
        private CheckBox p5HideMissing;
        private readonly List<CheckBox> p5Keep = new List<CheckBox>();
        private Label p5Summary, p5Title;
        // Step 6
        private Label p6Summary, p6Result;
        private Button p6Run;
        // Step 7
        private CheckBox p7Install, p7InputKey, p7HomeKey;
        private ComboBox p7LiveTv, p7Theme;
        private NumericUpDown p7Columns;
        private TextBox p7Greeting;
        private CheckedListBox p7Dock;
        private PictureBox p7Preview;
        private Label p7Result;
        // Step 8
        private CheckBox p8Off, p8Reboot;
        private Label p8Result;
        // Maintenance
        private TextBox pmIp;
        private Label pmList, pmResult;
        private readonly List<Button> pmNeedsList = new List<Button>();

        private static readonly string[] CheckNames = new string[] {
            "Bundled Python 3", "Eclipse Temurin JDK (17-22)", "Android SDK Platform 34", "Android SDK Build-Tools 34",
            "Android SDK Platform-Tools (adb)", "Android SDK licences", "CleanYourTV repository", "Gradle 8.9 distribution",
            "Gradle offline dependency cache", "launcher\\local.properties (sdk.dir)", "Python venv + adb-shell, rsa, cryptography" };

        public MainForm(bool fromInstaller)
        {
            this.fromInstaller = fromInstaller;
            appDir = Path.GetFullPath(Application.StartupPath);
            pyBase = Path.Combine(appDir, @"python\python.exe");
            jdk = Path.Combine(appDir, "jdk");
            sdk = Path.Combine(appDir, "android-sdk");
            gradleHome = Path.Combine(appDir, "gradle-home");
            repo = Path.Combine(appDir, "cleanyourtv");
            wheels = Path.Combine(appDir, "wheels");
            venvDir = Path.Combine(repo, @"tools\venv");
            venvPy = Path.Combine(venvDir, @"Scripts\python.exe");
            launcherDir = Path.Combine(repo, "launcher");
            marker = Path.Combine(appDir, "setup-done.txt");
            dataDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), @"VU3INI\AndroidTVCleaner");
            listsDir = Path.Combine(dataDir, "lists");
            themeOut = Path.Combine(dataDir, "theme");
            st = new Settings(Path.Combine(dataDir, "settings.txt"));
            BuildShell();
        }

        private string TvIp { get { return st.Get("tv_ip"); } }

        // ================================================================== shell

        private void BuildShell()
        {
            Text = AppName;
            Font = new Font("Segoe UI", 9.75f);
            StartPosition = FormStartPosition.CenterScreen;
            AutoScaleMode = AutoScaleMode.Dpi;
            ClientSize = new Size(1180, 800);
            MinimumSize = new Size(980, 680);
            BackColor = Color.White;
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

            Panel header = new Panel();
            header.Dock = DockStyle.Top;
            header.Height = 100;
            header.BackColor = Navy;
            // The VU3INI logo, top-left on every screen, on a white card (the artwork has a white background).
            Panel logoCard = new Panel();
            logoCard.BackColor = Color.White;
            logoCard.Size = new Size(88, 88);
            logoCard.Location = new Point(8, 6);
            logoCard.Paint += delegate (object s, PaintEventArgs pe)
            {
                pe.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
                using (Pen p = new Pen(Color.FromArgb(120, 170, 220), 2)) pe.Graphics.DrawRectangle(p, 1, 1, logoCard.Width - 3, logoCard.Height - 3);
            };
            PictureBox logo = new PictureBox();
            logo.SizeMode = PictureBoxSizeMode.Zoom;
            logo.Size = new Size(80, 80);
            logo.Location = new Point(4, 4);
            logo.BackColor = Color.White;
            logo.Image = LoadLogo();
            logo.Cursor = Cursors.Hand;
            logo.Click += delegate { ShowAbout(); };
            logoCard.Controls.Add(logo);
            Label title = new Label();
            title.Text = AppName;
            title.ForeColor = Color.White;
            title.Font = new Font("Segoe UI Semibold", 18f);
            title.AutoSize = true;
            title.Location = new Point(108, 14);
            Label sub = new Label();
            sub.Text = "Clean the ads, tracking and clutter off your Android TV, step by step. Everything runs offline; nothing is uninstalled.";
            sub.ForeColor = Color.FromArgb(200, 220, 240);
            sub.AutoSize = true;
            sub.Location = new Point(111, 56);
            header.Controls.Add(logoCard);
            header.Controls.Add(title);
            header.Controls.Add(sub);

            nav = new ListBox();
            nav.Dock = DockStyle.Left;
            nav.Width = 250;
            nav.BorderStyle = BorderStyle.None;
            nav.BackColor = Color.FromArgb(243, 246, 250);
            nav.DrawMode = DrawMode.OwnerDrawFixed;
            nav.ItemHeight = 38;
            nav.IntegralHeight = false;
            nav.Font = new Font("Segoe UI", 10f);
            foreach (string n in NavNames) nav.Items.Add(n);
            nav.DrawItem += NavDraw;
            nav.MouseDown += NavClick;

            host = new Panel();
            host.Dock = DockStyle.Fill;
            host.BackColor = Color.White;

            log = new RichTextBox();
            log.ReadOnly = true;
            log.Dock = DockStyle.Fill;
            log.Font = new Font("Consolas", 9f);
            log.BackColor = Color.FromArgb(250, 250, 250);
            log.BorderStyle = BorderStyle.None;
            log.WordWrap = false;

            SplitContainer split = new SplitContainer();
            split.Dock = DockStyle.Fill;
            split.Orientation = Orientation.Horizontal;
            split.Panel1.Controls.Add(host);
            Label logTitle = new Label();
            logTitle.Text = "  Activity log";
            logTitle.Dock = DockStyle.Top;
            logTitle.Height = 20;
            logTitle.ForeColor = Muted;
            logTitle.BackColor = Color.FromArgb(240, 240, 240);
            split.Panel2.Controls.Add(log);
            split.Panel2.Controls.Add(logTitle);
            split.FixedPanel = FixedPanel.Panel2;

            Panel footer = new Panel();
            footer.Dock = DockStyle.Bottom;
            footer.Height = 50;
            footer.BackColor = Color.FromArgb(243, 246, 250);
            btnBack = new Button();
            btnBack.Text = "< Back";
            btnBack.Size = new Size(110, 32);
            btnBack.Anchor = AnchorStyles.Right | AnchorStyles.Top;
            btnNext = new Button();
            btnNext.Text = "Next >";
            btnNext.Size = new Size(150, 32);
            btnNext.Anchor = AnchorStyles.Right | AnchorStyles.Top;
            StylePrimary(btnNext);
            btnBack.Click += delegate { GoBack(); };
            btnNext.Click += delegate { GoNext(); };
            busyBar = new ProgressBar();
            busyBar.Style = ProgressBarStyle.Marquee;
            busyBar.MarqueeAnimationSpeed = 0;
            busyBar.Size = new Size(160, 10);
            busyBar.Location = new Point(14, 20);
            busyBar.Visible = false;
            statusLbl = new Label();
            statusLbl.AutoSize = true;
            statusLbl.Location = new Point(184, 16);
            statusLbl.ForeColor = Muted;
            footer.Controls.Add(busyBar);
            footer.Controls.Add(statusLbl);
            footer.Controls.Add(btnBack);
            footer.Controls.Add(btnNext);
            footer.Resize += delegate
            {
                btnNext.Location = new Point(footer.ClientSize.Width - btnNext.Width - 14, 9);
                btnBack.Location = new Point(btnNext.Left - btnBack.Width - 8, 9);
            };

            Controls.Add(split);
            Controls.Add(footer);
            Controls.Add(nav);
            Controls.Add(header);

            pages[P_PREP] = BuildPrep();
            pages[P_SETUP] = BuildSetup();
            pages[P_CONNECT] = BuildConnect();
            pages[P_MODEL] = BuildModel();
            pages[P_KEEP] = BuildKeep();
            pages[P_CLEAN] = BuildClean();
            pages[P_HOME] = BuildHome();
            pages[P_FINISH] = BuildFinish();
            pages[P_MAINT] = BuildMaint();
            foreach (Control p in pages) { p.Visible = false; host.Controls.Add(p); }

            Shown += delegate
            {
                try { split.SplitterDistance = Math.Max(300, split.Height - 150); } catch { }
                OnFirstShown();
            };
        }

        private void NavDraw(object sender, DrawItemEventArgs e)
        {
            if (e.Index < 0) return;
            Graphics g = e.Graphics;
            bool isCurrent = e.Index == current;
            bool reachable = CanOpen(e.Index);
            Color back = isCurrent ? Color.FromArgb(214, 230, 248) : nav.BackColor;
            using (Brush b = new SolidBrush(back)) g.FillRectangle(b, e.Bounds);
            if (isCurrent) using (Brush b = new SolidBrush(Blue)) g.FillRectangle(b, e.Bounds.X, e.Bounds.Y, 4, e.Bounds.Height);
            if (e.Index == P_MAINT)
                using (Pen p = new Pen(Color.FromArgb(210, 215, 222))) g.DrawLine(p, e.Bounds.X + 12, e.Bounds.Y + 1, e.Bounds.Right - 12, e.Bounds.Y + 1);
            string badge;
            Color badgeColor;
            if (e.Index < WizardSteps)
            {
                badge = done[e.Index] ? "\u2713" : (e.Index + 1).ToString();
                badgeColor = done[e.Index] ? Green : (reachable ? Blue : Color.FromArgb(170, 170, 170));
            }
            else
            {
                badge = e.Index == P_MAINT ? "\u2692" : "i";
                badgeColor = Navy;
            }
            Rectangle circle = new Rectangle(e.Bounds.X + 14, e.Bounds.Y + 8, 22, 22);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (Brush b = new SolidBrush(badgeColor)) g.FillEllipse(b, circle);
            using (Font f = new Font("Segoe UI Semibold", 9f))
            using (StringFormat sf = new StringFormat())
            {
                sf.Alignment = StringAlignment.Center;
                sf.LineAlignment = StringAlignment.Center;
                g.DrawString(badge, f, Brushes.White, circle, sf);
            }
            Color fore = reachable ? Color.FromArgb(30, 30, 30) : Color.FromArgb(160, 160, 160);
            using (Font f = new Font("Segoe UI", 10f, isCurrent ? FontStyle.Bold : FontStyle.Regular))
            using (Brush b = new SolidBrush(fore))
                g.DrawString(nav.Items[e.Index].ToString(), f, b, e.Bounds.X + 46, e.Bounds.Y + 10);
        }

        private void NavClick(object sender, MouseEventArgs e)
        {
            if (busy) return;
            int i = nav.IndexFromPoint(e.Location);
            if (i < 0) return;
            if (i == NavNames.Length - 1) { ShowAbout(); return; }
            if (!CanOpen(i))
            {
                SetStatus("Finish the earlier steps first.");
                return;
            }
            ShowPage(i);
        }

        private bool CanOpen(int i)
        {
            if (i >= P_MAINT) return true;
            for (int k = 0; k < i; k++) if (!done[k]) return false;
            return true;
        }

        private void ShowPage(int i)
        {
            if (current == P_KEEP && i != P_KEEP && entries != null && Core.CountDisable(entries) > 0) SaveChoicesAndGenerate();
            if (current >= 0 && current < pages.Length) pages[current].Visible = false;
            current = i;
            pages[i].Visible = true;
            pages[i].BringToFront();
            FitWraps();
            OnEnter(i);
            FitWraps();
            RefreshNav();
        }

        private void RefreshNav()
        {
            nav.Invalidate();
            btnBack.Visible = current > 0 && current < P_MAINT;
            btnNext.Visible = current < P_MAINT;
            if (current >= 0 && current < WizardSteps)
            {
                btnNext.Text = current == P_FINISH ? "Finish" : (current == P_KEEP ? "Save choices  >" : "Next  >");
                btnNext.Enabled = !busy && done[current];
            }
            btnBack.Enabled = !busy;
        }

        private void GoBack()
        {
            if (busy || current <= 0) return;
            ShowPage(current - 1);
        }

        private void GoNext()
        {
            if (busy || current < 0 || current >= WizardSteps || !done[current]) return;
            if (current == P_KEEP && !SaveChoicesAndGenerate()) return;
            if (current == P_FINISH)
            {
                st.SetBool("finished", true);
                MessageBox.Show(this, "All done. Your TV is clean and secure.\r\n\r\nKeep this app: 'Maintenance and undo' re-applies your choices after a TV firmware update, and can put everything back if you ever want.",
                    AppName, MessageBoxButtons.OK, MessageBoxIcon.Information);
                ShowPage(P_MAINT);
                return;
            }
            ShowPage(current + 1);
        }

        private void MarkDone(int step, bool value)
        {
            done[step] = value;
            UI(delegate { RefreshNav(); });
        }

        // ================================================================== page helpers

        private TableLayoutPanel NewPage(string title, string intro)
        {
            TableLayoutPanel t = new TableLayoutPanel();
            t.Dock = DockStyle.Fill;
            t.ColumnCount = 1;
            t.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            t.Padding = new Padding(22, 14, 22, 10);
            t.AutoScroll = true;
            t.GrowStyle = TableLayoutPanelGrowStyle.AddRows;
            Label h = new Label();
            h.Text = title;
            h.Font = new Font("Segoe UI Semibold", 15f);
            h.ForeColor = Navy;
            h.AutoSize = true;
            h.Margin = new Padding(0, 0, 0, 6);
            AddRow(t, h);
            if (!string.IsNullOrEmpty(intro)) AddRow(t, Wrap(intro, Color.FromArgb(40, 40, 40)));
            t.Resize += delegate { FitWraps(); };
            return t;
        }

        private static void AddRow(TableLayoutPanel t, Control c)
        {
            t.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            t.Controls.Add(c, 0, t.RowStyles.Count - 1);
        }

        private static void AddFillRow(TableLayoutPanel t, Control c)
        {
            t.AutoScroll = false;
            c.Dock = DockStyle.Fill;
            t.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            t.Controls.Add(c, 0, t.RowStyles.Count - 1);
        }

        private Label Wrap(string text, Color color)
        {
            Label l = new Label();
            l.Text = text;
            l.AutoSize = true;
            l.ForeColor = color;
            l.Margin = new Padding(0, 3, 0, 6);
            l.UseMnemonic = false;
            wraps.Add(l);
            return l;
        }

        private CheckBox WrapCheck(string text, bool bold)
        {
            CheckBox c = new CheckBox();
            c.Text = text;
            c.AutoSize = true;
            c.Margin = new Padding(0, 6, 0, 6);
            if (bold) c.Font = new Font("Segoe UI Semibold", 10.5f);
            c.UseMnemonic = false;
            c.TextAlign = ContentAlignment.TopLeft;
            c.CheckAlign = ContentAlignment.TopLeft;
            wraps.Add(c);
            return c;
        }

        private void FitWraps()
        {
            foreach (Control c in wraps)
            {
                Control page = c.Parent;
                while (page != null && page.Parent != host) page = page.Parent;
                if (page == null || !page.Visible) continue;
                int w = Math.Max(320, page.ClientSize.Width - 70);
                bool box = c is CheckBox;
                Size m = TextRenderer.MeasureText(c.Text.Length == 0 ? " " : c.Text, c.Font, new Size(w - (box ? 26 : 4), 0),
                    TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);
                c.AutoSize = false;
                c.Size = new Size(w, m.Height + (box ? 8 : 4));
            }
        }

        private static Button Btn(string text)
        {
            Button b = new Button();
            b.Text = text;
            b.AutoSize = true;
            b.Padding = new Padding(8, 3, 8, 3);
            b.Margin = new Padding(0, 4, 8, 4);
            return b;
        }

        private static void StylePrimary(Button b)
        {
            b.BackColor = Blue;
            b.ForeColor = Color.White;
            b.FlatStyle = FlatStyle.Flat;
            b.FlatAppearance.BorderSize = 0;
            b.Font = new Font("Segoe UI Semibold", 10f);
        }

        private static FlowLayoutPanel Row(params Control[] cs)
        {
            FlowLayoutPanel f = new FlowLayoutPanel();
            f.AutoSize = true;
            f.WrapContents = true;
            f.Margin = new Padding(0, 2, 0, 2);
            f.Dock = DockStyle.Top;
            foreach (Control c in cs) f.Controls.Add(c);
            return f;
        }

        private static Label Lbl(string text)
        {
            Label l = new Label();
            l.Text = text;
            l.AutoSize = true;
            l.Margin = new Padding(0, 9, 6, 3);
            l.UseMnemonic = false;
            return l;
        }

        private void SetResult(Label l, string text, Color c)
        {
            l.Text = text;
            l.ForeColor = c;
            if (wraps.Contains(l)) FitWraps();
        }

        private Image LoadLogo()
        {
            string p = Path.Combine(appDir, @"assets\vu3ini-logo.png");
            try
            {
                if (File.Exists(p)) using (Image src = Image.FromFile(p)) { return new Bitmap(src); }
            }
            catch { }
            Bitmap bmp = new Bitmap(152, 152);
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                using (Brush b = new SolidBrush(Blue)) g.FillEllipse(b, 4, 4, 144, 144);
                using (Pen pen = new Pen(Color.White, 5)) g.DrawEllipse(pen, 8, 8, 136, 136);
                using (Font f = new Font("Segoe UI Black", 25f, FontStyle.Bold))
                using (StringFormat sf = new StringFormat())
                {
                    sf.Alignment = StringAlignment.Center;
                    sf.LineAlignment = StringAlignment.Center;
                    g.DrawString("VU3INI", f, Brushes.White, new RectangleF(0, 0, 152, 152), sf);
                }
            }
            return bmp;
        }

        private static Image LoadImageCopy(string path)
        {
            try
            {
                if (File.Exists(path)) using (Image src = Image.FromFile(path)) { return new Bitmap(src); }
            }
            catch { }
            return null;
        }

        // ================================================================== Step 1: prepare the TV

        private Control BuildPrep()
        {
            TableLayoutPanel t = NewPage("Step 1 - Prepare your TV",
                "Do these on the TV with its remote, then tick each one. Nothing on the TV is changed until step 6, and everything can be undone later.");
            p1Dev = WrapCheck("1.  Turn on Developer options: Settings > Device Preferences > About. Move to 'Build' and press OK seven times, until the TV says you are now a developer.", false);
            p1Usb = WrapCheck("2.  Turn on USB debugging: go back to Settings > Device Preferences > Developer options and switch on 'USB debugging'. On OnePlus and most Android TVs this alone allows the PC to connect over the network; no cable is needed.", false);
            p1Net = WrapCheck("3.  The TV and this PC are on the same home network (Wi-Fi or LAN cable), and the TV stays switched on.", false);
            p1Privacy = WrapCheck("Optional, recommended now: turn off 'Usage & diagnostics' and reset or opt out of the advertising ID (Settings > Device Preferences > About or Google > Ads). On some TVs these pages disappear after cleaning.", false);
            p1Privacy.ForeColor = Muted;
            AddRow(t, p1Dev);
            AddRow(t, p1Usb);
            AddRow(t, p1Net);
            AddRow(t, p1Privacy);
            AddRow(t, Wrap("4.  Type the TV's IP address. Find it on the TV under Settings > Network & Internet > (your network), for example 192.168.1.50.", Color.Black));
            p1Ip = new TextBox();
            p1Ip.Width = 170;
            p1Ip.Margin = new Padding(0, 5, 8, 3);
            p1Ip.Font = new Font("Segoe UI", 11f);
            Button ping = Btn("Check the TV is reachable");
            p1PingResult = Lbl("");
            AddRow(t, Row(Lbl("TV IP address:"), p1Ip, ping, p1PingResult));
            AddRow(t, Wrap("When the PC first connects (step 3), the TV shows 'Allow USB debugging?'. Tick 'Always allow from this computer' and press OK.", Muted));
            p1Confirm = WrapCheck("I have completed Step 1 on my TV - go ahead to the next step", true);
            p1Confirm.ForeColor = Navy;
            AddRow(t, p1Confirm);

            p1Dev.Checked = st.GetBool("s1_dev");
            p1Usb.Checked = st.GetBool("s1_usb");
            p1Net.Checked = st.GetBool("s1_net");
            p1Privacy.Checked = st.GetBool("s1_privacy");
            p1Ip.Text = TvIp;
            p1Confirm.Checked = st.GetBool("step1_done");
            EventHandler changed = delegate { Step1Changed(); };
            p1Dev.CheckedChanged += changed;
            p1Usb.CheckedChanged += changed;
            p1Net.CheckedChanged += changed;
            p1Privacy.CheckedChanged += changed;
            p1Confirm.CheckedChanged += changed;
            p1Ip.TextChanged += changed;
            ping.Click += delegate { PingTv(); };
            UpdateStep1Done();
            return t;
        }

        private static bool ValidIp(string ip)
        {
            IPAddress a;
            string[] parts = ip.Split('.');
            return parts.Length == 4 && IPAddress.TryParse(ip, out a) && a.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork;
        }

        private void Step1Changed()
        {
            if (suppressEvents) return;
            st.SetBool("s1_dev", p1Dev.Checked);
            st.SetBool("s1_usb", p1Usb.Checked);
            st.SetBool("s1_net", p1Net.Checked);
            st.SetBool("s1_privacy", p1Privacy.Checked);
            string ip = p1Ip.Text.Trim();
            if (ValidIp(ip) && ip != TvIp)
            {
                st.Set("tv_ip", ip);
                tv = null;
                done[P_CONNECT] = false;
                if (pmIp != null) pmIp.Text = ip;
            }
            p1Ip.BackColor = ip.Length == 0 || ValidIp(ip) ? SystemColors.Window : Color.FromArgb(255, 230, 230);
            if (p1Confirm.Checked && !(p1Dev.Checked && p1Usb.Checked && p1Net.Checked && ValidIp(ip)))
            {
                SetStatus("Tick steps 1 to 3 and type a valid IP address first.");
                suppressEvents = true;
                p1Confirm.Checked = false;
                suppressEvents = false;
            }
            st.SetBool("step1_done", p1Confirm.Checked);
            UpdateStep1Done();
            RefreshNav();
        }

        private void UpdateStep1Done()
        {
            done[P_PREP] = p1Confirm.Checked && p1Dev.Checked && p1Usb.Checked && p1Net.Checked && ValidIp(p1Ip.Text.Trim());
        }

        private void PingTv()
        {
            string ip = p1Ip.Text.Trim();
            if (!ValidIp(ip)) { SetResult(p1PingResult, "Type a valid IP address first.", Red); return; }
            SetResult(p1PingResult, "Checking...", Muted);
            Thread th = new Thread(delegate ()
            {
                string text;
                Color color;
                try
                {
                    using (Ping p = new Ping())
                    {
                        PingReply r = p.Send(ip, 2000);
                        if (r.Status == IPStatus.Success) { text = "Reachable (" + r.RoundtripTime + " ms)."; color = Green; }
                        else { text = "No reply. That is normal for some TVs; step 3 tests the real connection."; color = Orange; }
                    }
                }
                catch (Exception ex) { text = "Could not check: " + ex.Message; color = Orange; }
                UI(delegate { SetResult(p1PingResult, text, color); });
            });
            th.IsBackground = true;
            th.Start();
        }

        // ================================================================== Step 2: tools

        private Control BuildSetup()
        {
            TableLayoutPanel t = NewPage("Step 2 - Set up the tools",
                "Everything needed is already inside this app's folder: Python, the Java JDK 17, the Android SDK 34, Gradle and CleanYourTV with its tested lists. This step checks each part and finishes the setup. No internet is used.");
            checks = new ListView();
            checks.View = View.Details;
            checks.FullRowSelect = true;
            checks.HeaderStyle = ColumnHeaderStyle.Nonclickable;
            checks.Columns.Add("Component", 300);
            checks.Columns.Add("Status", 80);
            checks.Columns.Add("Details", 460);
            checks.Height = 270;
            checks.Dock = DockStyle.Top;
            foreach (string n in CheckNames)
            {
                ListViewItem it = new ListViewItem(n);
                it.SubItems.Add("...");
                it.SubItems.Add("");
                checks.Items.Add(it);
            }
            AddRow(t, checks);
            btnSetup = Btn("Run the setup again");
            Button recheck = Btn("Re-check");
            Button build = Btn("Optional: offline test build of the home screen");
            btnSetup.Click += delegate { RunAsync("Setting up the tools", delegate { return DoSetup(); }, null); };
            recheck.Click += delegate { RunAsync("Checking", delegate { return RecheckAll(); }, null); };
            build.Click += delegate { RunAsync("Building the home screen offline", delegate { return TestBuild(); }, null); };
            AddRow(t, Row(btnSetup, recheck, build));
            p2Result = Wrap("", Muted);
            p2Result.Font = new Font("Segoe UI Semibold", 10.5f);
            AddRow(t, p2Result);
            if (appDir.IndexOf(' ') >= 0)
                AddRow(t, Wrap("Warning: this app is installed in a folder whose path has spaces. Gradle and the Android SDK prefer a path without spaces; reinstall to C:\\VU3INI\\ATVCleaner if the setup fails.", Orange));
            return t;
        }

        // ================================================================== Step 3: connect

        private Control BuildConnect()
        {
            TableLayoutPanel t = NewPage("Step 3 - Connect to the TV",
                "The app connects to the TV over your network and reads its model and installed apps. Nothing on the TV is changed.");
            p3Ip = Lbl("");
            p3Ip.Font = new Font("Segoe UI Semibold", 10.5f);
            Button change = Btn("Change IP");
            change.Click += delegate { ShowPage(P_PREP); };
            AddRow(t, Row(Lbl("TV IP address:"), p3Ip, change));
            Button connect = Btn("Connect to the TV");
            StylePrimary(connect);
            connect.Click += delegate { ConnectTv(); };
            AddRow(t, Row(connect));
            AddRow(t, Wrap("Watch the TV: when it asks 'Allow USB debugging?', tick 'Always allow from this computer' and press OK. If the question timed out, press Connect again.", Orange));
            p3Result = Wrap("", Muted);
            p3Result.Font = new Font("Segoe UI Semibold", 10.5f);
            AddRow(t, p3Result);
            p3Info = new ListView();
            p3Info.View = View.Details;
            p3Info.HeaderStyle = ColumnHeaderStyle.Nonclickable;
            p3Info.FullRowSelect = true;
            p3Info.Columns.Add("Your TV", 220);
            p3Info.Columns.Add("", 520);
            AddFillRow(t, p3Info);
            return t;
        }

        private void ConnectTv()
        {
            string ip = TvIp;
            if (!ValidIp(ip)) { ShowPage(P_PREP); return; }
            if (!File.Exists(venvPy)) { MessageBox.Show(this, "Finish step 2 first.", AppName); return; }
            SetResult(p3Result, "Connecting to " + ip + " ... look at the TV and allow the connection.", Orange);
            TvInfo found = null;
            RunAsync("Connecting to the TV", delegate
            {
                StringBuilder outp = new StringBuilder();
                string cmds = string.Join("\n", Core.ProbeCommands) + "\n";
                Log("Reading the TV (model, installed apps). Nothing is changed.", Navy);
                int rc = Run(venvPy, "-I tools\\tv.py --batch", repo, 180, outp, false, cmds);
                if (rc != 0)
                {
                    Log(outp.ToString().Trim(), Red);
                    return false;
                }
                found = Core.ParseProbe(outp.ToString());
                return found.Model.Length > 0 || found.HasPackages;
            }, delegate (bool ok)
            {
                if (!ok || found == null)
                {
                    SetResult(p3Result, "Could not connect. Check: TV switched on and awake, same network, USB debugging on, IP correct; then press Connect again and allow the prompt on the TV.", Red);
                    MarkDone(P_CONNECT, false);
                    return;
                }
                tv = found;
                st.Set("tv_model", tv.Model);
                st.Set("tv_device", tv.Device);
                st.Set("tv_manufacturer", tv.Manufacturer);
                foreach (string s in Core.KnownStockLaunchers)
                    if (tv.HomePackage == s) st.Set("stock_launcher", s);
                if (tv.HomePackage == Core.LauncherPackage) st.SetBool("launcher_installed", true);
                ShowTvInfo();
                SetResult(p3Result, "Connected to " + (tv.Manufacturer + " " + tv.Model).Trim() + ". Press Next.", Green);
                Log("Connected: " + tv.Manufacturer + " " + tv.Model + " (" + tv.Device + "), Android " + tv.Android + ", " + tv.Installed.Count + " apps.", Green);
                MarkDone(P_CONNECT, true);
            });
        }

        private void ShowTvInfo()
        {
            p3Info.Items.Clear();
            if (tv == null) return;
            AddInfo("Manufacturer", tv.Manufacturer);
            AddInfo("Model", tv.Model);
            AddInfo("Device codename", tv.Device);
            AddInfo("Android version", tv.Android + (tv.Sdk.Length > 0 ? "  (API " + tv.Sdk + ")" : ""));
            AddInfo("Firmware", tv.Firmware);
            AddInfo("Current home screen app", tv.HomePackage);
            AddInfo("Installed apps and services", tv.Installed.Count.ToString());
            AddInfo("Already disabled", tv.Disabled.Count.ToString());
            AddInfo("Apps with a TV launcher icon", tv.Leanback.Count.ToString());
        }

        private void AddInfo(string k, string v)
        {
            ListViewItem it = new ListViewItem(k);
            it.SubItems.Add(v);
            p3Info.Items.Add(it);
        }

        // ================================================================== Step 4: brand and model

        private Control BuildModel()
        {
            TableLayoutPanel t = NewPage("Step 4 - Choose your TV's brand and model",
                "CleanYourTV has lists tested on hundreds of TVs. Pick the one for your TV; the app suggests it from what it read in step 3.");
            p4Suggest = Lbl("");
            p4Suggest.ForeColor = Green;
            p4UseSuggestion = Btn("Use the suggestion");
            p4UseSuggestion.Click += delegate { if (suggested != null) SelectExample(suggested, true); };
            AddRow(t, Row(p4Suggest, p4UseSuggestion));
            p4Brand = new ComboBox();
            p4Brand.DropDownStyle = ComboBoxStyle.DropDownList;
            p4Brand.Width = 320;
            p4Brand.MaxDropDownItems = 25;
            p4Brand.Margin = new Padding(0, 5, 8, 3);
            p4Brand.SelectedIndexChanged += delegate { if (!suppressEvents) FillModels(null); };
            AddRow(t, Row(Lbl("Brand:"), p4Brand));
            p4Models = new ListView();
            p4Models.View = View.Details;
            p4Models.FullRowSelect = true;
            p4Models.HideSelection = false;
            p4Models.MultiSelect = false;
            p4Models.HeaderStyle = ColumnHeaderStyle.Nonclickable;
            p4Models.Columns.Add("Tested TV model", 560);
            p4Models.Columns.Add("Software", 200);
            p4Models.Columns.Add("Lists", 60);
            p4Models.SelectedIndexChanged += delegate
            {
                if (suppressEvents || p4Models.SelectedItems.Count == 0) return;
                SelectExample(p4Models.SelectedItems[0].Tag as ExampleInfo, false);
            };
            p4Variant = new ComboBox();
            p4Variant.DropDownStyle = ComboBoxStyle.DropDownList;
            p4Variant.Width = 320;
            p4Variant.Margin = new Padding(0, 5, 8, 3);
            p4Variant.SelectedIndexChanged += delegate
            {
                if (suppressEvents || chosenExample == null || p4Variant.SelectedItem == null) return;
                ChooseSource(chosenExample, p4Variant.SelectedItem.ToString());
            };
            p4Notes = new TextBox();
            p4Notes.Multiline = true;
            p4Notes.ReadOnly = true;
            p4Notes.ScrollBars = ScrollBars.Vertical;
            p4Notes.Height = 96;
            p4Notes.Dock = DockStyle.Top;
            p4Notes.BackColor = Color.FromArgb(250, 250, 250);
            p4Using = Lbl("");
            p4Using.Font = new Font("Segoe UI Semibold", 10f);

            Button audit = Btn("My TV is not listed: build a list from a privacy audit of my TV");
            audit.Click += delegate { BuildAuditList(); };

            TableLayoutPanel lower = new TableLayoutPanel();
            lower.ColumnCount = 1;
            lower.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            lower.AutoSize = true;
            lower.Dock = DockStyle.Bottom;
            AddRow(lower, Row(Lbl("List version:"), p4Variant));
            AddRow(lower, Lbl("What the tested list does on that TV:"));
            AddRow(lower, p4Notes);
            AddRow(lower, p4Using);
            AddRow(lower, Row(audit));

            Panel mid = new Panel();
            mid.Controls.Add(p4Models);
            mid.Controls.Add(lower);
            p4Models.Dock = DockStyle.Fill;
            AddFillRow(t, mid);
            return t;
        }

        private void FillBrands()
        {
            suppressEvents = true;
            p4Brand.Items.Clear();
            foreach (KeyValuePair<string, int> kv in Core.Brands(examples)) p4Brand.Items.Add(new BrandItem(kv.Key, kv.Value));
            suppressEvents = false;
        }

        private void SelectBrand(string brand)
        {
            for (int i = 0; i < p4Brand.Items.Count; i++)
            {
                if (string.Equals(((BrandItem)p4Brand.Items[i]).Name, brand, StringComparison.OrdinalIgnoreCase))
                {
                    suppressEvents = true;
                    p4Brand.SelectedIndex = i;
                    suppressEvents = false;
                    return;
                }
            }
        }

        private void FillModels(ExampleInfo select)
        {
            BrandItem b = p4Brand.SelectedItem as BrandItem;
            suppressEvents = true;
            p4Models.BeginUpdate();
            p4Models.Items.Clear();
            if (b != null)
            {
                foreach (ExampleInfo e in examples)
                {
                    if (!string.Equals(e.Brand, b.Name, StringComparison.OrdinalIgnoreCase)) continue;
                    ListViewItem it = new ListViewItem(e.Tv + (e == suggested ? "    \u2190 suggested for your TV" : ""));
                    it.SubItems.Add(e.Os);
                    it.SubItems.Add(e.Lists.Count.ToString());
                    it.Tag = e;
                    if (e == suggested) it.ForeColor = Green;
                    p4Models.Items.Add(it);
                    if (e == select) { it.Selected = true; it.EnsureVisible(); }
                }
            }
            p4Models.EndUpdate();
            suppressEvents = false;
        }

        private void SelectExample(ExampleInfo e, bool showInList)
        {
            if (e == null) return;
            if (showInList) { SelectBrand(e.Brand); FillModels(e); }
            suppressEvents = true;
            p4Variant.Items.Clear();
            foreach (string l in e.Lists) p4Variant.Items.Add(l);
            string savedVariant = st.Get("example") == e.Folder ? st.Get("list_file") : "";
            int vi = Math.Max(0, p4Variant.Items.IndexOf(savedVariant));
            p4Variant.SelectedIndex = vi;
            p4Variant.Enabled = e.Lists.Count > 1;
            suppressEvents = false;
            p4Notes.Text = (e.Notes.Replace("`", "") + (e.HasConfig ? "\r\n\r\nThis TV also has a tested home screen setup (dock, Live TV app, remote keys) that step 7 uses." : "")).Trim();
            ChooseSource(e, p4Variant.Items[vi].ToString());
        }

        private void ChooseSource(ExampleInfo e, string listFile)
        {
            chosenExample = e;
            chosenSource = Path.Combine(e.Dir, listFile);
            chosenLabel = "examples\\" + e.Folder + "\\" + listFile;
            st.Set("example", e.Folder);
            st.Set("list_file", listFile);
            st.Set("source", "example");
            entries = null;
            MarkDone(P_KEEP, false);
            int n = 0;
            try { n = Core.CountDisable(Core.ParseList(chosenSource)); } catch { }
            SetResult(p4Using, "Using: " + e.Tv + "  -  " + listFile + "  (" + n + " apps to disable by default). Press Next.", Green);
            MarkDone(P_MODEL, true);
        }

        private void BuildAuditList()
        {
            if (!done[P_CONNECT]) { ShowPage(P_CONNECT); return; }
            if (MessageBox.Show(this, "The app will ask the TV which apps do voice, ACR (content recognition) and telemetry, and build a list of those for you to review in the next step.\r\n\r\nUse this only when no tested list fits your TV. Continue?",
                AppName, MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            string dir = Path.Combine(listsDir, "privacy-audit");
            string file = Path.Combine(dir, "audit-source.txt");
            RunAsync("Running the privacy audit", delegate
            {
                Directory.CreateDirectory(dir);
                if (File.Exists(file)) File.Delete(file);
                int rc = Run(venvPy, "-I tools\\privacy.py --write \"" + file + "\"", repo, 300, null, true, null);
                return rc == 0 && File.Exists(file);
            }, delegate (bool ok)
            {
                if (!ok) { SetResult(p4Using, "The privacy audit did not produce a list (see the log).", Red); return; }
                chosenExample = null;
                chosenSource = file;
                chosenLabel = "privacy audit of this TV";
                st.Set("source", "audit");
                entries = null;
                p4Notes.Text = "A list built by CleanYourTV's privacy audit (tools\\privacy.py) from what your TV runs for voice, ACR and telemetry. It was not tested on your model, so review it carefully in the next step.";
                SetResult(p4Using, "Using: privacy audit list (" + Core.CountDisable(Core.ParseList(file)) + " apps). Press Next.", Green);
                MarkDone(P_MODEL, true);
            });
        }

        // ================================================================== Step 5: what to keep

        private Control BuildKeep()
        {
            TableLayoutPanel t = NewPage("Step 5 - Choose what to keep", null);
            p5Title = Wrap("", Color.FromArgb(40, 40, 40));
            AddRow(t, p5Title);
            AddRow(t, Wrap("Ticked apps will be disabled (not uninstalled; Undo puts them back). Untick anything you use. Grey entries are protected and are never touched.", Color.FromArgb(40, 40, 40)));
            FlowLayoutPanel keepRow = Row(Lbl("Keep everything for:"));
            foreach (KeepCategory c in Core.KeepCategories)
            {
                CheckBox cb = new CheckBox();
                cb.Text = c.Name;
                cb.AutoSize = true;
                cb.Tag = c;
                cb.Margin = new Padding(0, 8, 14, 3);
                cb.CheckedChanged += delegate (object s, EventArgs ev) { if (!suppressEvents) KeepCategoryChanged((CheckBox)s); };
                p5Keep.Add(cb);
                keepRow.Controls.Add(cb);
            }
            AddRow(t, keepRow);
            Button reset = Btn("Reset to the tested list");
            Button none = Btn("Untick all");
            Button all = Btn("Tick all");
            p5HideMissing = new CheckBox();
            p5HideMissing.Text = "Hide apps that are not on my TV";
            p5HideMissing.AutoSize = true;
            p5HideMissing.Checked = true;
            p5HideMissing.Margin = new Padding(6, 9, 3, 3);
            reset.Click += delegate { SetAll(null); };
            none.Click += delegate { SetAll(false); };
            all.Click += delegate { SetAll(true); };
            p5HideMissing.CheckedChanged += delegate { FillKeepList(); };
            AddRow(t, Row(reset, none, all, p5HideMissing));
            p5List = new ListView();
            p5List.View = View.Details;
            p5List.CheckBoxes = true;
            p5List.FullRowSelect = true;
            p5List.ShowGroups = true;
            p5List.HeaderStyle = ColumnHeaderStyle.Nonclickable;
            p5List.Columns.Add("Disable  /  app", 300);
            p5List.Columns.Add("What it is (from the tested list)", 450);
            p5List.Columns.Add("On your TV", 130);
            p5List.ItemCheck += delegate (object s, ItemCheckEventArgs ev)
            {
                ListEntry e = p5List.Items[ev.Index].Tag as ListEntry;
                if (e != null && e.Locked) ev.NewValue = CheckState.Unchecked;
            };
            p5List.ItemChecked += delegate (object s, ItemCheckedEventArgs ev)
            {
                if (suppressEvents) return;
                ListEntry e = ev.Item.Tag as ListEntry;
                if (e == null || e.Locked) return;
                e.Disable = ev.Item.Checked;
                UpdateKeepSummary();
            };
            AddFillRow(t, p5List);
            p5Summary = Lbl("");
            p5Summary.Font = new Font("Segoe UI Semibold", 10f);
            AddRow(t, p5Summary);
            return t;
        }

        private string ChoiceKey()
        {
            return "choice:" + (chosenExample != null ? chosenExample.Folder + "/" + Path.GetFileName(chosenSource) : "audit");
        }

        private void LoadEntries()
        {
            entries = Core.ParseList(chosenSource);
            Core.ApplyStatus(entries, tv);
            // Saved choices: "+pkg" disabled, "-pkg" kept, relative to the tested list.
            string saved = st.Get(ChoiceKey());
            if (saved.Length > 0)
            {
                Dictionary<string, bool> diff = new Dictionary<string, bool>();
                foreach (string part in saved.Split(','))
                    if (part.Length > 1) diff[part.Substring(1)] = part[0] == '+';
                foreach (ListEntry e in entries)
                {
                    bool v;
                    if (!e.Locked && diff.TryGetValue(e.Package, out v)) e.Disable = v;
                }
            }
            suppressEvents = true;
            string cats = st.Get(ChoiceKey() + ":keep");
            foreach (CheckBox cb in p5Keep) cb.Checked = ("|" + cats + "|").Contains("|" + cb.Text + "|");
            suppressEvents = false;
            p5Title.Text = "List: " + chosenLabel + (tv != null ? "   -   TV: " + (tv.Manufacturer + " " + tv.Model).Trim() : "");
            FillKeepList();
        }

        private void FillKeepList()
        {
            if (entries == null) return;
            suppressEvents = true;
            p5List.BeginUpdate();
            p5List.Items.Clear();
            p5List.Groups.Clear();
            Dictionary<string, ListViewGroup> groups = new Dictionary<string, ListViewGroup>();
            foreach (ListEntry e in entries)
            {
                if (p5HideMissing.Checked && e.Status == "not installed") continue;
                ListViewGroup g;
                if (!groups.TryGetValue(e.Section, out g))
                {
                    g = new ListViewGroup(e.Section, e.Section);
                    groups[e.Section] = g;
                    p5List.Groups.Add(g);
                }
                ListViewItem it = new ListViewItem(e.Package, g);
                string what = e.Comment;
                if (!e.DefaultDisable && !e.Locked) what = "[kept by the list's testers] " + what;
                it.SubItems.Add(what);
                it.SubItems.Add(e.Locked ? "protected" : (e.Status.Length > 0 ? e.Status : "unknown"));
                it.Tag = e;
                it.Checked = e.Disable && !e.Locked;
                if (e.Locked) it.ForeColor = Color.Gray;
                else if (e.Status == "not installed") it.ForeColor = Color.FromArgb(150, 150, 150);
                else if (!e.DefaultDisable) it.ForeColor = Navy;
                p5List.Items.Add(it);
            }
            p5List.EndUpdate();
            suppressEvents = false;
            UpdateKeepSummary();
        }

        private void UpdateKeepSummary()
        {
            if (entries == null) return;
            int dis = 0, onTv = 0, hidden = 0;
            foreach (ListEntry e in entries)
            {
                if (e.Disable && !e.Locked)
                {
                    dis++;
                    if (e.Status == "enabled") onTv++;
                }
                if (p5HideMissing.Checked && e.Status == "not installed") hidden++;
            }
            string s = dis + " of " + entries.Count + " will be disabled";
            if (tv != null && tv.HasPackages) s += " (" + onTv + " of them are currently enabled on your TV)";
            if (hidden > 0) s += ";  " + hidden + " apps not on your TV are hidden";
            p5Summary.Text = s + ".";
            p5Summary.ForeColor = dis > 0 ? Navy : Red;
            done[P_KEEP] = dis > 0;
            RefreshNav();
        }

        private void KeepCategoryChanged(CheckBox cb)
        {
            if (entries == null) return;
            KeepCategory c = (KeepCategory)cb.Tag;
            int n = 0;
            foreach (ListEntry e in entries)
            {
                if (e.Locked || !c.Matches(e)) continue;
                // Keep: untick. Untick the switch: back to what the tested list says, unless another keep switch still covers it.
                bool keepByOther = false;
                foreach (CheckBox other in p5Keep)
                    if (other != cb && other.Checked && ((KeepCategory)other.Tag).Matches(e)) keepByOther = true;
                e.Disable = cb.Checked ? false : (keepByOther ? false : e.DefaultDisable);
                n++;
            }
            Log((cb.Checked ? "Keeping " : "Back to the tested choice for ") + n + " apps: " + c.Name, Navy);
            FillKeepList();
        }

        private void SetAll(object value)
        {
            if (entries == null) return;
            suppressEvents = true;
            foreach (CheckBox cb in p5Keep) cb.Checked = false;
            suppressEvents = false;
            foreach (ListEntry e in entries)
            {
                if (e.Locked) continue;
                if (value == null) e.Disable = e.DefaultDisable;
                else if (!p5HideMissing.Checked || e.Status != "not installed" || !(bool)value) e.Disable = (bool)value;
            }
            FillKeepList();
        }

        private string GeneratedListPath()
        {
            string folder = chosenExample != null ? chosenExample.Folder : "privacy-audit";
            string file = chosenExample != null ? Path.GetFileName(chosenSource) : "debloat.txt";
            return Path.Combine(Path.Combine(listsDir, folder), file);
        }

        private bool SaveChoicesAndGenerate()
        {
            if (entries == null || chosenSource.Length == 0) return false;
            if (Core.CountDisable(entries) == 0)
            {
                MessageBox.Show(this, "Nothing is ticked, so there is nothing to clean. Tick at least one app.", AppName);
                return false;
            }
            List<string> diff = new List<string>();
            foreach (ListEntry e in entries)
                if (!e.Locked && e.Disable != e.DefaultDisable) diff.Add((e.Disable ? "+" : "-") + e.Package);
            st.Set(ChoiceKey(), string.Join(",", diff.ToArray()));
            List<string> cats = new List<string>();
            foreach (CheckBox cb in p5Keep) if (cb.Checked) cats.Add(cb.Text);
            st.Set(ChoiceKey() + ":keep", string.Join("|", cats.ToArray()));
            string path = GeneratedListPath();
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(path));
                File.WriteAllText(path, Core.BuildList(chosenSource, entries, chosenLabel), new UTF8Encoding(false));
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, "Could not save your list: " + ex.Message, AppName);
                return false;
            }
            st.Set("generated_list", path);
            Log("Saved your choices: " + Core.CountDisable(entries) + " apps to disable -> " + path, Green);
            return true;
        }

        // ================================================================== Step 6: clean

        private Control BuildClean()
        {
            TableLayoutPanel t = NewPage("Step 6 - Clean the TV",
                "The app now disables the apps you ticked, using CleanYourTV's own script. Before the first change it saves a record of how the TV is now, so that 'Undo' (in Maintenance) can put everything back exactly.");
            p6Summary = Wrap("", Color.Black);
            p6Summary.Font = new Font("Segoe UI", 10.5f);
            AddRow(t, p6Summary);
            Button view = Btn("View the list that will be applied");
            view.Click += delegate
            {
                string p = st.Get("generated_list");
                if (File.Exists(p)) ShowText("Your list", File.ReadAllText(p));
            };
            AddRow(t, Row(view));
            p6Run = Btn("Clean my TV now");
            StylePrimary(p6Run);
            p6Run.Padding = new Padding(16, 8, 16, 8);
            p6Run.Click += delegate { CleanTv(); };
            AddRow(t, Row(p6Run));
            AddRow(t, Wrap("The TV's stock home screen app is skipped on this first run on purpose: there must always be a home screen. It is handled in step 7, once the new home screen is installed (or stays, if you skip step 7).", Muted));
            p6Result = Wrap("", Muted);
            p6Result.Font = new Font("Segoe UI Semibold", 10.5f);
            AddRow(t, p6Result);
            return t;
        }

        private void CleanTv()
        {
            string list = st.Get("generated_list");
            if (!File.Exists(list) || !done[P_KEEP]) { ShowPage(P_KEEP); return; }
            int n = Core.CountDisable(Core.ParseList(list));
            if (MessageBox.Show(this, "Disable " + n + " apps on the TV at " + TvIp + " now?\r\n\r\nNothing is uninstalled, and Maintenance > Undo puts everything back.",
                AppName, MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            SetResult(p6Result, "Cleaning... keep the TV on.", Orange);
            RunAsync("Cleaning the TV", delegate
            {
                return RunPs("tools\\disable.ps1", "-TvHost " + TvIp + " " + Q(list), 900) == 0;
            }, delegate (bool ok)
            {
                if (ok)
                {
                    st.Set("cleaned_list", list);
                    st.Set("cleaned_ip", TvIp);
                    SetResult(p6Result, "Done. The apps are disabled. Press Next for the new home screen.", Green);
                    MarkDone(P_CLEAN, true);
                    UpdateMaint();
                }
                else SetResult(p6Result, "The cleaning stopped with an error (see the activity log below). Nothing after the error was changed; you can run it again.", Red);
            });
        }

        private void UpdateCleanSummary()
        {
            string list = st.Get("generated_list");
            int n = 0;
            try { if (File.Exists(list)) n = Core.CountDisable(Core.ParseList(list)); } catch { }
            p6Summary.Text = "TV:   " + (tv != null ? (tv.Manufacturer + " " + tv.Model).Trim() + "  at " : "") + TvIp +
                "\r\nList:   " + chosenLabel + "\r\nApps to disable:   " + n;
            p6Run.Text = "Clean my TV now  (disable " + n + " apps)";
            if (st.Get("cleaned_list") == list && list.Length > 0 && !done[P_CLEAN])
            {
                SetResult(p6Result, "This list was already applied on " + st.Get("cleaned_ip") + ". You can run it again or press Next.", Green);
                MarkDone(P_CLEAN, true);
            }
        }

        // ================================================================== Step 7: home screen

        private Control BuildHome()
        {
            TableLayoutPanel t = NewPage("Step 7 - New home screen",
                "Replace the stock home screen and its ad rows with CleanYourTV's small, fast home screen. It is built here, offline, and installed on the TV. If anything goes wrong, Home goes back to the stock one by itself.");
            p7Install = WrapCheck("Install the new home screen (recommended)", true);
            p7Install.Checked = true;
            AddRow(t, p7Install);

            TableLayoutPanel grid = new TableLayoutPanel();
            grid.ColumnCount = 3;
            grid.AutoSize = true;
            grid.Dock = DockStyle.Top;
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

            p7LiveTv = new ComboBox();
            p7LiveTv.DropDownStyle = ComboBoxStyle.DropDown;
            p7LiveTv.Width = 300;
            p7Theme = new ComboBox();
            p7Theme.DropDownStyle = ComboBoxStyle.DropDownList;
            p7Theme.Width = 300;
            p7Theme.MaxDropDownItems = 20;
            p7Theme.SelectedIndexChanged += delegate { ShowThemePreview(); };
            p7Columns = new NumericUpDown();
            p7Columns.Minimum = 3;
            p7Columns.Maximum = 10;
            p7Columns.Value = 6;
            p7Columns.Width = 70;
            p7Greeting = new TextBox();
            p7Greeting.Width = 300;
            p7Greeting.Text = st.Get("greeting");
            p7Preview = new PictureBox();
            p7Preview.Size = new Size(256, 144);
            p7Preview.SizeMode = PictureBoxSizeMode.Zoom;
            p7Preview.BorderStyle = BorderStyle.FixedSingle;
            p7Preview.BackColor = Color.Black;

            p7Dock = new CheckedListBox();
            p7Dock.CheckOnClick = true;
            p7Dock.Size = new Size(300, 150);
            Button up = Btn("Up");
            Button down = Btn("Down");
            up.Click += delegate { MoveDock(-1); };
            down.Click += delegate { MoveDock(1); };
            FlowLayoutPanel dockButtons = new FlowLayoutPanel();
            dockButtons.FlowDirection = FlowDirection.TopDown;
            dockButtons.AutoSize = true;
            dockButtons.Controls.Add(up);
            dockButtons.Controls.Add(down);

            AddGrid(grid, "Live TV app (for HDMI and Inputs):", p7LiveTv, null);
            AddGrid(grid, "Look (theme):", p7Theme, p7Preview);
            AddGrid(grid, "Apps per row:", p7Columns, null);
            AddGrid(grid, "Greeting name (optional):", p7Greeting, null);
            AddGrid(grid, "Dock apps (ticked, in order):", p7Dock, dockButtons);
            AddRow(t, grid);

            p7InputKey = WrapCheck("The remote's Input button should open the input list (needed on some Google TV remotes)", false);
            p7HomeKey = WrapCheck("The remote's Home button sends 'All apps' instead of Home (some Xiaomi sticks)", false);
            AddRow(t, p7InputKey);
            AddRow(t, p7HomeKey);

            Button install = Btn("Install the home screen and finish cleaning");
            StylePrimary(install);
            install.Padding = new Padding(16, 8, 16, 8);
            install.Click += delegate { InstallHome(); };
            Button themeOnly = Btn("Apply look and dock only");
            themeOnly.Click += delegate { PushThemeOnly(); };
            Button skip = Btn("Skip - keep the stock home screen");
            skip.Click += delegate
            {
                st.SetBool("launcher_skipped", true);
                SetResult(p7Result, "Skipped. The stock home screen stays. Press Next.", Green);
                MarkDone(P_HOME, true);
            };
            AddRow(t, Row(install, themeOnly, skip));
            p7Result = Wrap("", Muted);
            p7Result.Font = new Font("Segoe UI Semibold", 10.5f);
            AddRow(t, p7Result);
            p7Install.CheckedChanged += delegate { grid.Enabled = p7Install.Checked; p7InputKey.Enabled = p7Install.Checked; p7HomeKey.Enabled = p7Install.Checked; };
            return t;
        }

        private static void AddGrid(TableLayoutPanel g, string label, Control c, Control extra)
        {
            int r = g.RowStyles.Count;
            g.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            Label l = Lbl(label);
            l.Margin = new Padding(0, 8, 10, 3);
            g.Controls.Add(l, 0, r);
            c.Margin = new Padding(0, 5, 8, 3);
            g.Controls.Add(c, 1, r);
            if (extra != null) g.Controls.Add(extra, 2, r);
        }

        private void MoveDock(int dir)
        {
            int i = p7Dock.SelectedIndex;
            int j = i + dir;
            if (i < 0 || j < 0 || j >= p7Dock.Items.Count) return;
            object item = p7Dock.Items[i];
            bool chk = p7Dock.GetItemChecked(i);
            p7Dock.Items.RemoveAt(i);
            p7Dock.Items.Insert(j, item);
            p7Dock.SetItemChecked(j, chk);
            p7Dock.SelectedIndex = j;
        }

        private Dictionary<string, object> ExampleConfig()
        {
            if (chosenExample == null || !chosenExample.HasConfig) return null;
            return Core.ReadJson(Path.Combine(chosenExample.Dir, "config.json"));
        }

        private void PrepareHomePage()
        {
            Dictionary<string, object> cfg = ExampleConfig();
            // Live TV app
            p7LiveTv.Items.Clear();
            List<string> live = new List<string>();
            string fromCfg = Core.JsonString(cfg, "live_tv_package");
            if (fromCfg.Length > 0) live.Add(fromCfg);
            foreach (string p in Core.KnownLiveTv)
                if (tv != null && tv.Installed.Contains(p) && !live.Contains(p)) live.Add(p);
            if (tv != null)
                foreach (string p in tv.Installed)
                    if ((p.Contains("livetv") || p.Contains("tvcenter") || p.Contains("tvplayer")) && !live.Contains(p)) live.Add(p);
            foreach (string p in live) p7LiveTv.Items.Add(p);
            string savedLive = st.Get("live_tv");
            p7LiveTv.Text = savedLive.Length > 0 ? savedLive : (live.Count > 0 ? live[0] : "");

            // Themes
            p7Theme.Items.Clear();
            p7Theme.Items.Add("(plain, no theme)");
            string themes = Path.Combine(repo, "themes");
            if (Directory.Exists(themes))
            {
                List<string> names = new List<string>();
                foreach (string d in Directory.GetDirectories(themes))
                    if (File.Exists(Path.Combine(d, "config.json"))) names.Add(Path.GetFileName(d));
                names.Sort(StringComparer.OrdinalIgnoreCase);
                foreach (string n in names) p7Theme.Items.Add(n);
            }
            string savedTheme = st.Get("theme");
            int ti = p7Theme.Items.IndexOf(savedTheme.Length > 0 ? savedTheme : "default");
            p7Theme.SelectedIndex = ti >= 0 ? ti : 0;

            // Columns
            string cols = st.Get("columns");
            if (cols.Length == 0) cols = Core.JsonString(cfg, "columns");
            int c;
            if (int.TryParse(cols, out c) && c >= 3 && c <= 10) p7Columns.Value = c;

            // Dock
            p7Dock.Items.Clear();
            List<string> order = new List<string>();
            string savedDock = st.Get("dock");
            List<string> dock = savedDock.Length > 0 ? new List<string>(savedDock.Split(',')) : Core.JsonStringList(cfg, "dock_apps");
            foreach (string p in dock) if (p.Length > 0 && !order.Contains(p) && (tv == null || !tv.HasPackages || tv.Installed.Contains(p))) order.Add(p);
            if (tv != null)
            {
                foreach (string p in tv.Leanback) if (!order.Contains(p) && p != Core.LauncherPackage) order.Add(p);
                foreach (string p in tv.ThirdParty) if (!order.Contains(p) && p != Core.LauncherPackage) order.Add(p);
            }
            bool noDock = dock.Count == 0;
            for (int i = 0; i < order.Count; i++)
            {
                p7Dock.Items.Add(order[i]);
                bool chk = dock.Contains(order[i]) || (noDock && i < 6 && tv != null && tv.Leanback.Contains(order[i]));
                p7Dock.SetItemChecked(i, chk);
            }

            // Remote keys: from the saved choice, else from what the tested list's notes say.
            string notes = chosenExample != null ? chosenExample.Notes : "";
            p7InputKey.Checked = st.Get("input_key").Length > 0 ? st.GetBool("input_key") : notes.Contains("InputKeyService");
            p7HomeKey.Checked = st.Get("home_key").Length > 0 ? st.GetBool("home_key") : notes.Contains("HomeKeyService");

            if (st.GetBool("launcher_installed")) { SetResult(p7Result, "The new home screen is installed. You can change its look and dock, or press Next.", Green); done[P_HOME] = true; }
            else if (st.GetBool("launcher_skipped")) { done[P_HOME] = true; }
            RefreshNav();
        }

        private void ShowThemePreview()
        {
            Image old = p7Preview.Image;
            p7Preview.Image = null;
            if (old != null) old.Dispose();
            string name = p7Theme.SelectedItem == null ? "" : p7Theme.SelectedItem.ToString();
            if (name.StartsWith("(")) return;
            p7Preview.Image = LoadImageCopy(Path.Combine(repo, "themes\\" + name + "\\screenshot.jpg"));
        }

        private string SaveHomeChoices()
        {
            string themeName = p7Theme.SelectedItem == null ? "" : p7Theme.SelectedItem.ToString();
            st.Set("theme", themeName);
            st.Set("columns", ((int)p7Columns.Value).ToString());
            st.Set("greeting", p7Greeting.Text.Trim());
            st.Set("live_tv", p7LiveTv.Text.Trim());
            st.SetBool("input_key", p7InputKey.Checked);
            st.SetBool("home_key", p7HomeKey.Checked);
            List<string> dock = new List<string>();
            foreach (object o in p7Dock.CheckedItems) dock.Add(o.ToString());
            st.Set("dock", string.Join(",", dock.ToArray()));

            Dictionary<string, object> ov = new Dictionary<string, object>();
            ov["columns"] = (int)p7Columns.Value;
            if (dock.Count > 0) ov["dock_apps"] = dock.ToArray();
            string live = p7LiveTv.Text.Trim();
            if (live.Length > 0 && Core.PkgRe.IsMatch(live)) ov["live_tv_package"] = live;
            string g = p7Greeting.Text.Trim();
            ov["greeting_name"] = g.Length > 0 ? (object)g : null;
            string themeDir = themeName.StartsWith("(") ? null : Path.Combine(repo, "themes\\" + themeName);
            string exCfg = chosenExample != null && chosenExample.HasConfig ? Path.Combine(chosenExample.Dir, "config.json") : null;
            Core.BuildTheme(themeDir, exCfg, ov, themeOut);
            Log("Prepared the home screen settings (" + (themeDir == null ? "plain" : themeName) + " look, " + dock.Count + " dock apps) in " + themeOut, Navy);
            return themeOut;
        }

        private void InstallHome()
        {
            if (!p7Install.Checked) { SetResult(p7Result, "Tick 'Install the new home screen' first, or press Skip.", Orange); return; }
            if (!done[P_CLEAN]) { ShowPage(P_CLEAN); return; }
            if (MessageBox.Show(this, "Build the home screen on this PC (2 to 5 minutes, offline), install it on the TV, apply your look and dock, and then finish the cleaning (the stock home screen app and its ad rows)?",
                AppName, MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            string themeDir;
            try { themeDir = SaveHomeChoices(); }
            catch (Exception ex) { SetResult(p7Result, "Could not prepare the settings: " + ex.Message, Red); return; }
            string args = "-TvHost " + TvIp + (p7InputKey.Checked ? " -InputKeyService" : "") + (p7HomeKey.Checked ? " -HomeKeyService" : "");
            string list = st.Get("cleaned_list");
            string stage = "";
            SetResult(p7Result, "Working... this takes a few minutes. Keep the TV on.", Orange);
            RunAsync("Installing the new home screen", delegate
            {
                stage = "building and installing the home screen";
                Log("1/3  Building and installing the home screen (offline)", Navy);
                if (RunPs("launcher\\build-and-install.ps1", args, 2400) != 0) return false;
                st.SetBool("launcher_installed", true);
                st.SetBool("launcher_skipped", false);
                stage = "applying the look and dock";
                Log("2/3  Applying your look and dock", Navy);
                if (RunPs("tools\\theme.ps1", "-TvHost " + TvIp + " " + Q(themeDir), 600) != 0) return false;
                stage = "finishing the cleaning";
                Log("3/3  Finishing the cleaning (the stock home screen app and its rows)", Navy);
                if (File.Exists(list) && RunPs("tools\\disable.ps1", "-TvHost " + TvIp + " " + Q(list), 900) != 0) return false;
                return true;
            }, delegate (bool ok)
            {
                if (!ok)
                {
                    SetResult(p7Result, "Stopped while " + stage + " (see the activity log). " +
                        (st.GetBool("launcher_installed") ? "The home screen itself is installed; you can press the button again." : "Home is still the stock one."), Red);
                    return;
                }
                SetResult(p7Result, "Done. The new home screen is installed and the cleaning is complete. Press Next.", Green);
                MarkDone(P_HOME, true);
                if (MessageBox.Show(this, "Restart the TV now so everything starts clean?", AppName, MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
                    RebootTv();
            });
        }

        private void PushThemeOnly()
        {
            if (!st.GetBool("launcher_installed"))
            {
                SetResult(p7Result, "Install the home screen first; the look and dock belong to it.", Orange);
                return;
            }
            string themeDir;
            try { themeDir = SaveHomeChoices(); }
            catch (Exception ex) { SetResult(p7Result, "Could not prepare the settings: " + ex.Message, Red); return; }
            RunAsync("Applying the look and dock", delegate
            {
                return RunPs("tools\\theme.ps1", "-TvHost " + TvIp + " " + Q(themeDir), 600) == 0;
            }, delegate (bool ok)
            {
                if (ok) SetResult(p7Result, "Look and dock applied; Home restarted on the TV.", Green);
                else SetResult(p7Result, "Could not apply the look (see the activity log).", Red);
            });
        }

        // ================================================================== Step 8: finish

        private Control BuildFinish()
        {
            TableLayoutPanel t = NewPage("Step 8 - Finish and secure",
                "Last step: close the debugging door. Network debugging has no password, so switch it off now that the TV is clean. The new home screen keeps working without it.");
            p8Off = WrapCheck("On the TV: Settings > Device Preferences > Developer options: switch 'USB debugging' off, and choose 'Revoke USB debugging authorisations'.", false);
            p8Reboot = WrapCheck("Restart the TV (Settings > Device Preferences > About > Restart, or unplug it for 10 seconds).", false);
            AddRow(t, p8Off);
            AddRow(t, p8Reboot);
            Button check = Btn("Check that the debugging door is closed");
            StylePrimary(check);
            check.Click += delegate { CheckPortClosed(p8Result); };
            AddRow(t, Row(check));
            p8Result = Wrap("", Muted);
            p8Result.Font = new Font("Segoe UI Semibold", 10.5f);
            AddRow(t, p8Result);
            AddRow(t, Wrap("Keep this app. After a TV firmware update, or if you ever want everything back, switch USB debugging on again and use 'Maintenance and undo'.", Muted));
            EventHandler ch = delegate
            {
                st.SetBool("s8_off", p8Off.Checked);
                st.SetBool("s8_reboot", p8Reboot.Checked);
                done[P_FINISH] = p8Off.Checked && p8Reboot.Checked;
                RefreshNav();
            };
            p8Off.Checked = st.GetBool("s8_off");
            p8Reboot.Checked = st.GetBool("s8_reboot");
            done[P_FINISH] = p8Off.Checked && p8Reboot.Checked;
            p8Off.CheckedChanged += ch;
            p8Reboot.CheckedChanged += ch;
            return t;
        }

        private void CheckPortClosed(Label target)
        {
            string ip = TvIp;
            if (!ValidIp(ip)) { SetResult(target, "Set the TV's IP address first.", Red); return; }
            int code = -1;
            RunAsync("Checking the debugging port", delegate
            {
                code = Run(venvPy, "-I tools\\adb-closed.py " + ip, repo, 60, null, true, null);
                return true;
            }, delegate (bool ok)
            {
                if (code == 0) SetResult(target, "Closed. Your TV no longer accepts debugging connections.", Green);
                else if (code == 1) SetResult(target, "Still open: switch USB debugging off on the TV, restart it, and check again.", Red);
                else SetResult(target, "Could not tell: the TV did not answer (off, asleep, restarting or at another address). Try again in a minute.", Orange);
            });
        }

        // ================================================================== Maintenance

        private Control BuildMaint()
        {
            TableLayoutPanel t = NewPage("Maintenance and undo",
                "These tools talk to the TV, so USB debugging must be switched on again first (step 1).");
            pmIp = new TextBox();
            pmIp.Width = 170;
            pmIp.Margin = new Padding(0, 5, 8, 3);
            pmIp.Text = TvIp;
            pmIp.TextChanged += delegate
            {
                string ip = pmIp.Text.Trim();
                if (ValidIp(ip) && ip != TvIp) { st.Set("tv_ip", ip); tv = null; done[P_CONNECT] = false; p1Ip.Text = ip; RefreshNav(); }
            };
            AddRow(t, Row(Lbl("TV IP address:"), pmIp));
            pmList = Wrap("", Muted);
            AddRow(t, pmList);

            AddRow(t, Section("Undo everything"));
            AddRow(t, Wrap("Puts the TV back exactly as it was before cleaning, from the record saved in step 6, and gives Home back to the stock home screen.", Color.Black));
            Button restore = Btn("Undo all changes");
            restore.Click += delegate { UndoAll(); };
            pmNeedsList.Add(restore);
            AddRow(t, Row(restore));

            AddRow(t, Section("After a TV firmware update"));
            AddRow(t, Wrap("Updates can switch disabled apps back on and give Home back to the stock launcher. Check first, then re-apply your choices if anything came back.", Color.Black));
            Button chk = Btn("Check what came back");
            Button fix = Btn("Re-apply my choices");
            chk.Click += delegate { CheckDrift(false); };
            fix.Click += delegate { CheckDrift(true); };
            pmNeedsList.Add(chk);
            pmNeedsList.Add(fix);
            AddRow(t, Row(chk, fix));

            AddRow(t, Section("More"));
            Button privacy = Btn("Privacy audit report");
            Button reboot = Btn("Restart the TV");
            Button closed = Btn("Check the debugging door is closed");
            Button change = Btn("Change my choices (step 5)");
            Button shell = Btn("Open CleanYourTV PowerShell");
            Button folder = Btn("Open my lists folder");
            privacy.Click += delegate { RunAsync("Running the privacy audit", delegate { return Run(venvPy, "-I tools\\privacy.py", repo, 300, null, true, null) == 0; }, null); };
            reboot.Click += delegate { if (MessageBox.Show(this, "Restart the TV now?", AppName, MessageBoxButtons.YesNo) == DialogResult.Yes) RebootTv(); };
            closed.Click += delegate { CheckPortClosed(pmResult); };
            change.Click += delegate { if (CanOpen(P_KEEP)) ShowPage(P_KEEP); else { SetStatus("Connect to the TV first (step 3)."); ShowPage(CanOpen(P_CONNECT) ? P_CONNECT : P_PREP); } };
            shell.Click += delegate { OpenShell(); };
            folder.Click += delegate { Directory.CreateDirectory(listsDir); Process.Start("explorer.exe", Q(listsDir)); };
            AddRow(t, Row(privacy, reboot, closed, change, shell, folder));
            pmResult = Wrap("", Muted);
            pmResult.Font = new Font("Segoe UI Semibold", 10.5f);
            AddRow(t, pmResult);
            return t;
        }

        private static Label Section(string title)
        {
            Label l = new Label();
            l.Text = title;
            l.AutoSize = true;
            l.UseMnemonic = false;
            l.Font = new Font("Segoe UI Semibold", 11.5f);
            l.ForeColor = Navy;
            l.Margin = new Padding(0, 16, 0, 2);
            return l;
        }

        private void UpdateMaint()
        {
            string list = st.Get("cleaned_list");
            bool has = list.Length > 0 && File.Exists(list);
            pmList.Text = has ? "Applied list: " + list + "   (on " + st.Get("cleaned_ip") + ")" : "No cleaning has been applied from this PC yet, so Undo and the firmware-update check are not available.";
            foreach (Button b in pmNeedsList) b.Enabled = has;
        }

        private void UndoAll()
        {
            string list = st.Get("cleaned_list");
            if (!File.Exists(list)) return;
            if (MessageBox.Show(this, "Put the TV at " + TvIp + " back the way it was before cleaning, and give Home back to the stock home screen?",
                AppName, MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
            string stock = st.Get("stock_launcher");
            if (stock.Length == 0) stock = Core.KnownStockLaunchers[0];
            RunAsync("Undoing all changes", delegate
            {
                return RunPs("tools\\restore.ps1", "-TvHost " + TvIp + " " + Q(list) + " -Stock " + stock, 900) == 0;
            }, delegate (bool ok)
            {
                if (ok)
                {
                    SetResult(pmResult, "Undone. The TV is back the way it was. A restart of the TV is recommended.", Green);
                    st.Set("cleaned_list", "");
                    st.SetBool("launcher_installed", false);
                    st.SetBool("finished", false);
                    done[P_CLEAN] = false;
                    done[P_HOME] = false;
                    UpdateMaint();
                    RefreshNav();
                }
                else SetResult(pmResult, "The undo stopped with an error (see the activity log). Run it again once the TV answers.", Red);
            });
        }

        private void CheckDrift(bool fix)
        {
            string list = st.Get("cleaned_list");
            if (!File.Exists(list)) return;
            string args = "-I tools\\check.py " + (fix ? "--fix " : "") + Q(list) + (st.GetBool("launcher_installed") ? " " + Core.LauncherPackage : "");
            int code = -1;
            RunAsync(fix ? "Re-applying your choices" : "Checking what came back", delegate
            {
                code = Run(venvPy, args, repo, 900, null, true, null);
                return true;
            }, delegate (bool ok)
            {
                if (code == 0) SetResult(pmResult, fix ? "Re-applied. The TV matches your choices again." : "Nothing came back. The TV matches your choices.", Green);
                else if (code == 1) SetResult(pmResult, fix ? "Re-applied, but some apps were left on by a safety check (see the log)." : "Some apps came back (listed in the log). Press 'Re-apply my choices'.", Orange);
                else SetResult(pmResult, "Could not read the TV (see the log). Is USB debugging on and the IP right?", Red);
            });
        }

        private void RebootTv()
        {
            RunAsync("Restarting the TV", delegate { return Run(venvPy, "-I tools\\tv.py --reboot", repo, 60, null, true, null) == 0; }, null);
        }

        // ================================================================== page entry

        private void OnEnter(int i)
        {
            if (i == P_SETUP && !done[P_SETUP] && !setupAutoRan)
            {
                setupAutoRan = true;
                RunAsync("Setting up the tools", delegate { return DoSetup(); }, null);
            }
            else if (i == P_CONNECT)
            {
                p3Ip.Text = TvIp;
                if (tv != null) ShowTvInfo();
            }
            else if (i == P_MODEL)
            {
                if (examples.Count == 0) LoadExamples();
                if (p4Brand.Items.Count == 0) FillBrands();
                int score;
                suggested = Core.BestMatch(examples, tv, out score);
                if (suggested != null)
                {
                    p4Suggest.Text = "Your TV (" + (tv.Manufacturer + " " + tv.Model + ", " + tv.Device).Trim() + ") matches:  " + suggested.Tv;
                    p4Suggest.ForeColor = Green;
                }
                else
                {
                    p4Suggest.Text = tv != null ? "No tested list names your exact model (" + (tv.Model + ", " + tv.Device).Trim() + "). Pick the closest one, or use the privacy audit below." : "";
                    p4Suggest.ForeColor = Orange;
                }
                p4UseSuggestion.Visible = suggested != null;
                // Restore the earlier choice, else take the suggestion, else the brand.
                ExampleInfo saved = null;
                foreach (ExampleInfo e in examples) if (e.Folder == st.Get("example")) saved = e;
                if (chosenExample != null) SelectExample(chosenExample, true);
                else if (st.Get("source") == "audit" && File.Exists(Path.Combine(listsDir, "privacy-audit\\audit-source.txt")) && chosenSource.Length > 0) { }
                else if (saved != null && (suggested == null || saved == suggested)) SelectExample(saved, true);
                else if (suggested != null) SelectExample(suggested, true);
                else
                {
                    string brand = Core.BrandFor(examples, tv);
                    if (brand.Length > 0) { SelectBrand(brand); FillModels(null); }
                    else if (p4Brand.Items.Count > 0 && p4Brand.SelectedIndex < 0) { p4Brand.SelectedIndex = 0; }
                }
            }
            else if (i == P_KEEP)
            {
                if (chosenSource.Length == 0) { ShowPage(P_MODEL); return; }
                if (entries == null) LoadEntries();
                else UpdateKeepSummary();
            }
            else if (i == P_CLEAN) UpdateCleanSummary();
            else if (i == P_HOME) PrepareHomePage();
            else if (i == P_MAINT) { pmIp.Text = TvIp; UpdateMaint(); }
        }

        private void LoadExamples()
        {
            try
            {
                examples = Core.LoadExamples(Path.Combine(repo, "examples"));
                Log("Loaded " + examples.Count + " tested TV lists (" + Core.Brands(examples).Count + " brands).", Muted);
            }
            catch (Exception ex) { Log("Could not read the tested lists: " + ex.Message, Red); }
        }

        private void OnFirstShown()
        {
            Log("== " + AppName + " " + AppVersion + " ==", Navy);
            Log("Installed in: " + appDir, Muted);
            string info = Path.Combine(appDir, "bundle-info.txt");
            if (File.Exists(info))
                try { foreach (string l in File.ReadAllLines(info)) if (l.Trim().Length > 0) Log("  " + l, Muted); } catch { }
            UpdateStep1Done();
            // Is step 2 still good? Quick check in the background (no changes).
            if (File.Exists(marker))
            {
                RunAsync("Checking the tools", delegate { return RecheckAll(); }, delegate (bool ok)
                {
                    if (!ok) setupAutoRan = false;
                });
            }
            UpdateMaint();
            if (!fromInstaller && st.GetBool("finished") && done[P_PREP]) ShowPage(P_MAINT);
            else ShowPage(P_PREP);
        }

        // ================================================================== threading

        private void RunAsync(string what, Work work, Action<bool> after)
        {
            if (busy) return;
            busy = true;
            SetBusy(true, what + "...");
            Thread t = new Thread(delegate ()
            {
                bool ok = false;
                try { ok = work(); }
                catch (Exception ex) { Log("ERROR: " + ex.Message, Red); }
                UI(delegate
                {
                    busy = false;
                    SetBusy(false, ok ? "Ready" : "Finished with a problem - see the log");
                    if (after != null) after(ok);
                    RefreshNav();
                });
            });
            t.IsBackground = true;
            t.Start();
        }

        private void SetBusy(bool on, string text)
        {
            host.Enabled = !on;
            nav.Enabled = !on;
            busyBar.Visible = on;
            busyBar.MarqueeAnimationSpeed = on ? 30 : 0;
            statusLbl.Text = text;
            RefreshNav();
        }

        private void SetStatus(string text) { statusLbl.Text = text; }

        private void UI(MethodInvoker m)
        {
            if (IsDisposed) return;
            try { if (InvokeRequired) BeginInvoke(m); else m(); }
            catch (ObjectDisposedException) { }
            catch (InvalidOperationException) { }
        }

        private void Log(string text, Color color)
        {
            UI(delegate
            {
                log.SelectionStart = log.TextLength;
                log.SelectionLength = 0;
                log.SelectionColor = color;
                log.AppendText(text + Environment.NewLine);
                log.SelectionColor = log.ForeColor;
                log.ScrollToCaret();
            });
        }

        private void Log(string text) { Log(text, Color.Black); }

        private void ShowText(string title, string text)
        {
            Form f = new Form();
            f.Text = title;
            f.Size = new Size(900, 640);
            f.StartPosition = FormStartPosition.CenterParent;
            TextBox tb = new TextBox();
            tb.Multiline = true;
            tb.ReadOnly = true;
            tb.ScrollBars = ScrollBars.Both;
            tb.WordWrap = false;
            tb.Dock = DockStyle.Fill;
            tb.Font = new Font("Consolas", 9.5f);
            tb.Text = text.Replace("\r\n", "\n").Replace("\n", "\r\n");
            f.Controls.Add(tb);
            f.ShowDialog(this);
        }

        // ================================================================== processes

        private void ApplyEnv(ProcessStartInfo psi)
        {
            psi.EnvironmentVariables["JAVA_HOME"] = jdk;
            psi.EnvironmentVariables["ANDROID_HOME"] = sdk;
            psi.EnvironmentVariables["ANDROID_SDK_ROOT"] = sdk;
            psi.EnvironmentVariables["GRADLE_USER_HOME"] = gradleHome;
            psi.EnvironmentVariables["PYTHONUTF8"] = "1";
            psi.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8";
            psi.EnvironmentVariables["PYTHONNOUSERSITE"] = "1";
            psi.EnvironmentVariables["PIP_NO_INDEX"] = "1";
            psi.EnvironmentVariables["PIP_DISABLE_PIP_VERSION_CHECK"] = "1";
            string path = psi.EnvironmentVariables["PATH"];
            psi.EnvironmentVariables["PATH"] = string.Join(";", new string[] {
                Path.Combine(venvDir, "Scripts"), Path.Combine(appDir, "python"), Path.Combine(jdk, "bin"),
                Path.Combine(sdk, "platform-tools"), path ?? "" });
            string ip = TvIp;
            if (ip.Length > 0) psi.EnvironmentVariables["TV_HOST"] = ip;
            foreach (string k in new string[] { "FORCE_SETUPWRAITH", "FORCE_HOME", "TVINPUT_ALLOW", "HANDLERS_ALLOW" })
                if (psi.EnvironmentVariables.ContainsKey(k)) psi.EnvironmentVariables.Remove(k);
        }

        /// Runs a program with the bundled environment, streams its output to the log, returns the exit code.
        private int Run(string exe, string args, string cwd, int timeoutSec, StringBuilder captured, bool echo, string stdin)
        {
            ProcessStartInfo psi = new ProcessStartInfo(exe, args);
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.RedirectStandardInput = stdin != null;
            psi.StandardOutputEncoding = Encoding.UTF8;
            psi.StandardErrorEncoding = Encoding.UTF8;
            psi.WorkingDirectory = cwd ?? appDir;
            ApplyEnv(psi);
            if (echo) Log("> " + Path.GetFileName(exe) + " " + args, Color.FromArgb(0, 90, 160));
            using (Process p = new Process())
            {
                p.StartInfo = psi;
                object gate = new object();
                DataReceivedEventHandler h = delegate (object s, DataReceivedEventArgs e)
                {
                    if (e.Data == null) return;
                    lock (gate) { if (captured != null) captured.AppendLine(e.Data); }
                    if (echo) Log("  " + e.Data, Color.FromArgb(70, 70, 70));
                };
                p.OutputDataReceived += h;
                p.ErrorDataReceived += h;
                try { p.Start(); }
                catch (Exception ex) { Log("  could not start " + exe + ": " + ex.Message, Red); return -1; }
                p.BeginOutputReadLine();
                p.BeginErrorReadLine();
                if (stdin != null)
                {
                    try
                    {
                        StreamWriter w = new StreamWriter(p.StandardInput.BaseStream, new UTF8Encoding(false));
                        w.Write(stdin);
                        w.Close();
                    }
                    catch (Exception ex) { Log("  could not send input: " + ex.Message, Red); }
                }
                if (!p.WaitForExit(timeoutSec * 1000))
                {
                    try { p.Kill(); } catch { }
                    Log("  timed out after " + timeoutSec + " s", Red);
                    return -2;
                }
                p.WaitForExit();
                return p.ExitCode;
            }
        }

        /// One of the repo's PowerShell scripts, run as its README shows, with the bundled toolchain.
        private int RunPs(string script, string args, int timeoutSec)
        {
            string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
            return Run(ps, "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + Q(Path.Combine(repo, script)) + " " + args,
                repo, timeoutSec, null, true, null);
        }

        private int RunCmd(string commandLine, string cwd, int timeoutSec)
        {
            string cmd = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "cmd.exe");
            return Run(cmd, "/d /c " + commandLine, cwd, timeoutSec, null, true, null);
        }

        private static string Q(string s) { return "\"" + s + "\""; }

        // ================================================================== step 2 checks and setup

        private void SetCheck(int i, CheckResult r)
        {
            UI(delegate
            {
                ListViewItem it = checks.Items[i];
                it.SubItems[1].Text = r.Ok ? "OK" : "Missing";
                it.SubItems[2].Text = r.Detail;
                it.ForeColor = r.Ok ? Green : Red;
            });
        }

        private CheckResult CheckPython()
        {
            if (!File.Exists(pyBase)) return new CheckResult(false, "python\\python.exe not found");
            StringBuilder sb = new StringBuilder();
            int rc = Run(pyBase, "--version", null, 30, sb, false, null);
            return new CheckResult(rc == 0, sb.ToString().Trim());
        }

        private CheckResult CheckJdk()
        {
            string java = Path.Combine(jdk, @"bin\java.exe");
            if (!File.Exists(java)) return new CheckResult(false, "jdk\\bin\\java.exe not found");
            if (!File.Exists(Path.Combine(jdk, @"bin\javac.exe")) || !File.Exists(Path.Combine(jdk, @"bin\jlink.exe")))
                return new CheckResult(false, "JDK is incomplete (javac/jlink missing)");
            StringBuilder sb = new StringBuilder();
            Run(java, "-version", null, 30, sb, false, null);
            Match m = Regex.Match(sb.ToString(), "version \"(\\d+)([^\"]*)\"");
            if (!m.Success) return new CheckResult(false, "could not read java -version");
            int major = int.Parse(m.Groups[1].Value);
            bool ok = major >= 17 && major <= 22;
            return new CheckResult(ok, "Java " + m.Groups[1].Value + m.Groups[2].Value + (ok ? "" : " (needs 17-22)"));
        }

        private CheckResult CheckPlatform()
        {
            return File.Exists(Path.Combine(sdk, @"platforms\android-34\android.jar")) ? new CheckResult(true, "platforms\\android-34") : new CheckResult(false, "android-34 not found");
        }

        private CheckResult CheckBuildTools()
        {
            string bt = Path.Combine(sdk, "build-tools");
            if (Directory.Exists(bt))
                foreach (string d in Directory.GetDirectories(bt, "34.*"))
                    if (File.Exists(Path.Combine(d, "aapt2.exe")) || File.Exists(Path.Combine(d, "aapt.exe")))
                        return new CheckResult(true, "build-tools\\" + Path.GetFileName(d));
            return new CheckResult(false, "build-tools 34.x not found");
        }

        private CheckResult CheckPlatformTools()
        {
            if (!File.Exists(Path.Combine(sdk, @"platform-tools\adb.exe"))) return new CheckResult(false, "platform-tools\\adb.exe not found");
            return new CheckResult(true, "adb " + ReadProp(Path.Combine(sdk, @"platform-tools\source.properties"), "Pkg.Revision"));
        }

        private CheckResult CheckLicences()
        {
            return File.Exists(Path.Combine(sdk, @"licenses\android-sdk-license")) ? new CheckResult(true, "accepted at bundle time") : new CheckResult(false, "licenses\\android-sdk-license missing");
        }

        private CheckResult CheckRepo()
        {
            if (!File.Exists(Path.Combine(repo, @"tools\tv.py")) || !File.Exists(Path.Combine(launcherDir, "gradlew.bat"))
                || !File.Exists(Path.Combine(repo, @"tools\disable.ps1")))
                return new CheckResult(false, "cleanyourtv folder incomplete");
            string info = Path.Combine(appDir, "bundle-info.txt");
            string commit = ReadProp(info, "repo_commit");
            int lists = 0;
            try { lists = Directory.GetDirectories(Path.Combine(repo, "examples")).Length; } catch { }
            return new CheckResult(true, string.Format("snapshot {0} {1}, {2} tested TVs", commit.Length > 10 ? commit.Substring(0, 10) : commit, ReadProp(info, "repo_date"), lists));
        }

        private CheckResult CheckGradleDist()
        {
            string dists = Path.Combine(gradleHome, @"wrapper\dists\gradle-8.9-bin");
            if (Directory.Exists(dists))
                foreach (string h in Directory.GetDirectories(dists))
                    if (File.Exists(Path.Combine(h, @"gradle-8.9\bin\gradle.bat"))) return new CheckResult(true, "gradle-8.9 (pre-extracted)");
            return new CheckResult(false, "Gradle 8.9 not found in gradle-home");
        }

        private CheckResult CheckGradleCache()
        {
            if (!Directory.Exists(Path.Combine(gradleHome, @"caches\modules-2\files-2.1\com.android.tools.build\gradle\8.5.2")))
                return new CheckResult(false, "Android Gradle Plugin 8.5.2 not cached");
            int groups = 0;
            try { groups = Directory.GetDirectories(Path.Combine(gradleHome, @"caches\modules-2\files-2.1")).Length; } catch { }
            return new CheckResult(true, "AGP 8.5.2 + " + groups + " Maven groups cached");
        }

        private CheckResult CheckLocalProps()
        {
            string lp = Path.Combine(launcherDir, "local.properties");
            if (!File.Exists(lp)) return new CheckResult(false, "not written yet");
            string v = ReadProp(lp, "sdk.dir").Replace("\\\\", "\\").Replace("\\:", ":");
            bool ok = string.Equals(v.TrimEnd('\\'), sdk.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);
            return new CheckResult(ok, ok ? "points at the bundled SDK" : "points elsewhere: " + v);
        }

        private CheckResult CheckVenv()
        {
            if (!File.Exists(venvPy)) return new CheckResult(false, "tools\\venv not created yet");
            StringBuilder sb = new StringBuilder();
            int rc = Run(venvPy, "-I -c \"import adb_shell, rsa, cryptography, sys; print('Python', sys.version.split()[0], '| cryptography', cryptography.__version__)\"",
                repo, 60, sb, false, null);
            return rc != 0 ? new CheckResult(false, "venv broken or packages missing") : new CheckResult(true, sb.ToString().Trim());
        }

        private bool RecheckAll()
        {
            CheckResult[] r = new CheckResult[] {
                CheckPython(), CheckJdk(), CheckPlatform(), CheckBuildTools(), CheckPlatformTools(), CheckLicences(),
                CheckRepo(), CheckGradleDist(), CheckGradleCache(), CheckLocalProps(), CheckVenv() };
            bool all = true;
            for (int i = 0; i < r.Length; i++) { SetCheck(i, r[i]); if (!r[i].Ok) all = false; }
            MarkDone(P_SETUP, all);
            UI(delegate
            {
                if (all) SetResult(p2Result, "All parts are in place. Press Next.", Green);
                else SetResult(p2Result, "Some parts are not ready yet (red above). Press 'Run the setup again'; if a part stays missing, reinstall the app.", Red);
            });
            if (all) { try { File.WriteAllText(marker, "Step 2 completed " + DateTime.Now.ToString("yyyy-MM-dd HH:mm") + "\r\n"); } catch { } }
            return all;
        }

        private bool DoSetup()
        {
            Log("=== Step 2: setting up the tools (offline) ===", Navy);
            CheckResult[] fixedParts = new CheckResult[] {
                CheckPython(), CheckJdk(), CheckPlatform(), CheckBuildTools(), CheckPlatformTools(), CheckLicences(),
                CheckRepo(), CheckGradleDist(), CheckGradleCache() };
            bool missing = false;
            for (int i = 0; i < fixedParts.Length; i++)
            {
                SetCheck(i, fixedParts[i]);
                if (!fixedParts[i].Ok) { missing = true; Log("  missing: " + CheckNames[i] + "  " + fixedParts[i].Detail, Red); }
            }
            if (missing)
            {
                Log("Part of the bundle is missing. Re-run the installer (it repairs the folder); this app never downloads anything.", Red);
                UI(delegate { SetResult(p2Result, "Part of the app's folder is missing. Run the installer again to repair it.", Red); });
                return false;
            }
            string lp = Path.Combine(launcherDir, "local.properties");
            File.WriteAllText(lp, "sdk.dir=" + sdk.Replace("\\", "\\\\") + "\r\n", Encoding.ASCII);
            Log("Wrote launcher\\local.properties -> " + sdk);
            SetCheck(9, CheckLocalProps());
            CheckResult v = CheckVenv();
            if (!v.Ok && Directory.Exists(venvDir))
            {
                Log("The existing Python environment does not work (folder moved?) - recreating it.", Orange);
                try { Directory.Delete(venvDir, true); } catch (Exception ex) { Log("  could not remove it: " + ex.Message, Red); return false; }
            }
            if (!v.Ok)
            {
                if (Run(pyBase, "-m venv " + Q(venvDir), repo, 300, null, true, null) != 0) { Log("Creating the Python environment failed.", Red); return false; }
                int rc = Run(venvPy, "-m pip install --no-index --find-links " + Q(wheels) + " -r " + Q(Path.Combine(repo, @"tools\requirements.txt")) + " --no-warn-script-location",
                    repo, 600, null, true, null);
                if (rc != 0) { Log("Installing the Python packages from the bundle failed.", Red); return false; }
            }
            SetCheck(10, CheckVenv());
            Log("Starting Gradle offline (the first start takes a minute)...");
            if (RunCmd("gradlew.bat --offline --version --console=plain", launcherDir, 600) != 0) { Log("Gradle could not start offline.", Red); return false; }
            return RecheckAll();
        }

        private bool TestBuild()
        {
            Log("=== Offline test build of the home screen (nothing is sent to the TV) ===", Navy);
            if (!File.Exists(Path.Combine(launcherDir, "local.properties"))) { Log("Run the setup first.", Red); return false; }
            Stopwatch sw = Stopwatch.StartNew();
            int rc = RunCmd("gradlew.bat assembleRelease --offline --console=plain", launcherDir, 1800);
            string apk = Path.Combine(launcherDir, @"app\build\outputs\apk\release\app-release.apk");
            if (rc == 0 && File.Exists(apk))
            {
                Log(string.Format("Build OK in {0:0} s: app-release.apk, {1} KB. The toolchain works fully offline.", sw.Elapsed.TotalSeconds, new FileInfo(apk).Length / 1024), Green);
                return true;
            }
            Log("The offline build failed (exit " + rc + ").", Red);
            return false;
        }

        // ================================================================== misc

        private void OpenShell()
        {
            string ps1 = Path.Combine(appDir, "Open-CleanYourTV-Shell.ps1");
            if (!File.Exists(ps1)) { MessageBox.Show(this, "Open-CleanYourTV-Shell.ps1 is missing; reinstall.", AppName); return; }
            string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
            string ip = TvIp;
            ProcessStartInfo psi = new ProcessStartInfo(ps, "-NoExit -NoProfile -ExecutionPolicy Bypass -File " + Q(ps1) + (ip.Length > 0 ? " -TvHost " + Q(ip) : ""));
            psi.UseShellExecute = true;
            psi.WorkingDirectory = repo;
            try { Process.Start(psi); } catch (Exception ex) { MessageBox.Show(this, ex.Message, AppName); }
        }

        private void ShowAbout()
        {
            string info = "";
            try { info = File.ReadAllText(Path.Combine(appDir, "bundle-info.txt")); } catch { }
            MessageBox.Show(this,
                AppName + " " + AppVersion + "\r\nby Sasanka Boruah, VU3INI  -  " + Email + "\r\n\r\n" +
                "A step-by-step, offline front end for CleanYourTV (github.com/Gathin23/cleanyourtv): it prepares the tools, " +
                "finds the tested list for your TV, lets you choose what to keep, cleans the TV, installs the new home screen, and can undo it all.\r\n\r\n" +
                "Bundled: CleanYourTV (MIT, Gathin23), Python (PSF licence), Eclipse Temurin JDK (GPLv2 + Classpath Exception), " +
                "Android SDK components (Android SDK Licence), Gradle (Apache 2.0) and its Maven dependencies. " +
                "See THIRD-PARTY-NOTICES.txt in the install folder.\r\n\r\n" + info,
                "About " + AppName, MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        private static string ReadProp(string file, string key)
        {
            try
            {
                if (!File.Exists(file)) return "";
                foreach (string line in File.ReadAllLines(file))
                {
                    int eq = line.IndexOf('=');
                    if (eq > 0 && line.Substring(0, eq).Trim() == key) return line.Substring(eq + 1).Trim();
                }
            }
            catch { }
            return "";
        }
    }
}
#####END
#####FILE src\Core.cs
// VU3INI Android TV Cleaner - logic that does not touch the UI: the TV list index, debloat list parsing and
// generation, matching a TV to a tested list, the launcher theme merge, and the settings file.
// C# 5 (the compiler built into Windows): no $"", ?. , nameof, expression bodies.
//
// Author: Sasanka Boruah, VU3INI  <hamvu3ini@gmail.com>

using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

namespace Vu3ini.AndroidTvCleaner
{
    /// One tested TV in the repo's examples\ folder.
    public sealed class ExampleInfo
    {
        public string Folder = "";
        public string Dir = "";
        public string Brand = "";
        public string Tv = "";
        public string Os = "";
        public string Notes = "";
        public List<string> Lists = new List<string>();   // file names: debloat.txt first, then debloat-*.txt
        public bool HasConfig;
        public override string ToString() { return Tv; }
    }

    /// One package line of a debloat list.
    public sealed class ListEntry
    {
        public string Package = "";
        public string Comment = "";
        public string Section = "";
        public bool DefaultDisable;   // true: an active line in the tested list; false: the list author kept it (commented)
        public bool Locked;           // core Android / TV middleware: never disabled (disable.ps1 refuses it too)
        public bool Disable;          // the user's choice
        public string Status = "";    // on the TV: "enabled", "already disabled", "not installed", "" (unknown)
    }

    /// What the probe read from the TV.
    public sealed class TvInfo
    {
        public string Model = "", Device = "", Manufacturer = "", Android = "", Sdk = "", Firmware = "", HomePackage = "";
        public HashSet<string> Installed = new HashSet<string>();
        public HashSet<string> Disabled = new HashSet<string>();
        public HashSet<string> ThirdParty = new HashSet<string>();
        public List<string> Leanback = new List<string>();
        public bool HasPackages { get { return Installed.Count > 0; } }
    }

    /// A "keep everything of this kind" switch on the What-to-keep page.
    public sealed class KeepCategory
    {
        public string Name;
        public string[] PackageWords;
        public string[] CommentWords;
        public KeepCategory(string name, string[] pkg, string[] comment) { Name = name; PackageWords = pkg; CommentWords = comment; }

        public bool Matches(ListEntry e)
        {
            string p = e.Package.ToLowerInvariant();
            string c = e.Comment.ToLowerInvariant();
            foreach (string w in PackageWords) if (p.Contains(w)) return true;
            foreach (string w in CommentWords) if (c.Contains(w)) return true;
            return false;
        }
    }

    public static class Core
    {
        // Same guard as tools\disable.ps1 / recovery.py: these are never disabled.
        public static readonly Regex CoreRe = new Regex(
            @"^(android|android\.ext\.(services|shared)|com\.android\.sdksandbox|com\.android\.location\.fused|com\.android\.systemui|com\.android\.shell|com\.android\.phone|com\.android\.settings|com\.android\.tv\.settings|com\.(google\.)?android\.(permissioncontroller|packageinstaller|ext\.services|ext\.shared|modulemetadata)|com\.google\.android\.overlay\.modules.*|com\.android\.providers\..*|com\.cltv\.mal|com\.mediatek\.(tis|tv\.service|tv\.agent))$");
        public static readonly Regex CoreOk = new Regex(@"^com\.android\.providers\.(calendar|contacts|userdictionary|blockednumber)$");
        public const string PkgPattern = @"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+";
        public static readonly Regex PkgRe = new Regex("^" + PkgPattern + "$");
        private static readonly Regex ActiveLine = new Regex(@"^(" + PkgPattern + @")\s*(?:#\s*(.*))?$");
        private static readonly Regex CommentedLine = new Regex(@"^#\s*(" + PkgPattern + @")\s*(?:#\s*(.*))?$");

        public const string LauncherPackage = "com.gathin.tvhome";
        public static readonly string[] KnownStockLaunchers = new string[] {
            "com.google.android.tvlauncher", "com.google.android.apps.tv.launcherx",
            "com.google.android.leanbacklauncher", "com.mitv.tvhome" };

        // Live TV apps seen in the tested lists, used to pre-fill the home screen's Inputs menu.
        public static readonly string[] KnownLiveTv = new string[] {
            "com.heytap.tv.livetv", "com.oneplus.tv.android.livetv", "com.mediatek.wwtv.tvcenter", "com.vt.tv.tvcenter",
            "com.sony.dtv.tvx", "com.tcl.tv", "com.tcl.tvinput", "com.xiaomi.mitv.tvplayer", "com.mitv.tvplayer",
            "com.droidlogic.tvsource", "com.realtek.tv", "com.google.android.tv", "com.android.tv" };

        public static readonly KeepCategory[] KeepCategories = new KeepCategory[] {
            new KeepCategory("Casting and screen mirroring",
                new string[] { "mediashell", "miracast", "mirror", "cast", "dlna", "airplay", "ars.sink", "multiscreen" },
                new string[] { "chromecast", "cast", "mirror", "screen shar", "dlna", "airplay" }),
            new KeepCategory("USB media players and file manager",
                new string[] { "filebrowser", "filemanager", "gallery", "musicplayer", "videoplayer", "mediaplayer", "mediacenter", "photoplayer" },
                new string[] { "(usb)", " usb", "file manager", "media player", "music player", "video player", "gallery" }),
            new KeepCategory("Bluetooth speaker mode",
                new string[] { "btspeaker", "bluetooth" },
                new string[] { "bluetooth speaker", "bluetooth" }),
            new KeepCategory("Voice assistant",
                new string[] { "katniss", "alexa", "voice" },
                new string[] { "google assistant", "voice", "alexa", "assistant mic" }),
            new KeepCategory("Streaming apps",
                new string[] { "netflix", "youtube", "amazonvideo", "primevideo", "hotstar", "jiocinema", "spotify", "sonyliv",
                               "graymatrix.did", "zee5", "airtel", "disney", "hulu", "tubi", "pluto", "mxplayer", "apps.youtube.music",
                               "tvmusic", "android.videos", "movies" },
                new string[] { "netflix", "youtube", "prime video", "streaming", "play movies", "spotify" })
        };

        public static bool IsCore(string pkg) { return CoreRe.IsMatch(pkg) && !CoreOk.IsMatch(pkg); }

        // ------------------------------------------------------------------ JSON

        public static Dictionary<string, object> ReadJson(string path)
        {
            try
            {
                if (!File.Exists(path)) return null;
                JavaScriptSerializer js = new JavaScriptSerializer();
                js.MaxJsonLength = 16 * 1024 * 1024;
                return js.DeserializeObject(File.ReadAllText(path, Encoding.UTF8)) as Dictionary<string, object>;
            }
            catch { return null; }
        }

        public static string JsonString(Dictionary<string, object> d, string key)
        {
            object v;
            if (d != null && d.TryGetValue(key, out v) && v != null) return Convert.ToString(v, System.Globalization.CultureInfo.InvariantCulture);
            return "";
        }

        public static List<string> JsonStringList(Dictionary<string, object> d, string key)
        {
            List<string> r = new List<string>();
            object v;
            if (d != null && d.TryGetValue(key, out v))
            {
                object[] arr = v as object[];
                if (arr != null) foreach (object o in arr) if (o != null) r.Add(o.ToString());
            }
            return r;
        }

        // ------------------------------------------------------------------ examples index

        public static List<ExampleInfo> LoadExamples(string examplesDir)
        {
            List<ExampleInfo> all = new List<ExampleInfo>();
            if (!Directory.Exists(examplesDir)) return all;
            foreach (string dir in Directory.GetDirectories(examplesDir))
            {
                List<string> lists = new List<string>();
                foreach (string f in Directory.GetFiles(dir, "debloat*.txt")) lists.Add(Path.GetFileName(f));
                if (lists.Count == 0) continue;
                lists.Sort(delegate (string a, string b)
                {
                    if (a == "debloat.txt") return -1;
                    if (b == "debloat.txt") return 1;
                    return string.Compare(a, b, StringComparison.OrdinalIgnoreCase);
                });
                ExampleInfo ex = new ExampleInfo();
                ex.Folder = Path.GetFileName(dir);
                ex.Dir = dir;
                ex.Lists = lists;
                ex.HasConfig = File.Exists(Path.Combine(dir, "config.json"));
                Dictionary<string, object> j = ReadJson(Path.Combine(dir, "tv.json"));
                ex.Brand = JsonString(j, "brand");
                ex.Tv = JsonString(j, "tv");
                ex.Os = JsonString(j, "os");
                ex.Notes = JsonString(j, "notes");
                if (ex.Brand.Length == 0) ex.Brand = "Other";
                if (ex.Tv.Length == 0) ex.Tv = ex.Folder;
                all.Add(ex);
            }
            all.Sort(delegate (ExampleInfo a, ExampleInfo b) { return string.Compare(a.Tv, b.Tv, StringComparison.OrdinalIgnoreCase); });
            return all;
        }

        /// Brands with their list counts, sorted by name (case-insensitive, first spelling wins).
        public static SortedDictionary<string, int> Brands(List<ExampleInfo> all)
        {
            SortedDictionary<string, int> r = new SortedDictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            foreach (ExampleInfo e in all)
            {
                int n;
                r.TryGetValue(e.Brand, out n);
                r[e.Brand] = n + 1;
            }
            return r;
        }

        private static bool ContainsWord(string hay, string word)
        {
            if (word.Length == 0) return false;
            return Regex.IsMatch(hay, "(^|[^a-z0-9])" + Regex.Escape(word) + "($|[^a-z0-9])");
        }

        /// The tested list that best fits the probed TV, or null. score >= 5 means the device codename or the
        /// model name was found; lower scores are brand-only and are not offered as a match.
        public static ExampleInfo BestMatch(List<ExampleInfo> all, TvInfo tv, out int bestScore)
        {
            bestScore = 0;
            ExampleInfo best = null;
            if (tv == null) return null;
            string man = tv.Manufacturer.Trim().ToLowerInvariant();
            string dev = tv.Device.Trim().ToLowerInvariant();
            string model = tv.Model.Trim().ToLowerInvariant();
            List<string> modelTokens = new List<string>();
            foreach (string t in Regex.Split(model, "[^a-z0-9]+"))
                if (t.Length >= 3 && Regex.IsMatch(t, "[0-9]")) modelTokens.Add(t);
            foreach (ExampleInfo e in all)
            {
                string hay = (e.Folder.Replace('-', ' ') + " " + e.Tv).ToLowerInvariant();
                string brand = e.Brand.ToLowerInvariant();
                int s = 0;
                if (man.Length > 1 && (brand.Contains(man) || man.Contains(brand) || hay.Contains(man))) s += 2;
                if (dev.Length >= 3 && ContainsWord(hay, dev)) s += 5;
                if (model.Length >= 3 && ContainsWord(hay, model)) s += 4;
                else
                {
                    int tokenScore = 0;
                    foreach (string t in modelTokens) if (ContainsWord(hay, t)) tokenScore += 2;
                    s += Math.Min(tokenScore, 4);
                }
                if (s > bestScore) { bestScore = s; best = e; }
            }
            return bestScore >= 5 ? best : null;
        }

        /// The brand that matches the TV's manufacturer, or "".
        public static string BrandFor(List<ExampleInfo> all, TvInfo tv)
        {
            if (tv == null) return "";
            string man = tv.Manufacturer.Trim().ToLowerInvariant();
            if (man.Length < 2) return "";
            foreach (ExampleInfo e in all) if (e.Brand.ToLowerInvariant() == man) return e.Brand;
            foreach (ExampleInfo e in all)
            {
                string b = e.Brand.ToLowerInvariant();
                if (b.Contains(man) || man.Contains(b)) return e.Brand;
            }
            return "";
        }

        // ------------------------------------------------------------------ debloat lists

        public static List<ListEntry> ParseList(string path)
        {
            List<ListEntry> entries = new List<ListEntry>();
            HashSet<string> seen = new HashSet<string>();
            string[] lines = File.ReadAllLines(path, Encoding.UTF8);
            string section = "General";
            for (int i = 0; i < lines.Length; i++)
            {
                string t = lines[i].Trim();
                if (t.Length == 0) continue;
                Match m = ActiveLine.Match(t);
                bool active = m.Success;
                if (!active) m = CommentedLine.Match(t);
                if (m.Success)
                {
                    string pkg = m.Groups[1].Value;
                    if (seen.Contains(pkg)) continue;
                    seen.Add(pkg);
                    ListEntry e = new ListEntry();
                    e.Package = pkg;
                    e.Comment = m.Groups[2].Success ? m.Groups[2].Value.Trim() : "";
                    e.Section = section;
                    e.Locked = IsCore(pkg);
                    e.DefaultDisable = active && !e.Locked;
                    e.Disable = e.DefaultDisable;
                    entries.Add(e);
                    continue;
                }
                // A section heading: a comment right after a blank line and right before a package line.
                if (t.StartsWith("#") && (i == 0 || lines[i - 1].Trim().Length == 0) && i + 1 < lines.Length)
                {
                    string next = lines[i + 1].Trim();
                    if (ActiveLine.IsMatch(next) || CommentedLine.IsMatch(next))
                    {
                        string h = t.TrimStart('#').Trim();
                        if (h.Length > 0) section = h.Length > 90 ? h.Substring(0, 87) + "..." : h;
                    }
                }
            }
            return entries;
        }

        public static void ApplyStatus(List<ListEntry> entries, TvInfo tv)
        {
            foreach (ListEntry e in entries)
            {
                if (tv == null || !tv.HasPackages) e.Status = "";
                else if (!tv.Installed.Contains(e.Package)) e.Status = "not installed";
                else if (tv.Disabled.Contains(e.Package)) e.Status = "already disabled";
                else e.Status = "enabled";
            }
        }

        /// The list the user chose: the tested list with every line they kept commented out and every line they
        /// turned on uncommented. Comments and order stay as in the tested list.
        public static string BuildList(string sourcePath, List<ListEntry> entries, string sourceLabel)
        {
            Dictionary<string, ListEntry> byPkg = new Dictionary<string, ListEntry>();
            foreach (ListEntry e in entries) if (!byPkg.ContainsKey(e.Package)) byPkg[e.Package] = e;
            HashSet<string> written = new HashSet<string>();
            StringBuilder sb = new StringBuilder();
            int on = 0;
            foreach (ListEntry e in entries) if (e.Disable && !e.Locked) on++;
            sb.AppendLine("# Generated by VU3INI Android TV Cleaner on " + DateTime.Now.ToString("yyyy-MM-dd HH:mm"));
            sb.AppendLine("# From: " + sourceLabel);
            sb.AppendLine("# " + on + " packages to disable. Lines marked 'kept by your choice' stay enabled.");
            sb.AppendLine("# Change the choices in the app (step 5), not here: the app rewrites this file.");
            sb.AppendLine("#");
            foreach (string raw in File.ReadAllLines(sourcePath, Encoding.UTF8))
            {
                string t = raw.Trim();
                Match m = ActiveLine.Match(t);
                bool active = m.Success;
                if (!active) m = CommentedLine.Match(t);
                if (!m.Success) { sb.AppendLine(raw); continue; }
                string pkg = m.Groups[1].Value;
                string comment = m.Groups[2].Success ? m.Groups[2].Value.Trim() : "";
                ListEntry e;
                if (!byPkg.TryGetValue(pkg, out e) || written.Contains(pkg)) { sb.AppendLine(active ? "# " + raw : raw); continue; }
                written.Add(pkg);
                bool disable = e.Disable && !e.Locked;
                if (disable)
                {
                    if (active) sb.AppendLine(raw);
                    else sb.AppendLine(pkg.PadRight(44) + " # " + (comment.Length > 0 ? comment + " " : "") + "(disabled by your choice)");
                }
                else
                {
                    if (active) sb.AppendLine("# " + pkg.PadRight(42) + " # " + (comment.Length > 0 ? comment + " " : "") + "(kept by your choice)");
                    else sb.AppendLine(raw);
                }
            }
            return sb.ToString();
        }

        public static int CountDisable(List<ListEntry> entries)
        {
            int n = 0;
            foreach (ListEntry e in entries) if (e.Disable && !e.Locked) n++;
            return n;
        }

        // ------------------------------------------------------------------ probe

        /// Splits tv.py --batch output ("$ command" then its output) into command -> output.
        public static Dictionary<string, string> SplitBatch(string output)
        {
            Dictionary<string, string> r = new Dictionary<string, string>();
            string cur = null;
            StringBuilder sb = new StringBuilder();
            foreach (string line in output.Replace("\r\n", "\n").Split('\n'))
            {
                if (line.StartsWith("$ "))
                {
                    if (cur != null) r[cur] = sb.ToString();
                    cur = line.Substring(2).Trim();
                    sb.Length = 0;
                }
                else if (cur != null) sb.AppendLine(line);
            }
            if (cur != null) r[cur] = sb.ToString();
            return r;
        }

        public static readonly string[] ProbeCommands = new string[] {
            "getprop ro.product.model",
            "getprop ro.product.device",
            "getprop ro.product.manufacturer",
            "getprop ro.build.version.release",
            "getprop ro.build.version.sdk",
            "getprop ro.build.display.id",
            "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME",
            "pm list packages",
            "pm list packages -d",
            "pm list packages -3",
            "cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER"
        };

        private static string Get(Dictionary<string, string> d, string k)
        {
            string v;
            return d.TryGetValue(k, out v) ? v.Trim() : "";
        }

        private static void ReadPackages(string text, HashSet<string> into)
        {
            foreach (string l in text.Replace("\r", "").Split('\n'))
            {
                string t = l.Trim();
                if (t.StartsWith("package:"))
                {
                    string p = t.Substring(8).Trim();
                    if (PkgRe.IsMatch(p)) into.Add(p);
                }
            }
        }

        public static TvInfo ParseProbe(string output)
        {
            Dictionary<string, string> d = SplitBatch(output);
            TvInfo tv = new TvInfo();
            tv.Model = Get(d, ProbeCommands[0]);
            tv.Device = Get(d, ProbeCommands[1]);
            tv.Manufacturer = Get(d, ProbeCommands[2]);
            tv.Android = Get(d, ProbeCommands[3]);
            tv.Sdk = Get(d, ProbeCommands[4]);
            tv.Firmware = Get(d, ProbeCommands[5]);
            Regex comp = new Regex(@"(" + PkgPattern + @")/");
            foreach (string l in Get(d, ProbeCommands[6]).Replace("\r", "").Split('\n'))
            {
                Match m = comp.Match(l.Trim());
                if (m.Success) tv.HomePackage = m.Groups[1].Value;   // last component line wins
            }
            ReadPackages(Get(d, ProbeCommands[7]), tv.Installed);
            ReadPackages(Get(d, ProbeCommands[8]), tv.Disabled);
            ReadPackages(Get(d, ProbeCommands[9]), tv.ThirdParty);
            Regex named = new Regex(@"packageName=(" + PkgPattern + ")");
            foreach (string l in Get(d, ProbeCommands[10]).Replace("\r", "").Split('\n'))
            {
                string t = l.Trim();
                Match m = comp.Match(t);
                if (!m.Success || m.Index != 0) m = named.Match(t);
                if (m.Success)
                {
                    string p = m.Groups[1].Value;
                    if (!tv.Leanback.Contains(p)) tv.Leanback.Add(p);
                }
            }
            return tv;
        }

        // ------------------------------------------------------------------ launcher theme

        private static void CopyDir(string from, string to)
        {
            Directory.CreateDirectory(to);
            foreach (string f in Directory.GetFiles(from))
            {
                string n = Path.GetFileName(f);
                if (n.Equals("screenshot.jpg", StringComparison.OrdinalIgnoreCase) || n.Equals("config.json", StringComparison.OrdinalIgnoreCase)
                    || n.EndsWith(".md", StringComparison.OrdinalIgnoreCase)) continue;
                File.Copy(f, Path.Combine(to, n), true);
            }
            foreach (string d in Directory.GetDirectories(from)) CopyDir(d, Path.Combine(to, Path.GetFileName(d)));
        }

        /// Builds the theme folder pushed with tools\theme.ps1: the chosen theme's files and config, overlaid with
        /// the tested TV's config.json (its dock, Live TV app and remote-key fixes), overlaid with the user's
        /// choices. A null value in overrides removes that key.
        public static Dictionary<string, object> BuildTheme(string themeDir, string exampleConfig, Dictionary<string, object> overrides, string outDir)
        {
            if (Directory.Exists(outDir)) Directory.Delete(outDir, true);
            Directory.CreateDirectory(outDir);
            Dictionary<string, object> cfg = new Dictionary<string, object>();
            if (!string.IsNullOrEmpty(themeDir) && Directory.Exists(themeDir))
            {
                CopyDir(themeDir, outDir);
                Dictionary<string, object> t = ReadJson(Path.Combine(themeDir, "config.json"));
                if (t != null) foreach (KeyValuePair<string, object> kv in t) cfg[kv.Key] = kv.Value;
            }
            Dictionary<string, object> ex = string.IsNullOrEmpty(exampleConfig) ? null : ReadJson(exampleConfig);
            if (ex != null) foreach (KeyValuePair<string, object> kv in ex) cfg[kv.Key] = kv.Value;
            foreach (KeyValuePair<string, object> kv in overrides)
            {
                if (kv.Value == null) cfg.Remove(kv.Key);
                else cfg[kv.Key] = kv.Value;
            }
            JavaScriptSerializer js = new JavaScriptSerializer();
            File.WriteAllText(Path.Combine(outDir, "config.json"), PrettyJson(js.Serialize(cfg)), new UTF8Encoding(false));
            return cfg;
        }

        /// Indents compact JSON so the file is readable; strings are copied verbatim.
        public static string PrettyJson(string json)
        {
            StringBuilder sb = new StringBuilder();
            int indent = 0;
            bool inStr = false;
            for (int i = 0; i < json.Length; i++)
            {
                char c = json[i];
                if (inStr)
                {
                    sb.Append(c);
                    if (c == '\\' && i + 1 < json.Length) { sb.Append(json[++i]); }
                    else if (c == '"') inStr = false;
                    continue;
                }
                switch (c)
                {
                    case '"': inStr = true; sb.Append(c); break;
                    case '{':
                    case '[':
                        if (i + 1 < json.Length && (json[i + 1] == '}' || json[i + 1] == ']')) { sb.Append(c).Append(json[++i]); break; }
                        sb.Append(c); indent++; sb.Append('\n').Append(' ', indent * 2); break;
                    case '}':
                    case ']':
                        indent--; sb.Append('\n').Append(' ', indent * 2).Append(c); break;
                    case ',': sb.Append(c).Append('\n').Append(' ', indent * 2); break;
                    case ':': sb.Append(": "); break;
                    default: sb.Append(c); break;
                }
            }
            return sb.ToString() + "\n";
        }
    }

    /// key=value settings in %APPDATA%\VU3INI\AndroidTVCleaner\settings.txt
    public sealed class Settings
    {
        private readonly string file;
        private readonly Dictionary<string, string> values = new Dictionary<string, string>();

        public Settings(string file)
        {
            this.file = file;
            try
            {
                if (File.Exists(file))
                    foreach (string line in File.ReadAllLines(file, Encoding.UTF8))
                    {
                        int eq = line.IndexOf('=');
                        if (eq > 0) values[line.Substring(0, eq)] = line.Substring(eq + 1);
                    }
            }
            catch { }
        }

        public string Get(string key) { string v; return values.TryGetValue(key, out v) ? v : ""; }
        public bool GetBool(string key) { return Get(key) == "1"; }

        public void Set(string key, string value)
        {
            values[key] = (value ?? "").Replace("\r", " ").Replace("\n", " ");
            Save();
        }

        public void SetBool(string key, bool v) { Set(key, v ? "1" : "0"); }

        private void Save()
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(file));
                List<string> lines = new List<string>();
                foreach (KeyValuePair<string, string> kv in values) lines.Add(kv.Key + "=" + kv.Value);
                lines.Sort(StringComparer.Ordinal);
                File.WriteAllLines(file, lines.ToArray(), new UTF8Encoding(false));
            }
            catch { }
        }
    }
}
#####END
#####FILE src\app.manifest
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="2.0.0.0" name="VU3INI.AndroidTVCleaner"/>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v2">
    <security>
      <requestedPrivileges xmlns="urn:schemas-microsoft-com:asm.v3">
        <requestedExecutionLevel level="asInvoker" uiAccess="false"/>
      </requestedPrivileges>
    </security>
  </trustInfo>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <!-- Windows 10 and 11 -->
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/>
    </application>
  </compatibility>
  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/pm</dpiAware>
      <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2, PerMonitor</dpiAwareness>
    </windowsSettings>
  </application>
  <dependency>
    <dependentAssembly>
      <assemblyIdentity type="win32" name="Microsoft.Windows.Common-Controls" version="6.0.0.0"
        processorArchitecture="*" publicKeyToken="6595b64144ccf1df" language="*"/>
    </dependentAssembly>
  </dependency>
</assembly>
#####END
#####FILE src\Open-CleanYourTV-Shell.ps1
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
#####END
#####FILE installer\VU3INI-AndroidTVCleaner.iss
; VU3INI Android TV Cleaner - Inno Setup script
; Compiled by build\Build-Installer.ps1, which passes /DStageDir, /DOutputDir and /DAppVersion.

#ifndef StageDir
  #define StageDir "C:\VU3INI-build\stage"
#endif
#ifndef OutputDir
  #define OutputDir "..\output"
#endif
#ifndef AppVersion
  #define AppVersion "2.0"
#endif

#define AppName "VU3INI Android TV Cleaner"
#define AppExe  "VU3INI Android TV Cleaner.exe"

[Setup]
AppId={{6B8E3C52-1F4D-4E7A-9A3B-5C2D1E0F9A31}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=VU3INI (Sasanka Boruah)
AppContact=hamvu3ini@gmail.com
AppComments=Offline Step 2 toolchain for CleanYourTV (Android TV / Google TV debloat)
VersionInfoVersion={#AppVersion}.0.0
VersionInfoCompany=VU3INI
VersionInfoDescription={#AppName} Setup
; No spaces in the default path: Gradle and the Android SDK prefer it. No admin rights needed.
DefaultDirName=C:\VU3INI\ATVCleaner
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
#if Ver >= 0x06030000
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#else
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
#endif
MinVersion=10.0.17763
OutputDir={#OutputDir}
OutputBaseFilename=VU3INI-Android-TV-Cleaner-Setup-{#AppVersion}
SetupIconFile={#StageDir}\assets\app.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
LZMAUseSeparateProcess=yes
LZMANumBlockThreads=4
DiskSpanning=no
ExtraDiskSpaceRequired=600000000
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"
Name: "{autoprograms}\{#AppName} - CleanYourTV PowerShell"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
  Parameters: "-NoExit -NoProfile -ExecutionPolicy Bypass -File ""{app}\Open-CleanYourTV-Shell.ps1"""; \
  WorkingDir: "{app}\cleanyourtv"; IconFilename: "{app}\assets\app.ico"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Parameters: "--setup"; Description: "Launch {#AppName} and finish Step 2 setup"; \
  Flags: nowait postinstall skipifsilent

[UninstallRun]
; Stop a Gradle daemon left running so its files can be removed.
Filename: "{cmd}"; Parameters: "/d /c set ""JAVA_HOME={app}\jdk"" && set ""GRADLE_USER_HOME={app}\gradle-home"" && gradlew.bat --stop"; \
  WorkingDir: "{app}\cleanyourtv\launcher"; Flags: runhidden; RunOnceId: "StopGradleDaemon"

[UninstallDelete]
; Files created after installation (venv, build outputs, Gradle's runtime caches).
Type: filesandordirs; Name: "{app}\cleanyourtv\tools\venv"
Type: filesandordirs; Name: "{app}\cleanyourtv\launcher\app\build"
Type: filesandordirs; Name: "{app}\cleanyourtv\launcher\build"
Type: filesandordirs; Name: "{app}\cleanyourtv\launcher\.gradle"
Type: files;          Name: "{app}\cleanyourtv\launcher\local.properties"
Type: filesandordirs; Name: "{app}\gradle-home"
Type: files;          Name: "{app}\setup-done.txt"
Type: filesandordirs; Name: "{app}\python\Lib\__pycache__"

[Code]
function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = wpSelectDir then
  begin
    if Pos(' ', WizardDirValue) > 0 then
    begin
      MsgBox('Please choose a folder without spaces (for example C:\VU3INI\ATVCleaner).' + #13#10 +
             'Gradle and the Android SDK do not work reliably from paths with spaces.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;
#####END
#####FILE branding\README-LOGO.txt
vu3ini-logo.png here is your VU3INI logo; Build-Installer.bat carries the same file inside it.
To change the logo, put a new vu3ini-logo.png next to Build-Installer.bat and run it.
#####END
#####B64FILE branding\vu3ini-logo.png
iVBORw0KGgoAAAANSUhEUgAAAgAAAAIACAMAAADDpiTIAAADAFBMVEX///////7///z9//7//v/+
/v/+/v7+/vz8/v3//f79/f79/f39/fv9/Pv8/Pz8+/v6+/v6+Pfo7/H907bR1df9xKH7vpjvwKK0
wcr4uZP2uJP3tpH2tpD1t5H3t433to31to71to31tozzuJL0to/QuKqkuMf2tY71tZH1tY/1tY30
tY70tYz0tYv2tI30tJD0tI70tIz1s4z1sYnztI7ztIvxtI7xsYrrqIXapIapqqyfpKpuo8TamHfX
knDVjGvTjGrRjm3Ri2nOjm3CkHfTiGfRh2XPh2XEh2raf2q+fmj0amnaZmGVlpeSiIODhIVZja6T
dmmPZlVscXViY2R9VUlcWVlUVFZSUVJPUFNOTk5MS0w+oNk6ndg7nNg5nNg5nNc5nNU4nNc2nNc8
m9Y5m9o5m9g5m9Y4m9c4m9Y4m9Q3m9c3m9Y3m9Q1m9c7mtY4mtg4mtc4mdc4mtU3mtg3mtY3mdY3
mtU1mtY7lc80ltM1gLEtcqQsbaAmbKMjbKIpaZ4maZ8laZ8iaZ8nZponXYjUMzPULi7SLi/SLi3S
LizRLi3TLS3RLTDRLS7RLSzTLC3RLC3NNDS5NTjMLi7OLS3QLC3QLCvNLC3TKyzRKy3RKyvTKSzR
KSzQKy7QKyzQKizQKyrQKSvPKyzPKSzHKiyvICOkHiJhRkNKSUpISEhFRkZERERDQ0NCQkJBQUJC
QUFBQUFBQUBBQEA/QkJAQEFAQEA+QEFAQD9YOTM/P0A/Pz8/Pz0/PT4+Pz8+Pj8+Pj49Pj4+Pj09
PT2fIiWgHiKgHCGMJymAHiFMJiFPExM8PDw7Ozs6Ojo4ODgnPU81NTUyMjIvLy8iMDwtLS0sLCwr
KystKScoKSkhJiorHBgeHh8YGh0VFRYrDAsXDgwQERIPDA0JERgKDRAJDA8KCw0GCg4JCAwICAcE
CAsbAwMOAwIHBQcHAQIFBQcEBAQEAQIDBAcDAwMDBAICAgUCAgICAgECAAEBAwYBAQMBAQEBAgAB
AAEAAwYAAAMAAAAC9vZgAAEAAElEQVR42tT9+VtTd/4+joeqR9tYBq2grIowLxRUlB0dcMPl4rqQ
siO41b3L6Nh2HK1au+j/AgmJxVYq4tRofuITiEkEDCSRIIYkFUEsjqWD5ns/nucknCQngPOa1/u6
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
Qq8JAAAAAElFTkSuQmCC
#####END
