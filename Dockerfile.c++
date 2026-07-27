# Stage 1: Final minimal image
FROM luxonis/depthai-library:a1b078ba480981b9e81251bfd37799be644052b9 AS oakapp

# Define build argument for architecture
ARG TARGETARCH

# Install runtime dependencies and create symlinks
RUN apt-get update && apt-get install -y --no-install-recommends \
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
    gettext \
	glibc-source \
    && ln -s /usr/local/python3.10/bin/python3.10 /usr/local/bin/python \
    && ln -s /usr/local/python3.10/bin/python3.10 /usr/local/bin/python3 \
    && ln -s /usr/local/python3.10/bin/python3.10 /usr/local/bin/python3.10 \
    && ln -s /usr/local/python3.10/bin/pip3.10 /usr/local/bin/pip \
    && ln -s /usr/local/python3.10/bin/pip3.10 /usr/local/bin/pip3

# Install DepthAI OS dependencies
RUN apt-get install -y libgl1 \
    libxrender1 \
    && rm -rf /var/lib/apt/lists/*

# Create service directories
RUN mkdir -p /etc/service/nginx /etc/service/oak_webrtc /etc/service/connection

# Add service run scripts
COPY --chmod=755 services/nginx-run.sh /etc/service/nginx/run
COPY --chmod=755 services/oak_webrtc-run.sh /etc/service/oak_webrtc/run
COPY --chmod=755 services/connection-run.sh /etc/service/connection/run
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# Add oak_webrtc binary, downloaded from the Luxonis release bucket.
# OAK_WEBRTC_VERSION is empty by default, which installs the current stable release.
ARG OAK_WEBRTC_BASE_URL=https://oakagent-releases.luxonis.com
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
