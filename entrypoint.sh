#!/bin/bash
# VARIABLES
GAME_DIR="/appdata/space-engineers/SpaceEngineersDedicated"
INSTANCES_DIR="/appdata/space-engineers/instances"
PLUGIN_DIR="/appdata/space-engineers/plugins"
WINEPREFIX="${WINEPREFIX:-/root/server}"
export WINEPREFIX
INSTANCE_DIR="${INSTANCES_DIR}/${INSTANCE_NAME}"
CONFIG_PATH="${INSTANCE_DIR}/SpaceEngineers-Dedicated.cfg"
VDF_PATH="${GAME_DIR}/steamapps/libraryfolders.vdf"
LINUX_GAME_DIR="${GAME_DIR}"
WINDOWS_GAME_DIR='Z:\\appdata\\space-engineers\\SpaceEngineersDedicated'
INSTANCE_IP=$(hostname -I | sed "s= ==g")

# The Linux steamcmd and the Windows Steam client (used by the server under
# Wine) expect different path formats in libraryfolders.vdf. Keep the file in
# the format of whichever tool runs next.
set_vdf_library_path() {
  local new_path="$1" replacement
  [ -f "${VDF_PATH}" ] || return 0
  replacement=$(printf '%s' "${new_path}" | sed 's/\\/\\\\/g')
  sed -E -i "s#(\"path\"[[:space:]]*\")[^\"]*SpaceEngineersDedicated[^\"]*\"#\\1${replacement}\"#g" "${VDF_PATH}"
}

# Make sure the Windows Steam client has a library it can use. If steamcmd did
# not create libraryfolders.vdf, write a minimal one pointing at the server dir.
write_windows_vdf() {
  if [ -f "${VDF_PATH}" ]; then
    set_vdf_library_path "${WINDOWS_GAME_DIR}"
    return 0
  fi
  mkdir -p "$(dirname "${VDF_PATH}")"
  cat > "${VDF_PATH}" <<EOF
"libraryfolders"
{
	"0"
	{
		"path"		"${WINDOWS_GAME_DIR}"
	}
}
EOF
}

# The Steam client DLL resolves its library through SteamPath in the Wine
# prefix, not through the game directory. Create a minimal Steam tree and
# point its library at the game directory, where steamcmd cached the mods.
prepare_wine_steam() {
  local steam_dir="${WINEPREFIX}/drive_c/Program Files (x86)/Steam"
  mkdir -p "${steam_dir}/steamapps/common" \
           "${steam_dir}/steamapps/downloading" \
           "${steam_dir}/config" \
           "${steam_dir}/logs" \
           "${GAME_DIR}/steamapps/common" \
           "${GAME_DIR}/steamapps/downloading" \
           "${GAME_DIR}/steamapps/workshop/content/244850"
  # Keep the prefix workshop directory in sync with the persistent cache.
  ln -sfn "${GAME_DIR}/steamapps/workshop" "${steam_dir}/steamapps/workshop" || true

  local windows_steam_dir='C:\\Program Files (x86)\\Steam'
  cat > "${steam_dir}/steamapps/libraryfolders.vdf" <<EOF
"libraryfolders"
{
	"0"
	{
		"path"		"${windows_steam_dir}"
		"label"		""
		"contentid"	"0"
		"totalsize"	"0"
		"update_clean_bytes_tally"	"0"
		"time_last_update_corruption"	"0"
		"apps"
		{
		}
	}
	"1"
	{
		"path"		"${WINDOWS_GAME_DIR}"
		"label"		""
		"contentid"	"0"
		"totalsize"	"0"
		"update_clean_bytes_tally"	"0"
		"time_last_update_corruption"	"0"
		"apps"
		{
		}
	}
}
EOF
  cp -f "${steam_dir}/steamapps/libraryfolders.vdf" "${steam_dir}/config/libraryfolders.vdf"

  # The prefix lives in the image and is recreated when the container is
  # replaced, so write the registry keys on every start.
  wine reg add 'HKCU\Software\Valve\Steam' /v SteamPath /t REG_SZ /d 'c:/program files (x86)/steam' /f >/dev/null 2>&1 \
    || echo "Warning: could not set SteamPath registry key."
  wine reg add 'HKLM\SOFTWARE\Valve\Steam' /v InstallPath /t REG_SZ /d 'C:\Program Files (x86)\Steam' /f >/dev/null 2>&1 \
    || echo "Warning: could not set HKLM InstallPath registry key."
  wine reg add 'HKLM\SOFTWARE\WOW6432Node\Valve\Steam' /v InstallPath /t REG_SZ /d 'C:\Program Files (x86)\Steam' /f >/dev/null 2>&1 \
    || echo "Warning: could not set WOW6432Node InstallPath registry key."

  echo "Prepared Wine Steam library at ${steam_dir}"
}

# The dedicated server keeps its own workshop cache under the -path instance
# directory. Seed it from the Linux steamcmd cache so the server does not have
# to download mods through the Wine Steam client.
sync_instance_workshop() {
  local src="${GAME_DIR}/steamapps/workshop"
  local dest="${INSTANCE_DIR}"
  local item name
  [ -d "${src}/content/244850" ] || return 0
  mkdir -p "${dest}/content/244850"
  for item in "${src}/content/244850"/*; do
    [ -d "${item}" ] || continue
    name=$(basename "${item}")
    mkdir -p "${dest}/content/244850/${name}"
    if ! cp -a "${item}/." "${dest}/content/244850/${name}/"; then
      echo "Warning: failed to sync workshop item ${name}."
    fi
  done
  if [ -f "${src}/appworkshop_244850.acf" ]; then
    if ! cp -f "${src}/appworkshop_244850.acf" "${dest}/appworkshop_244850.acf"; then
      echo "Warning: failed to copy appworkshop_244850.acf."
    fi
  fi
  echo "Synced workshop cache to ${dest}/content/244850"
}

set_vdf_library_path "${LINUX_GAME_DIR}"

echo "-------------------------------INSTALL & UPDATE------------------------------"
/usr/games/steamcmd +force_install_dir ${GAME_DIR} +login anonymous +@sSteamCmdForcePlatformType windows +app_update 298740 +quit

# The dedicated server ships outdated Steamworks DLLs which cannot resolve the
# Steam library, so workshop downloads fail with
# "Staging/Install library folder not found". Updated copies live in the app
# root; copy them into the directory the server binary loads them from.
echo "------------------------FIX OUTDATED STEAMWORKS DLLS-------------------------"
for STEAM_DLL in steamclient64.dll tier0_s64.dll vstdlib_s64.dll; do
  if [ -f "${GAME_DIR}/${STEAM_DLL}" ]; then
    cp -f "${GAME_DIR}/${STEAM_DLL}" "${GAME_DIR}/DedicatedServer64/${STEAM_DLL}"
    echo "Updated DedicatedServer64/${STEAM_DLL}"
  else
    echo "Warning: ${GAME_DIR}/${STEAM_DLL} not found, skipping."
  fi
done

# Download configured workshop mods with the native Linux steamcmd. This keeps
# large downloads out of Wine and caches them before the server starts.
echo "-----------------------------SYNC WORKSHOP MODS------------------------------"
MOD_IDS=$(grep -hoE '<PublishedFileId>[0-9]+</PublishedFileId>' \
  "${CONFIG_PATH}" \
  "${INSTANCE_DIR}"/Saves/*/Sandbox_config.sbc 2>/dev/null \
  | grep -oE '[0-9]+' | sort -u)

if [ -n "${MOD_IDS}" ]; then
  WORKSHOP_ARGS=""
  for MOD_ID in ${MOD_IDS}; do
    WORKSHOP_ARGS="${WORKSHOP_ARGS} +workshop_download_item 244850 ${MOD_ID}"
  done
  echo "Downloading workshop mods: $(echo ${MOD_IDS} | tr '\n' ' ')"
  # WORKSHOP_ARGS is intentionally unquoted: it is a list of steamcmd arguments.
  if ! /usr/games/steamcmd +force_install_dir "${GAME_DIR}" +login anonymous ${WORKSHOP_ARGS} +quit; then
    echo "Warning: workshop download failed; the server will retry the missing mods."
  fi
  for MOD_ID in ${MOD_IDS}; do
    if [ -d "${GAME_DIR}/steamapps/workshop/content/244850/${MOD_ID}" ]; then
      echo "Workshop item ${MOD_ID}: cached"
    else
      echo "Warning: workshop item ${MOD_ID} is not cached."
    fi
  done
else
  echo "No workshop mods found in config or world saves."
fi

echo "-------------------------SYNC INSTANCE MOD CACHE----------------------------"
sync_instance_workshop

echo "---------------------------FIX STEAM LIBRARY PATHS---------------------------"
write_windows_vdf
prepare_wine_steam

echo "---------------------------------UPDATE CONFIG-------------------------------"
# update IP to host external ip
CURRENT_IP=$(grep -oEi '<IP>(.*)</IP>' ${CONFIG_PATH} | sed -E "s=<IP>|</IP>==g")
sed -i "s=<IP>.*</IP>=<IP>${INSTANCE_IP}</IP>=g" ${CONFIG_PATH}

# update world save path
CURRENT_WORLDNAME=$(grep -oEi '<WorldName>(.*)</WorldName>' ${CONFIG_PATH} | sed -E "s=<WorldName>|</WorldName>==g")
SAVE_PATH="Z:\\\\appdata\\\\space-engineers\\\\instances\\\\${INSTANCE_NAME}\\\\Saves\\\\${CURRENT_WORLDNAME}";
sed -E -i "s=<LoadWorld />|<LoadWorld.*LoadWorld>=<LoadWorld>${SAVE_PATH}</LoadWorld>=g" ${CONFIG_PATH}

echo "---------------------------------UPDATE PLUGINS------------------------------"
PLUGIN_COUNT=$(ls -1 ${PLUGIN_DIR}/*.dll | wc -l)
echo "Found ${PLUGIN_COUNT} plugins in ${PLUGIN_DIR}"

if [ "${PLUGIN_COUNT}" -gt "0" ]; then 
  PLUGINS_STRING="<Plugins>$(ls -1 /appdata/space-engineers/plugins/*.dll |\
  sed -E "s=(.+\.dll)=<string>\1</string>=g" |\
  tr -d "\n" )</Plugins>"
else
  PLUGINS_STRING="<Plugins />"
fi

sed -E -i "s=<Plugins />|<Plugins.*Plugins>=${PLUGINS_STRING}=g" ${CONFIG_PATH}

echo "-----------------------------CURRENT CONFIGURATION---------------------------"
echo "GAME_DIR=$GAME_DIR"
echo "CONFIG_PATH=$CONFIG_PATH"
echo "INSTANCE_IP=$INSTANCE_IP"
echo "CURRENT_IP=$CURRENT_IP"
echo "CURRENT_WORLDNAME=$CURRENT_WORLDNAME"
echo "SAVE_PATH=$SAVE_PATH"
## END UPDATES ##
wine --version
echo "----------------------------------START GAME---------------------------------"
# mkdir first to fix possible no such file or directory on rm
mkdir -p ${INSTANCES_DIR}/${INSTANCE_NAME}
rm ${INSTANCES_DIR}/${INSTANCE_NAME}/*.log
cd ${GAME_DIR}/DedicatedServer64/
wine SpaceEngineersDedicated.exe -noconsole -ignorelastsession -path Z:\\appdata\\space-engineers\\instances\\${INSTANCE_NAME}
echo "-----------------------------------END GAME----------------------------------"
sleep 1
echo "-----------------------------------BYE !!!!----------------------------------"
