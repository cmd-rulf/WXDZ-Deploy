FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PATH="/usr/src/app/.venv/bin:$PATH"

WORKDIR /usr/src/app

# 1. Add deadsnakes PPA for Python 3.12 on Ubuntu 22.04 (Bypasses 24.04 package conflicts)
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    && add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update

# 2. OS Dependencies, Python 3.12 & Build Tools (No 24.04 conflicts!)
RUN apt-get install -y --no-install-recommends \
    python3.12 python3.12-venv python3.12-dev python3.12-distutils \
    aria2 qbittorrent-nox ffmpeg p7zip-full unzip wget curl git \
    libmagic1 libmediainfo-dev libxml2 libxslt1.1 \
    libglib2.0-dev libsodium-dev libc-ares-dev libssl-dev libsqlite3-dev \
    libcurl4-openssl-dev libfreeimage-dev libpcre3-dev \
    libcrypto++-dev \
    build-essential autoconf autoconf-archive automake libtool libtool-bin pkg-config swig cmake \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Set Python 3.12 as default and install pip
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 && \
    ln -sf /usr/bin/python3.12 /usr/bin/python && \
    curl -sS https://bootstrap.pypa.io/get-pip.py | python3.12

# 3. RClone Install
RUN curl -s https://rclone.org/install.sh | bash

# 4. Install UV (Fast Package Manager)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# 5. Compile MEGA SDK (The Real MegaApi from C++ Source)
RUN git clone --depth 1 --branch v4.8.0 https://github.com/meganz/sdk.git /tmp/sdk && \
    cd /tmp/sdk && \
    ./autogen.sh && \
    ./configure --disable-silent-rules --enable-python --with-sodium --disable-examples && \
    make -j$(nproc) && \
    cd bindings/python && \
    python3 setup.py bdist_wheel && \
    cp dist/*.whl /tmp/mega_sdk.whl && \
    rm -rf /tmp/sdk

# 6. Setup Venv & Install MEGA SDK
RUN python3 -m venv .venv
RUN pip install --no-cache-dir /tmp/mega_sdk.whl && rm /tmp/mega_sdk.whl

# 7. MAGIC SYMLINKS (Custom names ko standard binaries se jodna)
RUN ln -sf /usr/bin/qbittorrent-nox /usr/local/bin/torrentgod && \
    ln -sf /usr/bin/qbittorrent-nox /usr/local/bin/stormtorrent && \
    ln -sf /usr/bin/aria2c /usr/local/bin/blitzfetcher && \
    ln -sf /usr/bin/aria2c /usr/local/bin/speeddemon && \
    ln -sf /usr/bin/ffmpeg /usr/local/bin/mediaforge && \
    ln -sf /usr/local/bin/rclone /usr/local/bin/ghostdrive && \
    echo -e '#!/bin/bash\nexit 0' > /usr/local/bin/newsripper && \
    chmod +x /usr/local/bin/newsripper

# 8. Install Base Requirements
COPY requirements.txt .
RUN uv pip install --no-cache -r requirements.txt || true

# 9. 🚨 WRAPPER HACK (Prevent update.py from sabotaging at runtime)
# Wrap UV
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
    chmod +x /usr/local/bin/uv

# Wrap PIP
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
    chmod +x /usr/src/app/.venv/bin/pip

# 10. Copy Code & Permissions
COPY . .
RUN chmod +x start.sh 2>/dev/null || true

# 11. ULTIMATE CMD (Aria2 Daemon Start + Bot Start)
CMD aria2c --enable-rpc --rpc-listen-all=true --rpc-allow-origin-all --daemon=true --log=aria2.log --log-level=notice && bash start.sh
