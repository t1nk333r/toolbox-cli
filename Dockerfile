FROM ubuntu:24.04
# C.UTF-8 keeps unicode filenames correct in yazi and the rest of the TUI tools.
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Identity of the login user. 568 is TrueNAS SCALE's `apps` id: the datasets
# this toolbox works on are mode 770 owned by root:568, so a login user outside
# group 568 cannot read them at all. Override for other hosts.
ARG PUID=568
ARG PGID=568
ARG USERNAME=toolbox
ENV TOOLBOX_USER=${USERNAME}

# Base tools + ffmpeg suite
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    ncdu \
    curl \
    git \
    wget \
    unzip \
    unrar \
    jq \
    file \
    7zip \
    zstd \
    pigz \
    less \
    neovim \
    ffmpeg \
    ffmpegthumbnailer \
    mediainfo \
    exiftool \
    imagemagick \
    fzf \
    ripgrep \
    bat \
    fd-find \
    htop \
    tmux \
    openssh-client \
    openssh-server \
    poppler-utils \
    rsync \
    && rm -rf /var/lib/apt/lists/*

# eza
RUN wget -qO /tmp/eza.tar.gz \
        "https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-musl.tar.gz" \
    && tar xzf /tmp/eza.tar.gz -C /tmp \
    && mv /tmp/eza /usr/local/bin/ \
    && rm -rf /tmp/eza*

# dua-cli — version resolved from the release redirect; needs no auth
RUN DUA_VERSION=$(curl -sILo /dev/null -w '%{url_effective}' \
        https://github.com/Byron/dua-cli/releases/latest \
        | sed 's#.*/tag/v##') \
    && [ -n "$DUA_VERSION" ] \
    && wget -qO /tmp/dua.tar.gz \
        "https://github.com/Byron/dua-cli/releases/latest/download/dua-v${DUA_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
    && tar xzf /tmp/dua.tar.gz -C /tmp \
    && find /tmp -name dua -type f -exec mv {} /usr/local/bin/ \; \
    && rm -rf /tmp/dua*

# yazi
RUN curl -Lo /tmp/yazi.zip \
        https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-musl.zip \
    && unzip /tmp/yazi.zip -d /tmp/yazi \
    && mv /tmp/yazi/yazi*/yazi /tmp/yazi/yazi*/ya /usr/local/bin/ \
    && rm -rf /tmp/yazi*

# glow — markdown renderer used by yazi's glow previewer
RUN GLOW_VERSION=$(curl -sILo /dev/null -w '%{url_effective}' \
        https://github.com/charmbracelet/glow/releases/latest \
        | sed 's#.*/tag/v##') \
    && [ -n "$GLOW_VERSION" ] \
    && wget -qO /tmp/glow.tar.gz \
        "https://github.com/charmbracelet/glow/releases/latest/download/glow_${GLOW_VERSION}_Linux_x86_64.tar.gz" \
    && tar xzf /tmp/glow.tar.gz -C /tmp \
    && find /tmp -name glow -type f -exec mv {} /usr/local/bin/ \; \
    && rm -rf /tmp/glow*

# Aliases
RUN echo 'alias cat="batcat --paging=never"' >> /etc/bash.bashrc \
    && echo 'alias bat="batcat --paging=never"' >> /etc/bash.bashrc \
    && echo 'alias ls="eza --icons"'            >> /etc/bash.bashrc \
    && echo 'alias ll="eza -la --icons"'        >> /etc/bash.bashrc \
    && echo 'alias la="eza -a --icons"'         >> /etc/bash.bashrc \
    && echo 'alias fd="fdfind"'                 >> /etc/bash.bashrc

# Login user. Ubuntu 24.04 ships a stock `ubuntu` account at uid 1000, which
# collides whenever PUID is 1000; drop it first. `|| true` because it does not
# exist on every base image.
RUN userdel -r ubuntu 2>/dev/null || true \
    && groupadd -g ${PGID} ${USERNAME} \
    && useradd -u ${PUID} -g ${PGID} -m -s /bin/bash ${USERNAME}

# LazyVim
RUN git clone https://github.com/LazyVim/starter /home/${USERNAME}/.config/nvim

# Config baked into image
COPY config/ /home/${USERNAME}/.config/

# Catches both the COPY and the git clone above, which run as root.
RUN chown -R ${PUID}:${PGID} /home/${USERNAME}

# SSH server: key-only, and you log in as the unprivileged user so anything
# written into a mounted dataset carries its ownership, not root's. sshd itself
# stays root (host keys, privilege separation, port 22), so there is no USER
# instruction here; use `docker exec -u 0` for apt and other root work.
RUN mkdir -p /run/sshd \
    && printf '%s\n' \
        'PermitRootLogin no' \
        'PasswordAuthentication no' \
        'PubkeyAuthentication yes' \
        'KbdInteractiveAuthentication no' \
        "AllowUsers ${USERNAME}" \
        'HostKey /etc/ssh/host_keys/ssh_host_ed25519_key' \
        'HostKey /etc/ssh/host_keys/ssh_host_rsa_key' \
        > /etc/ssh/sshd_config.d/toolbox.conf
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# `open <file>` sends a file back to the machine you connected from, via the
# reverse tunnel set up by scripts/toolbox-ssh. Pure shell — no GUI stack.
COPY container/open /usr/local/bin/open
RUN chmod +x /usr/local/bin/open \
    && ln -sf /usr/local/bin/open /usr/local/bin/xdg-open

# TCP 22 = SSH (shell, and the reverse tunnel that `open` streams through)
EXPOSE 22/tcp

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["sleep", "infinity"]
