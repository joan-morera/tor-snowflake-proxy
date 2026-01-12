#
# Snowflake Proxy (from Source)
#
# Stage 1: Builder (Build & Fetch Dependencies)
#
FROM debian:trixie-slim AS builder

# Install Build & Runtime Data Dependencies
# - build-essential, git, golang: for building
# - ca-certificates, curl, gpg, debian-keyring: for fetching Tor repo and data
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    debian-keyring \
    git \
    golang \
    gpg \
    gpg-agent \
    && rm -rf /var/lib/apt/lists/*

# Add Tor Project Repository (for tor-geoipdb)
# See: <https://support.torproject.org/apt/tor-deb-repo/>
RUN curl https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | gpg --dearmor | tee /usr/share/keyrings/tor-archive-keyring.gpg >/dev/null
RUN printf "deb [signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org trixie main\n" >> /etc/apt/sources.list.d/tor.list

# Install tor-geoipdb
RUN apt-get update && apt-get install -y \
    tor-geoipdb \
    && rm -rf /var/lib/apt/lists/*

# Arguments
ARG SNOWFLAKE_VERSION

# Build Snowflake Proxy
WORKDIR /build
RUN echo "[BUILD] Cloning Snowflake..." && \
    git clone https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/snowflake.git && \
    cd snowflake && \
    # Checkout specific commit if provided
    if [ -n "$SNOWFLAKE_VERSION" ] && [ "$SNOWFLAKE_VERSION" != "latest" ]; then \
        git checkout "$SNOWFLAKE_VERSION"; \
    fi && \
    cd proxy && \
    # Build Static Binary
    CGO_ENABLED=0 go build -o proxy -ldflags '-extldflags "-static" -w -s' .

# -----------------------------------------------------------------------------
# Stage 2: Final (Scratch)
# -----------------------------------------------------------------------------
FROM scratch
LABEL maintainer="JoanMorera"

# Copy Certificates
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# Copy Timezone Info
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo

# Copy Tor GeoIP Databases
COPY --from=builder /usr/share/tor/geoip /usr/share/tor/geoip
COPY --from=builder /usr/share/tor/geoip6 /usr/share/tor/geoip6

# Copy Binary
COPY --from=builder /build/snowflake/proxy/proxy /bin/proxy

# Runtime Config
ENTRYPOINT ["/bin/proxy"]
