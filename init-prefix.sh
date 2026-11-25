#!/bin/bash
set -e

export WINEARCH=win64
export WINEDEBUG=-all
export WINEPREFIX=/root/server
export DISPLAY=:5.0

# winecfg and the VC++ installer need an X display in a headless build.
Xvfb :5 -screen 0 1024x768x16 &
sleep 1

# No mscoree override and no native dotnet48: wineboot installs the matching
# Wine Mono MSI from /usr/share/wine/mono while creating the prefix.
wineboot --init /nogui
wineserver -w

wine winecfg /v win10
wineserver -w

# Equivalent of `winetricks sound=disabled`.
wine reg add 'HKCU\Software\Wine\Drivers' /v Audio /t REG_SZ /d '' /f
wineserver -w

# Only the x64 VC++ 2015-2022 runtime is needed by the 64-bit server.
curl -fsSL -o /tmp/vc_redist.x64.exe https://aka.ms/vs/17/release/vc_redist.x64.exe
set +e
wine /tmp/vc_redist.x64.exe /install /quiet /norestart
vc_rc=$?
set -e
wineserver -w
rm -f /tmp/vc_redist.x64.exe
if [ "${vc_rc}" -ne 0 ] && [ "${vc_rc}" -ne 3010 ]; then
  echo "vc_redist.x64.exe failed with exit code ${vc_rc}"
  exit "${vc_rc}"
fi

# Wine Mono should have registered a .NET 4.x installation.
if ! wine reg query 'HKLM\Software\Microsoft\NET Framework Setup\NDP\v4\Full' /v Release >/dev/null 2>&1; then
  echo "Warning: .NET 4.x registry entry not found; check Wine Mono installation."
fi
