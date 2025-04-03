# Configure variables
$ndiSdkUrl = "https://downloads.ndi.tv/SDK/NDI_SDK/NDI%206%20SDK.exe"

# choco install visualstudio2022community --force --params '--add Microsoft.VisualStudio.Workload.NativeDesktop --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64.Spectre --add Microsoft.VisualStudio.Component.VC.ATL.Spectre' -y
# choco install msys2 -y

# configure msys2
# Set MSYS2_PATH_TYPE=inherit in msys2_shell.cmd
$msys2_root = "C:\tools\msys64"
$msys2_bin = "$msys2_root\usr\bin"
$msys2_shell = "$msys2_root\msys2_shell.cmd"
$env:MSYS2_BIN = "$msys2_bin\bash.exe"
$link = "$msys2_bin\link.exe"

# # Update packages
# Write-Host 'Updating packages...'
# for ($i = 0; $i -lt 2; $i++)
# {
#     Start-Process -Wait $msys2_shell -ArgumentList '-mingw64 -c "pacman -Syuu --noconfirm"'
# }

# # Install additional packages 
# $packages = @('mingw-w64-x86_64-nasm', 'mingw-w64-x86_64-gcc', 'mingw-w64-x86_64-yasm', 'mingw-w64-x86_64-SDL2', 'mingw-w64-x86_64-gcc-libs', 'make', 'pkgconfdiffutils', 'diffutils')
# foreach ($package in $packages)
# {
#     Write-Host "Installing $package..."
#     Start-Process -Wait $msys2_shell -ArgumentList "-mingw64 -c `"pacman -S $package --noconfirm`""
# }

# # Rename link.exe to prevent conflict with MSVC
if (Test-Path $link)
{
    Write-Host "Renaming $link..."
    Rename-Item -Path $link -NewName "$link.0000"
}

# Set MSYS2_BIN environment variable
Write-Host 'Setting MSYS2_BIN environment variable...'
#[System.Environment]::SetEnvironmentVariable('MSYS2_BIN', "$msys2_bin\bash.exe", "User")
$env:MSYS2_BIN = "$msys2_bin\bash.exe"

# Install ndi sdk
$ndiInstallerPath = "$env:TEMP\ndisdk.exe"
$appFound = ((Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*).DisplayName -Match "NDI 6 SDK").Length -gt 0
if ($appFound -ne $true) {
  try{
    # Download the file
    if (-not(Test-Path $ndiInstallerPath))
    {
        Invoke-WebRequest -Uri $ndiSdkUrl -OutFile $ndiInstallerPath
    }
  } catch {
    Write-Error "Failed to download NDI SDK"
    Exit 1
  }

  try {
    $NDI_installer = Start-Process "$ndiInstallerPath" -ArgumentList "/VERYSILENT" -PassThru
    Wait-Process -Id $NDI_installer.Id -Timeout 120
  } catch {
    Write-Error "Failed to install NDI SDK"
    Exit 1
  }

  $appFound = ((Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*).DisplayName -Match "NDI 6 SDK").Length -gt 0
  if ($appFound -ne $true) {
      Write-Error("Failed to install NDI SDK")
      Exit 1
  }
}


# # Copy NDI SDK files to MSYS2
# copy-item -Recurse -Verbose "C:\Program Files\NDI\NDI 6 SDK\Include\" -Destination "C:\tools\msys64\opt\"
# copy-item -Recurse -Verbose "C:\Program Files\NDI\NDI 6 SDK\Lib\x64\" -Destination  "C:\tools\msys64\opt\"

if (-not(Test-Path "C:\msys64\opt\ndi.lib")) {
    copy-item -Verbose "C:\msys64\opt\Processing.NDI.Lib.x64.lib" -Destination "C:\msys64\opt\ndi.lib"
}


# Validate FFmpeg build environment
if (-not $env:MSYS2_BIN)
{
    Write-Error(
        'ERROR: MSYS2_BIN environment variable not set. ' +
        'Use SetUpFFmpegBuildEnvironment.ps1 to set up the FFmpeg build environment.')
    exit 1
}

if (-not (Test-Path $env:MSYS2_BIN))
{
    Write-Error(
        "ERROR: MSYS2_BIN environment variable is not valid - $env:MSYS2_BIN does not exist. " +
        'Use SetUpFFmpegBuildEnvironment.ps1 to set up the FFmpeg build environment.')
    exit 1
}

# Locate Visual Studio installation
if (-not (Get-Module -Name VSSetup -ListAvailable))
{
    Install-Module -Name VSSetup -Scope CurrentUser -Force
}

$requiredComponents = 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
$vsInstance = Get-VSSetupInstance -All | Select-VSSetupInstance -Require $requiredComponents -Latest

if ($vsInstance -eq $null)
{
    Write-Error(
        'ERROR: Could not find a valid Visual Studio installation. ' +
        'Ensure Visual Studio and VC++ x64/x86 build tools are installed.')
    exit 1
}

# Import Microsoft.VisualStudio.DevShell.dll for Enter-VsDevShell cmdlet
Import-Module "$($vsInstance.InstallationPath)\Common7\Tools\Microsoft.VisualStudio.DevShell.dll"

# Initialize the build environment
Enter-VsDevShell `
    -VsInstallPath $vsInstance.InstallationPath

# Export full current PATH from environment into MSYS2 and set compiler to mingw64
$env:MSYS2_PATH_TYPE = 'inherit'
$env:MSYSTEM = "MINGW64"

# Build FFmpeg
& $env:MSYS2_BIN --login -x "/FFmpeg/configure" "--arch=x86_64" "--target-os=win64" "--enable-cross-compile" "--toolchain=msvc" "--enable-shared" "--disable-encoders" "--disable-filters" "--disable-muxers" "--enable-libndi_newtek" "--extra-cflags='-I/opt/'" "--extra-ldflags='/LIBPATH:C:/tools/msys64/opt/'" "--extra-ldflags='-CETCOMPAT'"
& $env:MSYS2_BIN --login -x "make" "-j``nproc``" "install"

$buildResult = $?

# TODO: Fix below build issue
# INSTALL libavformat/avformat.dll
# LD      libavdevice/avdevice-61.dll
#    Creating library libavdevice/avdevice.lib and object libavdevice/avdevice.exp
# libndi_newtek_dec.o : error LNK2019: unresolved external symbol __imp__NDIlib_initialize referenced in function _ndi_read_header
# libndi_newtek_enc.o : error LNK2001: unresolved external symbol __imp__NDIlib_initialize
# libndi_newtek_dec.o : error LNK2019: unresolved external symbol __imp__NDIlib_find_destroy referenced in function _ndi_read_close
# libndi_newtek_dec.o : error LNK2019: unresolved external symbol __imp__NDIlib_find_get_current_sources referenced in function _ndi_read_header
# libndi_newtek_dec.o : error LNK2019: unresolved external symbol __imp__NDIlib_find_wait_for_sources referenced in function _ndi_read_header
# libndi_newtek_dec.o : error LNK2019: unresolved external symbol __imp__NDIlib_recv_create_v3 referenced in function _ndi_read_header
# libndi_newtek_dec.o : error LNK2019: unresolved external symbol __imp__NDIlib_recv_destroy referenced in function _ndi_read_close
# libndi_newtek_dec.o : error LNK2019: unresolved external symbol __imp__NDIlib_recv_capture_v2 referenced in function _ndi_read_packet
# libndi_newtek_dec.o : error LNK2019: unresolved external symbol __imp__NDIlib_recv_free_video_v2 referenced in function _ndi_read_packet
# libndi_newtek_dec.o : error LNK2019: unresolved external symbol __imp__NDIlib_recv_free_metadata referenced in function _ndi_read_packet
# libndi_newtek_dec.o : error LNK2019: unresolved external symbol __imp__NDIlib_recv_set_tally referenced in function _ndi_read_header
# libndi_newtek_dec.o : error LNK2019: unresolved external symbol __imp__NDIlib_find_create2 referenced in function _ndi_read_header
# libndi_newtek_dec.o : error LNK2019: unresolved external symbol __imp__NDIlib_recv_free_audio referenced in function _ndi_read_packet
# libndi_newtek_dec.o : error LNK2019: unresolved external symbol __imp__NDIlib_util_audio_to_interleaved_16s referenced in function _ndi_read_packet
# libndi_newtek_enc.o : error LNK2019: unresolved external symbol __imp__NDIlib_send_create referenced in function _ndi_write_header
# libndi_newtek_enc.o : error LNK2019: unresolved external symbol __imp__NDIlib_send_destroy referenced in function _ndi_write_trailer
# libndi_newtek_enc.o : error LNK2019: unresolved external symbol __imp__NDIlib_send_send_video_async_v2 referenced in function _ndi_write_packet
# libndi_newtek_enc.o : error LNK2019: unresolved external symbol __imp__NDIlib_util_send_send_audio_interleaved_16s referenced in function _ndi_write_packet
# C:\tools\msys64\opt\\ndi.lib : warning LNK4272: library machine type 'x64' conflicts with target machine type 'x86'
# libavdevice\avdevice-61.dll : fatal error LNK1120: 17 unresolved externals
# make: *** [/FFmpeg/ffbuild/library.mak:132: libavdevice/avdevice-61.dll] Error 96