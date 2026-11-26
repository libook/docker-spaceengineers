#!/bin/bash
# Local liveness check. Deliberately does NOT call the Steam Web API:
# GetServersAtAddress only knows publicly listed servers (so it fails for
# PUBLIC_IP=127.0.0.1, NAT, and private servers), lags behind the real state,
# and is rate limited to about one request per minute per IP.
set -u

# 1. The dedicated server must be running under Wine.
found=1
for cmdline in /proc/[0-9]*/cmdline; do
  if tr '\0' ' ' < "${cmdline}" 2>/dev/null | grep -q 'SpaceEngineersDedicated\.exe'; then
    found=0
    break
  fi
done
[ "${found}" -eq 0 ] || exit 1

# 2. Its game port must be bound. /proc/net/udp prints ports in hex, so
#    UDP 27016 (the SE default, also published in docker-compose) is 6988.
port_hex=$(printf '%04x' 27016)
grep -qi ":${port_hex} " /proc/net/udp /proc/net/udp6 2>/dev/null || exit 1

exit 0
