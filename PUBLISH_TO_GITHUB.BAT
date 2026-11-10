@echo off
rem ===========================================================================
rem  VU3INI Android TV Cleaner - publish this folder to GitHub
rem  by Sasanka Boruah, VU3INI - hamvu3ini@gmail.com
rem
rem  First run : creates a GitHub repository and uploads this folder.
rem  Later runs: uploads whatever changed since the last run.
rem  Optional  : publishes output\VU3INI-Android-TV-Cleaner-Setup-*.exe and the
rem              PDF guide as a GitHub Release, so people can download the
rem              installer directly.
rem
rem  Needs Git for Windows. The GitHub CLI (gh) is recommended: it creates the
rem  repository and handles sign-in in your browser. Both can be installed from
rem  here with winget (built into Windows 10/11).
rem ===========================================================================
setlocal EnableExtensions
title VU3INI Android TV Cleaner - publish to GitHub
cd /d "%~dp0"

set "DEFAULT_REPO=VU3INI-Android-TV-Cleaner"
set "DESCRIPTION=Offline Windows wizard that debloats Android TV / Google TV (OnePlus and 120+ brands) using CleanYourTV - by VU3INI"
set "APPVER=2.0"

echo.
echo  VU3INI Android TV Cleaner - publish to GitHub
echo  ---------------------------------------------
echo  Folder: %CD%
echo.

rem ---------------------------------------------------------------- Git
where git >nul 2>nul
if not errorlevel 1 goto :have_git
echo  Git for Windows is not installed.
call :ask_yes "Install it now with winget" INSTALL_GIT
if /i not "%INSTALL_GIT%"=="Y" goto :need_git
winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
echo.
echo  Git was installed. Close this window and run PUBLISH_TO_GITHUB.BAT again
echo  so that Windows picks up the new program.
goto :end_pause
:have_git

rem ---------------------------------------------------------------- GitHub CLI (optional)
set "HAVE_GH=0"
where gh >nul 2>nul
if not errorlevel 1 set "HAVE_GH=1"
if "%HAVE_GH%"=="1" goto :gh_checked
echo  The GitHub CLI (gh) is not installed. It is the easy way: it creates the
echo  repository for you and signs in through your browser.
call :ask_yes "Install the GitHub CLI now with winget" INSTALL_GH
if /i not "%INSTALL_GH%"=="Y" goto :no_gh
winget install --id GitHub.cli -e --source winget --accept-package-agreements --accept-source-agreements
echo.
echo  The GitHub CLI was installed. Close this window and run PUBLISH_TO_GITHUB.BAT again.
goto :end_pause
:no_gh
echo  Continuing without it: you will create an empty repository on github.com yourself.
echo.
:gh_checked

rem ---------------------------------------------------------------- your name for commits
for /f "delims=" %%A in ('git config --global user.name 2^>nul') do set "GIT_NAME=%%A"
for /f "delims=" %%A in ('git config --global user.email 2^>nul') do set "GIT_EMAIL=%%A"
if defined GIT_NAME goto :name_ok
set "GIT_NAME=Sasanka Boruah - VU3INI"
set /p "GIT_NAME=Your name for the commit history [Sasanka Boruah - VU3INI]: "
:name_ok
if defined GIT_EMAIL goto :email_ok
set "GIT_EMAIL=hamvu3ini@gmail.com"
set /p "GIT_EMAIL=Your e-mail for the commit history [hamvu3ini@gmail.com]: "
:email_ok

rem ---------------------------------------------------------------- repository files
if not exist ".gitignore" (
  > ".gitignore" (
    echo # Build results - publish the installer as a GitHub Release instead
    echo output/
    echo VU3INI-ATVC-builder-files/
    echo *.exe
    echo *.zip
    echo *.log
    echo Thumbs.db
    echo desktop.ini
  )
  echo  Created .gitignore
)
if not exist ".gitattributes" (
  > ".gitattributes" (
    echo # Windows scripts and sources keep CRLF line endings; images and PDFs are binary
    echo *.bat text eol=crlf
    echo *.BAT text eol=crlf
    echo *.cmd text eol=crlf
    echo *.ps1 text eol=crlf
    echo *.cs text eol=crlf
    echo *.iss text eol=crlf
    echo *.manifest text eol=crlf
    echo *.txt text eol=crlf
    echo *.md text eol=crlf
    echo *.png binary
    echo *.jpg binary
    echo *.pdf binary
    echo *.ico binary
  )
  echo  Created .gitattributes
)

if not exist ".git" (
  git init -q
  if errorlevel 1 goto :git_failed
  echo  Started a new Git repository here.
)
git symbolic-ref HEAD refs/heads/main >nul 2>nul
git config user.name "%GIT_NAME%"
git config user.email "%GIT_EMAIL%"
git config core.autocrlf false

rem ---------------------------------------------------------------- commit
git add -A
if errorlevel 1 goto :git_failed
git diff --cached --quiet
if not errorlevel 1 (
  echo  No changes since the last commit.
  goto :committed
)
set "MSG=VU3INI Android TV Cleaner %APPVER%"
git rev-parse --verify HEAD >nul 2>nul
if errorlevel 1 goto :do_commit
set "MSG=Update"
set /p "MSG=Describe this update in a few words [Update]: "
:do_commit
call :commit
if errorlevel 1 goto :git_failed
:committed

rem ---------------------------------------------------------------- remote
git remote get-url origin >nul 2>nul
if not errorlevel 1 goto :push

if "%HAVE_GH%"=="1" goto :create_with_gh

echo.
echo  Create an EMPTY repository on GitHub now:
echo    1. Open https://github.com/new
echo    2. Repository name: %DEFAULT_REPO%   (no README, no licence, no .gitignore)
echo    3. Choose Public or Private, then press "Create repository"
echo    4. Copy its address, e.g. https://github.com/yourname/%DEFAULT_REPO%.git
start "" "https://github.com/new"
echo.
set "REMOTE_URL="
set /p "REMOTE_URL=Paste the repository address here: "
if not defined REMOTE_URL (
  echo  No address given - nothing was uploaded. Run this again when ready.
  goto :end_pause
)
git remote add origin "%REMOTE_URL%"
if errorlevel 1 goto :git_failed
goto :push

:create_with_gh
gh auth status >nul 2>nul
if not errorlevel 1 goto :signed_in
echo.
echo  Sign in to GitHub: a browser window opens; copy the one-time code shown here
echo  into it and approve.
gh auth login --hostname github.com --git-protocol https --web
if errorlevel 1 (
  echo  Sign-in did not complete. Run this again to retry.
  goto :end_pause
)
:signed_in
gh auth setup-git >nul 2>nul
echo.
set "REPO_NAME=%DEFAULT_REPO%"
set /p "REPO_NAME=Repository name [%DEFAULT_REPO%]: "
set "VIS=public"
call :ask_yes "Make it public (anyone can see and download it)" PUB
if /i not "%PUB%"=="Y" set "VIS=private"
echo  Creating %VIS% repository %REPO_NAME% on GitHub...
gh repo create "%REPO_NAME%" --%VIS% --source . --remote origin --description "%DESCRIPTION%"
if errorlevel 1 (
  echo  GitHub did not create the repository. If it already exists, add it with:
  echo     git remote add origin https://github.com/YOURNAME/%REPO_NAME%.git
  echo  and run this file again.
  goto :end_pause
)
gh repo edit --add-topic android-tv --add-topic google-tv --add-topic debloat --add-topic privacy --add-topic oneplus --add-topic windows --add-topic cleanyourtv >nul 2>nul

:push
echo.
echo  Uploading to GitHub...
git push -u origin main
if errorlevel 1 (
  echo.
  echo  The upload failed. Common causes: no internet, not signed in, or the GitHub
  echo  repository was not empty ^(created with a README^). For the last case run:
  echo     git pull --rebase origin main    and then this file again.
  goto :end_pause
)
for /f "delims=" %%U in ('git remote get-url origin') do set "ORIGIN=%%U"
echo.
echo  Done: the source is on GitHub - %ORIGIN%

rem ---------------------------------------------------------------- optional release
set "SETUP="
for %%F in ("output\VU3INI-Android-TV-Cleaner-Setup-*.exe") do set "SETUP=%%~fF"
if not defined SETUP goto :finish
if "%HAVE_GH%"=="1" goto :offer_release
echo.
echo  Tip: to let people download the installer, create a Release on GitHub
echo  (repository page, Releases, Draft a new release) and attach:
echo     %SETUP%
goto :finish
:offer_release
echo.
echo  Found the installer: %SETUP%
call :ask_yes "Publish it (and the PDF guide) as GitHub Release v%APPVER%" REL
if /i not "%REL%"=="Y" goto :finish
set "NOTES=%TEMP%\vu3ini-release-notes.txt"
> "%NOTES%" (
  echo VU3INI Android TV Cleaner %APPVER% - offline installer for Windows 10/11 ^(64-bit^).
  echo.
  echo Download VU3INI-Android-TV-Cleaner-Setup-%APPVER%.exe, run it ^(SmartScreen: More info - Run anyway^),
  echo keep the folder C:\VU3INI\ATVCleaner and follow the 8 steps in the app.
  echo The PDF guide explains everything with screenshots.
  echo.
  echo Built on CleanYourTV ^(https://github.com/Gathin23/cleanyourtv, MIT^).
)
set "GUIDE="
if exist "VU3INI-Android-TV-Cleaner-Guide.pdf" set "GUIDE=VU3INI-Android-TV-Cleaner-Guide.pdf"
echo  Uploading the release (the installer is large; this can take a while)...
gh release view "v%APPVER%" >nul 2>nul
if not errorlevel 1 (
  gh release upload "v%APPVER%" "%SETUP%" %GUIDE% --clobber
) else (
  gh release create "v%APPVER%" "%SETUP%" %GUIDE% --title "VU3INI Android TV Cleaner %APPVER%" --notes-file "%NOTES%"
)
if errorlevel 1 (
  echo  The release upload failed; the source code is already on GitHub. Run this again to retry.
) else (
  echo  Release v%APPVER% published.
)
del "%NOTES%" >nul 2>nul

:finish
echo.
if not "%HAVE_GH%"=="1" goto :end_pause
call :ask_yes "Open the repository in your browser" OPEN
if /i "%OPEN%"=="Y" gh repo view --web >nul 2>nul
goto :end_pause

rem ================================================================ helpers
:commit
git commit -q -m "%MSG%"
if errorlevel 1 exit /b 1
echo  Committed: %MSG%
exit /b 0

:ask_yes
rem  %1 = question, %2 = variable to receive Y or N
set "%~2=N"
set "_ANS="
set /p "_ANS=%~1? [Y/N]: "
if /i "%_ANS%"=="Y" set "%~2=Y"
if /i "%_ANS%"=="YES" set "%~2=Y"
exit /b 0

:need_git
echo.
echo  Install Git for Windows from https://git-scm.com/download/win and run this again.
goto :end_pause

:git_failed
echo.
echo  A Git command failed - see the message above.
goto :end_pause

:end_pause
echo.
pause
endlocal
exit /b 0
