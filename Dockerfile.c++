# Stage 1: Final minimal image
FROM luxonis/depthai-library:v3.10.0 AS oakapp

# Define build argument for architecture
ARG TARGETARCH

# Install runtime dependencies. The base image already provides Python 3,
# pip, git, and the build toolchain; --no-upgrade avoids duplicating its
# packages in this layer.
RUN apt-get update && apt-get install -y --no-install-recommends --no-upgrade \
    libssl3 \
    libsqlite3-0 \
    libffi8 \
    libglib2.0-0 \
    zlib1g \
    ca-certificates \
    runit \
    nginx \
    openssl \
    wget \
    curl \
    jq \
    git \
    gettext-base \
    libgl1 \
    libxrender1 \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/python3 /usr/local/bin/python \
    && ln -s /usr/bin/pip3 /usr/local/bin/pip

# Create service directories
RUN mkdir -p /etc/service/nginx /etc/service/oak_webrtc /etc/service/connection

# Add service run scripts
COPY --chmod=755 services/nginx-run.sh /etc/service/nginx/run
COPY --chmod=755 services/oak_webrtc-run.sh /etc/service/oak_webrtc/run
COPY --chmod=755 services/connection-run.sh /etc/service/connection/run
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# Add oak_webrtc binary, downloaded from the Luxonis release bucket.
# OAK_WEBRTC_VERSION is empty by default, which installs the current stable release.
ARG OAK_WEBRTC_BASE_URL=https://webrtc-releases.luxonis.com
ARG OAK_WEBRTC_VERSION=
COPY --chmod=755 scripts/fetch-oak-webrtc.sh /tmp/fetch-oak-webrtc.sh
RUN OAK_WEBRTC_BASE_URL="$OAK_WEBRTC_BASE_URL" OAK_WEBRTC_VERSION="$OAK_WEBRTC_VERSION" \
    /tmp/fetch-oak-webrtc.sh \
    && rm /tmp/fetch-oak-webrtc.sh

# Configure nginx and SSL
COPY /nginx/setup.sh /tmp/setup_nginx.sh
RUN chmod +x /tmp/setup_nginx.sh && \
    /tmp/setup_nginx.sh && \
    rm /tmp/setup_nginx.sh
COPY /nginx/server.template /etc/nginx/templates/site.template
COPY /nginx/nginx.conf /etc/nginx/nginx.conf
