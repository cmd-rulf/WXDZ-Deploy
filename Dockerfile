FROM python:3.11-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1
ENV PYTHONDONTWRITEBYTECODE=1

WORKDIR /usr/src/app

# 1. OS Dependencies & Binaries Install (libmagic1 added for python-magic)
RUN apt-get update && apt-get install -y --no-install-recommends \
    aria2 \
    qbittorrent-nox \
    ffmpeg \
    p7zip-full \
    unzip \
    wget \
    curl \
    git \
    libmagic1 \
    libmediainfo0v5 \
    libmediainfo-dev \
    libxml2 \
    libxslt1.1 \
    libglib2.0-0 \
    libsodium23 \
    libc-ares2 \
    libssl3 \
    libsqlite3-0 \
    libcurl4 \
    libfreeimage3 \
    ca-certificates \
    build-essential \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# 2. RClone Install
RUN curl -s https://rclone.org/install.sh | bash

# 3. MAGIC SYMLINKS (Purane custom names ko naye standard binaries se jodna bina Python code change kiye)
RUN ln -sf /usr/bin/qbittorrent-nox /usr/local/bin/torrentgod && \
    ln -sf /usr/bin/aria2c /usr/local/bin/blitzfetcher && \
    ln -sf /usr/bin/aria2c /usr/local/bin/speeddemon && \
    ln -sf /usr/bin/ffmpeg /usr/local/bin/mediaforge && \
    ln -sf /usr/local/bin/rclone /usr/local/bin/ghostdrive && \
    echo -e '#!/bin/bash\nexit 0' > /usr/local/bin/newsripper && \
    chmod +x /usr/local/bin/newsripper

# 4. UV Installer (Fast pip operations)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/bin/

# 5. User & Venv Setup
RUN useradd -m botuser && chown -R botuser:botuser /usr/src/app
USER botuser
RUN uv venv .venv
ENV PATH="/usr/src/app/.venv/bin:$PATH"

# 6. Copy Requirements & Pre-install Dependencies (Force tenacity & mega.py)
COPY --chown=botuser:botuser requirements.txt .
RUN uv pip install --no-cache-dir -r requirements.txt "tenacity>=8.2.0" "mega.py"

# 7. Copy Rest of the Code
COPY --chown=botuser:botuser . .

# 8. Ensure start.sh is executable
RUN chmod +x start.sh 2>/dev/null || true

# 9. ULTIMATE CMD (Aria2 Daemon Start + Bot Start)
CMD aria2c --enable-rpc --rpc-listen-all=true --rpc-allow-origin-all --daemon=true --log=aria2.log --log-level=notice && bash start.sh
