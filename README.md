<p align="center"><img src="branding/vu3ini-logo.png" alt="VU3INI" width="160"></p>

# VU3INI Android TV Cleaner

A Windows 10/11 app that does **Step 2 of [CleanYourTV](https://github.com/Gathin23/cleanyourtv)**: it sets up
Python, a JDK, the Android SDK, Gradle and the CleanYourTV repository so the repo's scripts can debloat your
Android TV / Google TV. Everything is bundled inside one `Setup.exe`, which installs and runs with **no internet**.

By Sasanka Boruah, VU3INI, hamvu3ini@gmail.com

**New here? Read `VU3INI-Android-TV-Cleaner-Guide.pdf`**: what the app does and how to install and use it, with screenshots.

## Making the offline installer (once, on a PC with internet)

1. Your VU3INI logo is built in. It appears top-left on every screen of the app and is used for the `.exe` and installer icons. To use a different logo, put `vu3ini-logo.png` next to `Build-Installer.bat`.
2. Double-click **`Build-Installer.bat`**. It is self-contained: it carries its own copy of the files in `build\`, `src\` and `installer\` (kept here for reading and editing), so the .bat alone is enough.
3. Wait 20 to 40 minutes. The builder will:
   - download Python 3.12 (NuGet build), Eclipse Temurin JDK 17, the Android SDK (platform 34, build-tools 34.0.0,
     platform-tools), Gradle 8.9 and the CleanYourTV repo
   - download offline wheels for `tools\requirements.txt` and test an offline venv install
   - build the launcher online to fill Gradle's cache, then **build it again with `--offline`** to prove the bundle is complete
   - compile the app with Windows' built-in C# compiler
   - package everything with Inno Setup (it fetches a portable copy if you don't have it)
4. The result is `output\VU3INI-Android-TV-Cleaner-Setup-2.0.exe`, next to the .bat (about 500 to 700 MB). Copy it anywhere and
   install it with no internet.

The builder needs about 8 GB free on `C:` and works in `C:\VU3INI-build`. Change this with `-WorkDir D:\somewhere`;
the path must have no spaces. Downloads are cached, and a re-run after a finished bundle only redoes the installer step (use `-Rebuild` to start from scratch, e.g. after adding a logo).

## Installing and using it

Run the Setup. The default folder is `C:\VU3INI\ATVCleaner` (no spaces, no admin rights needed). The app is a
step-by-step wizard; the left side shows the steps, with a tick on each finished one. Nobody has to edit a file.

1. **Prepare the TV**: tick off Developer options, USB debugging and the same network, type the TV's IP
   (with a reachability check), and confirm "I have completed Step 1". Only then does Next unlock.
2. **Set up tools**: checks the bundled Python, JDK, Android SDK, Gradle and repo, creates the Python environment
   and points the launcher build at the bundled SDK. This is automatic and offline.
3. **Connect to the TV**: reads the model, codename, Android version, home app and installed apps. Nothing changes.
4. **Brand and model**: pick from all 456 tested TVs (122 brands). The app suggests the matching list from what it read,
   shows the testers' notes, and offers list versions where a TV has several. If no list fits, it can build one from a
   privacy audit of the TV.
5. **What to keep**: every app in the list, grouped as in the list, with what it is and whether it is on your TV.
   Untick what you use, or use the one-click "keep" switches (casting, USB media, Bluetooth speaker, voice
   assistant, streaming apps). Your choices are saved, and the app writes its own copy of the list.
6. **Clean the TV**: runs CleanYourTV's `disable.ps1`, which records the TV's state first so that Undo is exact.
7. **New home screen**: builds the CleanYourTV launcher offline and installs it. Choose the Live TV app (pre-filled),
   a theme with preview, apps per row, a greeting, and the dock apps and their order. Remote-key fixes are pre-ticked
   from the tested notes. The app then finishes the cleaning and offers to restart the TV. You can also skip this step.
8. **Finish and secure**: reminds you to switch debugging off and checks that the TV's debugging port is really closed.

**Maintenance and undo** (any time): undo all changes, check and re-apply after a TV firmware update, a privacy
audit report, restart the TV, change your choices, open a CleanYourTV PowerShell, and open your lists folder.

Your settings and generated lists are kept in `%APPDATA%\VU3INI\AndroidTVCleaner`. CleanYourTV's undo records
are in `%USERPROFILE%\.cleanyourtv`.

## Folder layout after install

```
C:\VU3INI\ATVCleaner\
  VU3INI Android TV Cleaner.exe
  Open-CleanYourTV-Shell.ps1
  python\        Python 3.12
  jdk\           Temurin JDK 17
  android-sdk\   platform 34, build-tools 34.0.0, platform-tools, licences
  gradle-home\   Gradle 8.9 + offline Maven cache
  cleanyourtv\   repo snapshot (tools\venv is created on first run)
  wheels\        offline Python packages
  bundle-info.txt, THIRD-PARTY-NOTICES.txt
```

One change is made to the repo snapshot: `launcher\build-and-install.ps1` calls Gradle with `--offline`.

## Publishing to GitHub

Double-click **`PUBLISH_TO_GITHUB.BAT`**. It:

- checks for Git and the GitHub CLI, and offers to install them with winget
- signs you in through your browser
- asks for the repository name (default `VU3INI-Android-TV-Cleaner`) and whether it is public or private
- creates the repository and uploads this folder

If `output\VU3INI-Android-TV-Cleaner-Setup-*.exe` exists, it can also publish it with the PDF guide as a GitHub
Release, so people can download the installer directly. Run it again any time to upload your changes.
Build results (`output\`, `.exe`, `.zip`) are kept out of the repository.

## Licences

The app is by VU3INI. Bundled components keep their own licences: CleanYourTV (MIT), Python (PSF), Temurin
(GPLv2 + Classpath Exception), Android SDK (Android SDK licence, accepted at build time), and Gradle and its
dependencies (Apache 2.0). See `THIRD-PARTY-NOTICES.txt`.
