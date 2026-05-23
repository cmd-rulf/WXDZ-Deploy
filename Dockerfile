FROM python:3.12-slim-bookworm

# ==========================================
# ENV
# ==========================================
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    SETUPTOOLS_USE_DISTUTILS=local

WORKDIR /usr/src/app

# ==========================================
# INSTALL ALL SYSTEM DEPENDENCIES
# ==========================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    g++ \
    make \
    python3-dev \
    libc6-dev \
    git \
    curl \
    wget \
    unzip \
    p7zip-full \
    ffmpeg \
    aria2 \
    qbittorrent-nox \
    autoconf \
    automake \
    libtool \
    pkg-config \
    swig \
    cmake \
    libffi-dev \
    libssl-dev \
    libcurl4-openssl-dev \
    libsqlite3-dev \
    libsodium-dev \
    libfreeimage-dev \
    libpcre3-dev \
    libcrypto++-dev \
    zlib1g-dev \
    libuv1-dev \
    libc-ares-dev \
    libmagic1 \
    libmediainfo0v5 \
    ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ==========================================
# VERIFY GCC EXISTS
# ==========================================
RUN gcc --version

# ==========================================
# INSTALL UV
# ==========================================
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# ==========================================
# INSTALL RCLONE
# ==========================================
RUN curl https://rclone.org/install.sh | bash

# ==========================================
# CUSTOM ALIASES
# ==========================================
RUN ln -sf /usr/bin/qbittorrent-nox /usr/local/bin/torrentgod && \
    ln -sf /usr/bin/qbittorrent-nox /usr/local/bin/stormtorrent && \
    ln -sf /usr/bin/aria2c /usr/local/bin/blitzfetcher && \
    ln -sf /usr/bin/aria2c /usr/local/bin/speeddemon && \
    ln -sf /usr/bin/ffmpeg /usr/local/bin/mediaforge && \
    ln -sf /usr/local/bin/rclone /usr/local/bin/ghostdrive

# ==========================================
# UPGRADE BUILD TOOLS
# ==========================================
RUN pip install --upgrade \
    pip \
    setuptools \
    wheel \
    cython

# ==========================================
# COPY REQUIREMENTS
# ==========================================
COPY requirements.txt .

# ==========================================
# REMOVE BROKEN PACKAGES
# ==========================================
RUN sed -i '/pycrypto/d' requirements.txt || true && \
    sed -i '/mega/d' requirements.txt || true

# ==========================================
# INSTALL TGCRYPTO FIRST
# ==========================================
RUN pip install --no-cache-dir tgcrypto

# ==========================================
# INSTALL REQUIREMENTS
# ==========================================
RUN uv pip install --system -r requirements.txt

# ==========================================
# FIXED PYTHON PACKAGES
# ==========================================
RUN pip install --no-cache-dir \
    pycryptodome \
    "tenacity>=8.2.0"

# ==========================================
# BUILD MEGA SDK
# ==========================================
RUN git clone --depth 1 --branch v4.8.0 \
    https://github.com/meganz/sdk.git /tmp/sdk && \
    cd /tmp/sdk && \
    ./autogen.sh && \
    ./configure \
    --enable-python \
    --with-sodium \
    --disable-examples && \
    make -j$(nproc) && \
    cd bindings/python && \
    python setup.py install

# ==========================================
# CLEANUP
# ==========================================
RUN rm -rf /tmp/sdk

# ==========================================
# COPY APP
# ==========================================
COPY . .

RUN chmod +x start.sh || true

# ==========================================
# START
# ==========================================
CMD aria2c \
    --enable-rpc \
    --rpc-listen-all=true \
    --rpc-allow-origin-all \
    --daemon=true \
    --log=aria2.log \
    --log-level=notice \
    && bash start.sh
