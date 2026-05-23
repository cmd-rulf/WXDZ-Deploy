# ==========================================
# STAGE 1: BUILD MEGA SDK (The Matrix Hack)
# ==========================================
FROM python:3.12-slim-bookworm AS megabuilder

ENV DEBIAN_FRONTEND=noninteractive
# Mega SDK compile karne ke liye C++ dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git build-essential autoconf automake libtool pkg-config swig \
    libcurl4-openssl-dev libssl-dev libsqlite3-dev libsodium-dev \
    libfreeimage-dev libpcre3-dev libcrypto++-dev \
    && rm -rf /var/lib/apt/lists/*

ENV MEGA_SDK_VERSION=4.8.0
# Meganz SDK clone aur Python bindings compile
RUN git clone --depth 1 --branch v${MEGA_SDK_VERSION} https://github.com/meganz/sdk.git /tmp/sdk && \
    cd /tmp/sdk && \
    ./autogen.sh && \
    ./configure --disable-silent-rules --enable-python --with-sodium --disable-examples && \
    make -j$(nproc) && \
    cd bindings/python && \
    python3 setup.py bdist_wheel

# ==========================================
# STAGE 2: FINAL PRODUCTION IMAGE
# ==========================================
FROM python:3.12-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/usr/src/app/.venv/bin:$PATH"

WORKDIR /usr/src/app

# 1. OS Dependencies & Binaries (Mega SDK runtime libs included)
RUN apt-get update && apt-get install -y --no-install-recommends \
    aria2 qbittorrent-nox ffmpeg p7zip-full unzip wget curl git \
    libmagic1 libmediainfo0v5 libmediainfo-dev libxml2 libxslt1.1 \
    libglib2.0-0 libsodium23 libc-ares2 libssl3 libsqlite3-0 \
    libcurl4 libfreeimage3 libpcre3 libcrypto++-dev \
    ca-certificates \
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

# 5. Main Dependencies (Pehle normal requirements install)
COPY requirements.txt .
RUN uv pip install --no-cache -r requirements.txt

# 6. 🚨 CRITICAL FIX: Overwrite PyPI mega.py with our compiled Mega SDK (MegaApi)
COPY --from=megabuilder /tmp/sdk/bindings/python/dist/*.whl /tmp/
RUN uv pip install --no-cache-dir --force-reinstall /tmp/*.whl && rm -rf /tmp/*.whl

# 7. Fix pycrypto SyntaxError (Python 3.12 compatibility)
RUN uv pip uninstall -y pycrypto || true
RUN uv pip install --no-cache "pycryptodome" "tenacity>=8.2.0"

# 8. Copy Rest of the Code
COPY . .
RUN chmod +x start.sh 2>/dev/null || true

# 9. ULTIMATE CMD (Aria2 Daemon Start + Bot Start)
CMD aria2c --enable-rpc --rpc-listen-all=true --rpc-allow-origin-all --daemon=true --log=aria2.log --log-level=notice && bash start.sh
