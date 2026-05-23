# ==========================================
# STAGE 1: BUILD MEGA SDK (The Real MegaApi)
# ==========================================
FROM python:3.12-slim-bookworm AS megabuilder

ENV DEBIAN_FRONTEND=noninteractive
# C++ dependencies for MEGA SDK (libuv1-dev fixed!)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git build-essential autoconf automake libtool pkg-config swig \
    libcurl4-openssl-dev libssl-dev libsqlite3-dev libsodium-dev \
    libfreeimage-dev libpcre3-dev libcrypto++-dev cmake \
    zlib1g-dev libuv1-dev \
    && rm -rf /var/lib/apt/lists/*

ENV MEGA_SDK_VERSION=4.8.0
# Compile MEGA SDK from source
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

# 1. OS Dependencies (libuv1 added for runtime)
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
    libpcre3 \
    libcrypto++-dev \
    libuv1 \
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
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/
RUN uv venv .venv

# 5. Install Base Requirements
COPY requirements.txt .
RUN uv pip install --no-cache -r requirements.txt || true

# 6. 🚨 CRITICAL FIX: Install our compiled Mega SDK (MegaApi)
COPY --from=megabuilder /tmp/sdk/bindings/python/dist/*.whl /tmp/
RUN uv pip install --no-cache-dir --force-reinstall /tmp/*.whl && rm -rf /tmp/*.whl

# 7. Fix Pycrypto & Tenacity
RUN uv pip uninstall -y pycrypto || true
RUN uv pip install --no-cache "pycryptodome" "tenacity>=8.2.0"

# 8. WRAPPER HACK (Prevent update.py from ruining the venv at runtime)
RUN mv /usr/local/bin/uv /usr/local/bin/uv-original && \
    echo '#!/bin/bash' > /usr/local/bin/uv && \
    echo 'ARGS=()' >> /usr/local/bin/uv && \
    echo 'for arg in "$@"; do' >> /usr/local/bin/uv && \
    echo '  if [[ "$arg" == *requirements.txt ]]; then' >> /usr/local/bin/uv && \
    echo '    grep -vEi "^(mega|mega\.py|pycrypto)" "$arg" > /tmp/safe_req.txt 2>/dev/null || true' >> /usr/local/bin/uv && \
    echo '    ARGS+=("/tmp/safe_req.txt")' >> /usr/local/bin/uv && \
    echo '  elif [[ "$arg" == "mega" || "$arg" == "mega.py" || "$arg" == "pycrypto" ]]; then continue' >> /usr/local/bin/uv && \
    echo '  else ARGS+=("$arg"); fi' >> /usr/local/bin/uv && \
    echo 'done' >> /usr/local/bin/uv && \
    echo '/usr/local/bin/uv-original "${ARGS[@]}"' >> /usr/local/bin/uv && \
    echo '/usr/local/bin/uv-original pip install --no-cache "tenacity>=8.2.0" "pycryptodome" >/dev/null 2>&1' >> /usr/local/bin/uv && \
    echo '/usr/local/bin/uv-original pip uninstall -y pycrypto >/dev/null 2>&1' >> /usr/local/bin/uv && \
    chmod +x /usr/local/bin/uv

RUN mv /usr/src/app/.venv/bin/pip /usr/src/app/.venv/bin/pip-original && \
    echo '#!/bin/bash' > /usr/src/app/.venv/bin/pip && \
    echo 'ARGS=()' >> /usr/src/app/.venv/bin/pip && \
    echo 'for arg in "$@"; do' >> /usr/src/app/.venv/bin/pip && \
    echo '  if [[ "$arg" == *requirements.txt ]]; then' >> /usr/src/app/.venv/bin/pip && \
    echo '    grep -vEi "^(mega|mega\.py|pycrypto)" "$arg" > /tmp/safe_req.txt 2>/dev/null || true' >> /usr/src/app/.venv/bin/pip && \
    echo '    ARGS+=("/tmp/safe_req.txt")' >> /usr/src/app/.venv/bin/pip && \
    echo '  elif [[ "$arg" == "mega" || "$arg" == "mega.py" || "$arg" == "pycrypto" ]]; then continue' >> /usr/src/app/.venv/bin/pip && \
    echo '  else ARGS+=("$arg"); fi' >> /usr/src/app/.venv/bin/pip && \
    echo 'done' >> /usr/src/app/.venv/bin/pip && \
    echo '/usr/src/app/.venv/bin/pip-original "${ARGS[@]}"' >> /usr/src/app/.venv/bin/pip && \
    echo '/usr/src/app/.venv/bin/pip-original install --no-cache "tenacity>=8.2.0" "pycryptodome" >/dev/null 2>&1' >> /usr/src/app/.venv/bin/pip && \
    echo '/usr/src/app/.venv/bin/pip-original uninstall -y pycrypto >/dev/null 2>&1' >> /usr/src/app/.venv/bin/pip && \
    chmod +x /usr/src/app/.venv/bin/pip

# 9. Copy Rest of the Code
COPY . .
RUN chmod +x start.sh 2>/dev/null || true

# 10. ULTIMATE CMD
CMD aria2c --enable-rpc --rpc-listen-all=true --rpc-allow-origin-all --daemon=true --log=aria2.log --log-level=notice && bash start.sh
