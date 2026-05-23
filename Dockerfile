FROM python:3.10-slim-bookworm AS megabuilder
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    python3-dev \
    gcc \
    g++ \
    make \
    autoconf \
    automake \
    libtool \
    m4 \
    pkg-config \
    swig \
    cmake \
    libsodium-dev \
    libc-ares-dev \
    libssl-dev \
    libcrypto++-dev \
    libsqlite3-dev \
    libcurl4-openssl-dev \
    libfreeimage-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*
ENV MEGA_SDK_VERSION=4.8.0
RUN git clone --depth 1 --branch v${MEGA_SDK_VERSION} https://github.com/meganz/sdk.git /tmp/sdk && \
    cd /tmp/sdk && \
    ./autogen.sh && \
    ./configure \
        --disable-silent-rules \
        --enable-python \
        --with-sodium \
        --disable-examples && \
    make -j1 && \
    cd bindings/python && \
    python3 setup.py bdist_wheel

# Stage 2 — Final lightweight runtime image
# =========================================================
FROM python:3.10-slim-bookworm
ENV PYTHONUNBUFFERED=1 \
    DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/usr/local/bin:$PATH"
WORKDIR /usr/src/app
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    curl \
    git \
    ffmpeg \
    aria2 \
    qbittorrent-nox \
    p7zip-full \
    unzip \
    libmagic1 \
    libglib2.0-0 \
    libsodium23 \
    libc-ares2 \
    libssl3 \
    libsqlite3-0 \
    libcurl4 \
    libfreeimage3 \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
RUN curl https://rclone.org/install.sh | bash
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/bin/
COPY --from=megabuilder /tmp/sdk/bindings/python/dist/*.whl /tmp/
RUN pip install --no-cache-dir /tmp/*.whl && \
    rm -rf /tmp/*.whl
RUN useradd -m botuser && \
    mkdir -p /downloads /temp && \
    chown -R botuser:botuser /usr/src/app /downloads /temp
RUN ln -sf $(which qbittorrent-nox) /usr/local/bin/stormtorrent && \
    ln -sf $(which aria2c) /usr/local/bin/blitzfetcher && \
    ln -sf $(which ffmpeg) /usr/local/bin/mediaforge && \
    ln -sf $(which rclone) /usr/local/bin/ghostdrive
USER botuser
RUN uv venv .venv
ENV PATH="/usr/src/app/.venv/bin:$PATH"

COPY requirements.txt .
RUN uv pip install --no-cache-dir -r requirements.txt
COPY --chown=botuser:botuser . .

ENV MALLOC_ARENA_MAX=2
ENV QBT_PROFILE=/tmp/qbt
ENV TMPDIR=/tmp

CMD ["bash", "start.sh"]
