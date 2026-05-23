# ==========================================
# STAGE 1 — Build Mega SDK Wheel
# ==========================================
FROM python:3.12-slim-bookworm AS mega-builder

ENV DEBIAN_FRONTEND=noninteractive
ENV SETUPTOOLS_USE_DISTUTILS=local
ENV MEGA_SDK_VERSION=4.8.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    git build-essential autoconf automake libtool pkg-config swig \
    libcurl4-openssl-dev libssl-dev libsqlite3-dev libsodium-dev \
    libfreeimage-dev libpcre3-dev libcrypto++-dev cmake \
    zlib1g-dev libuv1-dev libc-ares-dev \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --upgrade pip setuptools wheel

RUN git clone --depth 1 --branch v${MEGA_SDK_VERSION} \
    https://github.com/meganz/sdk.git /tmp/sdk && \
    cd /tmp/sdk && \
    ./autogen.sh && \
    ./configure \
    --enable-python \
    --with-sodium \
    --disable-examples && \
    make -j$(nproc) && \
    cd bindings/python && \
    python setup.py bdist_wheel

# ==========================================
# STAGE 2 — Final Runtime Image
# ==========================================
FROM python:3.12-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/usr/src/app/.venv/bin:$PATH"

WORKDIR /usr/src/app

# ==========================================
# System Dependencies
# ==========================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    aria2 \
    qbittorrent-nox \
    ffmpeg \
    p7zip-full \
    unzip \
    curl \
    wget \
    git \
    ca-certificates \
    libmagic1 \
    libmediainfo0v5 \
    libsodium23 \
    libc-ares2 \
    libssl3 \
    libsqlite3-0 \
    libcurl4 \
    libfreeimage3 \
    libpcre3 \
    libuv1 \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

# ==========================================
# Install Rclone
# ==========================================
RUN curl https://rclone.org/install.sh | bash

# ==========================================
# Custom Binary Aliases
# ==========================================
RUN ln -sf /usr/bin/qbittorrent-nox /usr/local/bin/torrentgod && \
    ln -sf /usr/bin/aria2c /usr/local/bin/blitzfetcher && \
    ln -sf /usr/bin/ffmpeg /usr/local/bin/mediaforge && \
    ln -sf /usr/local/bin/rclone /usr/local/bin/ghostdrive

# ==========================================
# Install UV
# ==========================================
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# ==========================================
# Create Virtual Environment
# ==========================================
RUN uv venv /usr/src/app/.venv

# ==========================================
# Install Python Requirements
# ==========================================
COPY requirements.txt .

RUN sed -i '/pycrypto/d' requirements.txt && \
    sed -i '/mega/d' requirements.txt || true

RUN uv pip install --system -r requirements.txt

# ==========================================
# Install Fixed Dependencies
# ==========================================
RUN uv pip install --system \
    pycryptodome \
    "tenacity>=8.2.0"

# ==========================================
# Install Mega SDK Wheel
# ==========================================
COPY --from=mega-builder /tmp/sdk/bindings/python/dist/*.whl /tmp/

RUN pip install /tmp/*.whl && rm -rf /tmp/*.whl

# ==========================================
# Copy Project Files
# ==========================================
COPY . .

RUN chmod +x start.sh || true

# ==========================================
# Health Fixes
# ==========================================
RUN pip install --upgrade pip setuptools wheel

# ==========================================
# Start Services
# ==========================================
CMD aria2c \
    --enable-rpc \
    --rpc-listen-all=true \
    --rpc-allow-origin-all \
    --daemon=true \
    --log=aria2.log \
    --log-level=notice \
    && bash start.sh
