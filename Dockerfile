FROM python:3.12-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PATH="/usr/src/app/.venv/bin:$PATH" \
    LD_LIBRARY_PATH="/usr/local/lib:$LD_LIBRARY_PATH"

WORKDIR /usr/src/app

RUN chmod 777 /usr/src/app

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
    mediainfo \
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

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

RUN curl https://rclone.org/install.sh | bash

RUN ln -sf /usr/bin/qbittorrent-nox /usr/local/bin/torrentgod && \
    ln -sf /usr/bin/qbittorrent-nox /usr/local/bin/stormtorrent && \
    ln -sf /usr/bin/aria2c /usr/local/bin/speeddemon && \
    ln -sf /usr/bin/aria2c /usr/local/bin/blitzfetcher && \
    ln -sf /usr/bin/ffmpeg /usr/local/bin/vidwarlock && \
    ln -sf /usr/bin/ffmpeg /usr/local/bin/mediaforge && \
    ln -sf /usr/bin/ffprobe /usr/local/bin/ffprobe && \
    ln -sf /usr/bin/mediainfo /usr/local/bin/mediainfo && \
    ln -sf /usr/local/bin/rclone /usr/local/bin/cloudphantom && \
    ln -sf /usr/local/bin/rclone /usr/local/bin/ghostdrive

RUN python -m venv .venv

RUN .venv/bin/python -m ensurepip --upgrade

RUN .venv/bin/pip install --upgrade \
    pip \
    setuptools \
    wheel \
    cython

COPY requirements.txt .

RUN .venv/bin/pip install --no-cache-dir -r requirements.txt

RUN git clone --depth 1 --branch v4.8.0 \
    https://github.com/meganz/sdk.git /tmp/sdk && \
    cd /tmp/sdk && \
    ./autogen.sh && \
    ./configure \
    --enable-python \
    --with-sodium \
    --disable-examples && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    cd bindings/python && \
    /usr/src/app/.venv/bin/python setup.py install

RUN rm -rf /tmp/sdk

COPY . .

RUN sed -i 's/link_id = (await telegraph.create_page(title="MediaInfo X", content=tc))\\["path"\\]/try:\\n    tc = tc if tc else "Failed to fetch mediainfo."\\nexcept:\\n    tc = "Failed to fetch mediainfo."\\n\\nlink_id = (await telegraph.create_page(title="MediaInfo X", content=tc))["path"]/g' /usr/src/app/bot/modules/mediainfo.py || true

RUN chmod +x start.sh || true

CMD ["bash", "start.sh"]
