# check=skip=SecretsUsedInArgOrEnv
# Debian 13 (trixie), pinned by digest; trixie-slim tag last updated 2026-11-24
FROM debian:trixie-slim@sha256:8aa5a7bf5a1955bddbe7d74fcdd0b91ab30e74362a8b73af672b0481b35b44a0

WORKDIR /root

# ARG only available during build
# never env DEBIAN_FRONTEND=noninteractive !!
ARG DEBIAN_FRONTEND=noninteractive
ARG WINEBRANCH=stable
# Experiment: Wine 11 + Wine Mono 10.4.1 (no native dotnet48).
# Wine 11.0.0.0~trixie-1 expects exactly this Mono version and SHA.
ARG WINEVERSION=11.0.0.0~trixie-1
ARG MONO_VERSION=10.4.1
ARG MONO_SHA256=071f4b2887e1c97a11d791ff3d65be9429eed6dec4c2708888bfd546ba358e23

ENV WINEARCH=win64
ENV WINEDEBUG=-all
ENV WINEPREFIX=/root/server
# Not a secret: suppresses the legacy apt-key warning. The BuildKit secret
# check matches the name, so the check is skipped at the top of this file.
ENV APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1

RUN \
  dpkg --add-architecture i386 && \
  apt-get -qq -y update && \
  apt-get upgrade -y -qq && \
  apt-get install -y -qq ca-certificates curl gnupg2 wget && \
  # add repository keys
  mkdir -pm755 /etc/apt/keyrings && \
  wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key && \
  # add repositories
  echo "deb http://ftp.us.debian.org/debian trixie main non-free" > /etc/apt/sources.list.d/non-free.list && \
  wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/debian/dists/trixie/winehq-trixie.sources
RUN \
  apt-get update -qq && \
  echo steam steam/question select "I AGREE" | debconf-set-selections && \
  echo steam steam/license note '' | debconf-set-selections && \
  apt-get install -qq -y \
  libfaudio0:i386 \
  libfaudio0
RUN \
  apt-get install -qq -y --install-recommends \
  winehq-${WINEBRANCH}=${WINEVERSION} \
  wine-${WINEBRANCH}-i386=${WINEVERSION} \
  wine-${WINEBRANCH}-amd64=${WINEVERSION} \
  wine-${WINEBRANCH}=${WINEVERSION} \
  steamcmd \
  xvfb \
  cabextract

# Wine 11.0.0.0~trixie-1 looks for this exact MSI and verifies its SHA.
RUN \
  mkdir -p /usr/share/wine/mono && \
  curl -fsSL -o "/usr/share/wine/mono/wine-mono-${MONO_VERSION}-x86.msi" \
    "https://dl.winehq.org/wine/wine-mono/${MONO_VERSION}/wine-mono-${MONO_VERSION}-x86.msi" && \
  echo "${MONO_SHA256}  /usr/share/wine/mono/wine-mono-${MONO_VERSION}-x86.msi" | sha256sum -c -

# Wine Mono + x64 VC++ prefix (no native dotnet48)
COPY init-prefix.sh /root/
RUN \
  chmod +x /root/init-prefix.sh && \
  /root/init-prefix.sh && \
  rm -f /root/init-prefix.sh && \
  # Remove stuff we do not need anymore to reduce docker size
  apt-get remove -qq -y \
  gnupg2 && \
  apt-get autoremove -qq -y && \
  apt-get -qq clean autoclean && \
  rm -rf /var/lib/{apt,dpkg,cache,log}/

COPY healthcheck.sh /root/
HEALTHCHECK --interval=60s --timeout=60s --start-period=600s --retries=3 CMD [ "/root/healthcheck.sh" ]

COPY entrypoint.sh /root/
ENTRYPOINT ["/root/entrypoint.sh"]
