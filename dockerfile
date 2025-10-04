FROM debian:13 AS downloader
LABEL org.opencontainers.image.source=https://github.com/joshhighet/isolator

ARG TOR_VERSION=14.5.7
ARG CADDY_VERSION=2.10.2

# build-time deps in single layer
RUN apt-get update && apt-get install -y \
    wget \
    xz-utils \
    git \
    ca-certificates \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# download and extract in parallel, single layer
RUN set -ex && \
    wget -q --show-progress --progress=bar:force:noscroll \
        -O /tmp/tor-browser.tar.xz \
        "https://dist.torproject.org/torbrowser/${TOR_VERSION}/tor-browser-linux-x86_64-${TOR_VERSION}.tar.xz" && \
    wget -q --show-progress --progress=bar:force:noscroll \
        -O /tmp/caddy.tar.gz \
        "https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_amd64.tar.gz" && \
    git clone --depth=1 --single-branch \
        https://github.com/novnc/noVNC.git /tmp/noVNC && \
    mkdir -p /opt/tor-browser && \
    tar -xf /tmp/tor-browser.tar.xz -C /opt/ && \
    tar -xzf /tmp/caddy.tar.gz -C /opt/ && \
    chmod +x /opt/caddy && \
    rm -rf /tmp/*.tar.xz /tmp/*.tar.gz

# runtime
FROM debian:13 AS runtime
LABEL org.opencontainers.image.source=https://github.com/joshhighet/isolator

# environment setup first (most stable)
ENV USER=toruser
ENV HOME=/home/${USER}
ENV TOR_FORCE_NET_CONFIG=0

# system packages (stable, cache-friendly)
RUN apt-get update && apt-get install -y \
    openbox \
    tigervnc-standalone-server \
    tigervnc-common \
    tigervnc-tools \
    wget \
    curl \
    netcat-openbsd \
    net-tools \
    novnc \
    openssl \
    bash \
    wmctrl \
    ffmpeg \
    inotify-tools \
    zenity \
    x11-utils \
    x11-xserver-utils \
    --no-install-recommends \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# user and directories (stable structure)
RUN useradd -m ${USER} -s /usr/bin/bash && \
    mkdir -p /home/${USER}/certs \
             /home/${USER}/.vnc \
             /home/${USER}/.config/openbox \
             /etc/caddy && \
    openssl req -x509 -newkey rsa:4096 \
        -keyout /home/${USER}/certs/key.pem \
        -out /home/${USER}/certs/cert.pem \
        -days 365 -nodes -subj "/CN=isolator" && \
    touch /home/${USER}/.Xauthority \
          /home/${USER}/.Xresources

# binaries from downloader stage (changes with versions)
COPY --from=downloader /opt/tor-browser /home/${USER}/tor-browser
COPY --from=downloader /opt/caddy /usr/local/bin/caddy
COPY --from=downloader /tmp/noVNC /home/${USER}/noVNC

# config files (changes most frequently)
COPY xstartup /home/${USER}/.vnc/xstartup
COPY entrypoint.sh /entrypoint.sh
COPY launch-browser.sh /home/toruser/launch-browser.sh
COPY logging.sh /home/${USER}/logging.sh
COPY index.html /home/${USER}/noVNC/index.html
COPY user.js /home/${USER}/user.js
COPY bookmarks.html /home/${USER}/tor-browser/Browser/TorBrowser/Data/Browser/profile.default/bookmarks.html
COPY caddyfile /etc/caddy/caddyfile
COPY rc.xml /home/${USER}/.config/openbox/rc.xml
COPY autostart.sh /home/${USER}/.config/openbox/autostart.sh

# permissions and ownership (final step)
RUN chmod +x /home/${USER}/.vnc/xstartup \
             /entrypoint.sh \
             /home/toruser/launch-browser.sh \
             /home/${USER}/.config/openbox/autostart.sh \
             /usr/local/bin/caddy && \
    chown -R ${USER}:${USER} /home/${USER} && \
    chmod 700 /home/${USER}/.vnc && \
    chmod 600 /home/${USER}/certs/*.pem

# security hardening
RUN echo 'toruser:!' | chpasswd -e && \
    usermod -L ${USER}

# container metadata and configuration
VOLUME ["/mount"]
EXPOSE 6080/tcp 9222/tcp

# health monitoring
HEALTHCHECK --interval=15s --timeout=10s --start-period=30s --retries=3 \
  CMD DISPLAY=:1 wmctrl -l | grep -q "Tor Browser" && \
      pgrep -f "novnc_proxy" > /dev/null && \
      nc -z localhost 5901 && \
      curl --fail --insecure --max-time 5 "https://localhost:$(echo ${PORT:-6080})" > /dev/null 2>&1

# runtime user (non-root)
USER ${USER}
WORKDIR ${HOME}

# startup
ENTRYPOINT ["/entrypoint.sh"]
CMD []
