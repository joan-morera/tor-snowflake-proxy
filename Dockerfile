#
# Snowflake Proxy (from Source)
#
# Stage 1: Builder
#
FROM golang:latest AS builder

# Arguments
ARG SNOWFLAKE_VERSION

# 1. Build Snowflake Proxy
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
# Stage 2: Helper (for extracting system files)
# -----------------------------------------------------------------------------
FROM debian:trixie-slim AS helper

# Install dependencies to add Tor's repository.
RUN apt-get update && apt-get install -y \
    curl \
    gpg \
    gpg-agent \
    ca-certificates \
    debian-keyring \
    --no-install-recommends

# Add Tor Project Repository
# See: <https://support.torproject.org/apt/tor-deb-repo/>
RUN curl https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | gpg --dearmor | tee /usr/share/keyrings/tor-archive-keyring.gpg >/dev/null
RUN printf "deb [signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org trixie main\n" >> /etc/apt/sources.list.d/tor.list

# Install tor-geoipdb
RUN apt-get update && apt-get install -y \
    tor-geoipdb \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Stage 3: Final (Scratch)
# -----------------------------------------------------------------------------
FROM scratch
LABEL maintainer="JoanMorera"

# Copy Certificates
COPY --from=helper /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# Copy Timezone Info
COPY --from=helper /usr/share/zoneinfo /usr/share/zoneinfo

# Copy Tor GeoIP Databases
COPY --from=helper /usr/share/tor/geoip /usr/share/tor/geoip
COPY --from=helper /usr/share/tor/geoip6 /usr/share/tor/geoip6

# Copy Binary
COPY --from=builder /build/snowflake/proxy/proxy /bin/proxy

# Runtime Config
ENTRYPOINT ["/bin/proxy"]
