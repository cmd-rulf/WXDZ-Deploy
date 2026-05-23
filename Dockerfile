FROM python:3.12-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/usr/src/app/.venv/bin:$PATH"

WORKDIR /usr/src/app

# 1. OS Dependencies & Binaries
RUN apt-get update && apt-get install -y --no-install-recommends \
    aria2 qbittorrent-nox ffmpeg p7zip-full unzip wget curl git \
    libmagic1 libmediainfo0v5 libmediainfo-dev libxml2 libxslt1.1 \
    libglib2.0-0 libsodium23 libc-ares2 libssl3 libsqlite3-0 \
    libcurl4 libfreeimage3 ca-certificates build-essential python3-dev \
    && rm -rf /var/lib/apt/lists/*

# 2. RClone Install
RUN curl -s https://rclone.org/install.sh | bash

# 3. MAGIC SYMLINKS (Custom names ko standard binaries se jodna)
RUN ln -sf /usr/bin/qbittorrent-nox /usr/local/bin/torrentgod && \
    ln -sf /usr/bin/qbittorrent-nox /usr/local/bin/stormtorrent && \
    ln -sf /usr/bin/aria2c /usr/local/bin/blitzfetcher && \
    ln -sf /usr/bin/aria2c /usr/local/bin/speeddemon && \
    ln -sf /usr/bin/ffmpeg /usr/local/bin/mediaforge && \
    ln -sf /usr/local/bin/rclone /usr/local/bin/ghostdrive && \
    echo -e '#!/bin/bash\nexit 0' > /usr/local/bin/newsripper && \
    chmod +x /usr/local/bin/newsripper

# 4. UV Installer & Venv Setup
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/bin/
RUN uv venv .venv

# 5. 🚀 GOD MODE MATRIX HACK (Auto-Fix pycrypto at Runtime)
# update.py baar-baar requirements.txt se pycrypto install kar deta hai.
# Hum uv aur pip ko wrap kar rahe hain taaki install hone ke turant baad 
# yeh automatically pycrypto ko uda de aur pycryptodome laga de!
RUN mv /usr/bin/uv /usr/bin/uv-original && \
    echo '#!/bin/bash' > /usr/bin/uv && \
    echo '/usr/bin/uv-original "$@"' >> /usr/bin/uv && \
    echo 'if [[ "$*" == *"install"* ]]; then' >> /usr/bin/uv && \
    echo '  /usr/bin/uv-original pip uninstall -y pycrypto >/dev/null 2>&1' >> /usr/bin/uv && \
    echo '  /usr/bin/uv-original pip install pycryptodome >/dev/null 2>&1' >> /usr/bin/uv && \
    echo 'fi' >> /usr/bin/uv && \
    chmod +x /usr/bin/uv

RUN mv /usr/local/bin/pip /usr/local/bin/pip-original || true
RUN echo '#!/bin/bash' > /usr/local/bin/pip && \
    echo '/usr/local/bin/pip-original "$@"' >> /usr/local/bin/pip && \
    echo 'if [[ "$*" == *"install"* ]]; then' >> /usr/local/bin/pip && \
    echo '  /usr/local/bin/pip-original uninstall -y pycrypto >/dev/null 2>&1' >> /usr/local/bin/pip && \
    echo '  /usr/local/bin/pip-original install pycryptodome >/dev/null 2>&1' >> /usr/local/bin/pip && \
    echo 'fi' >> /usr/local/bin/pip && \
    chmod +x /usr/local/bin/pip

# 6. Copy Requirements & Pre-install
COPY requirements.txt .
RUN uv pip install --no-cache -r requirements.txt || true
RUN uv pip install --no-cache pycryptodome && uv pip uninstall -y pycrypto || true

# 7. Copy Rest of the Code
COPY . .
RUN chmod +x start.sh 2>/dev/null || true

# 8. ULTIMATE CMD
CMD aria2c --enable-rpc --rpc-listen-all=true --rpc-allow-origin-all --daemon=true --log=aria2.log --log-level=notice && bash start.sh
